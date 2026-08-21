"""Bounded, in-memory hybrid text extraction for supporting documents."""

from __future__ import annotations

import asyncio
import base64
import logging
from io import BytesIO
from typing import Protocol

from pypdf import PdfReader, PdfWriter

from app.schemas.document_extraction import (
    DocumentExtractionResult,
    VisionExtractionOutput,
)
from app.schemas.supporting_documents import SupportingDocumentInput
from app.services.diagnostics import log_development_event
from app.services.exceptions import (
    AgentServiceError,
    ProviderConfigurationError,
    UnsupportedProviderError,
    VisionCapabilityUnavailableError,
)
from app.services.model_provider import (
    ModelMedia,
    ModelProvider,
    request_structured_media_output,
)

_MIN_USABLE_TEXT_CHARACTERS = 40
_HIGH_CONFIDENCE_TEXT_CHARACTERS = 80
_MAX_RENDERED_PAGE_DIMENSION = 2_000
_HANDWRITTEN_SINHALA_WARNING = (
    "Handwritten Sinhala text could not be verified reliably. Manual review is required."
)
_UNCERTAIN_TEXT_WARNING = (
    "Document text could not be extracted reliably. Manual review is required."
)
_VISION_UNAVAILABLE_WARNING = (
    "Vision analysis is not configured for this scanned or image document. "
    "Manual review is required."
)
_VISION_FAILURE_WARNING = (
    "Vision analysis is temporarily unavailable for this scanned or image document. "
    "Manual review is required."
)
logger = logging.getLogger(__name__)


class VisionTextExtractor(Protocol):
    async def extract(
        self,
        *,
        document_id: str,
        media: list[ModelMedia],
    ) -> VisionExtractionOutput: ...


class ModelVisionTextExtractor:
    def __init__(self, provider: ModelProvider, *, timeout_seconds: float) -> None:
        self._provider = provider
        self._timeout_seconds = timeout_seconds

    async def extract(
        self,
        *,
        document_id: str,
        media: list[ModelMedia],
    ) -> VisionExtractionOutput:
        return await request_structured_media_output(
            self._provider,
            output_schema=VisionExtractionOutput,
            instructions=(
                "Perform conservative OCR only. Return visible text, language, whether the "
                "content is printed or handwritten, confidence, and short safe warnings. "
                "Support printed English and Sinhala best-effort. Never guess unreadable text, "
                "never translate or transliterate names, and mark uncertain handwriting or "
                "Sinhala as Low/Unknown confidence. Do not return hidden reasoning."
            ),
            input_data={"documentId": document_id},
            media=media,
            timeout_seconds=self._timeout_seconds,
            invocation_name="document_vision_ocr",
        )


class HybridDocumentExtractor:
    def __init__(
        self,
        vision_extractor: VisionTextExtractor,
        *,
        max_pdf_pages: int,
        max_extracted_characters: int,
        extraction_timeout_seconds: float,
    ) -> None:
        self._vision_extractor = vision_extractor
        self._max_pdf_pages = max_pdf_pages
        self._max_extracted_characters = max_extracted_characters
        self._timeout_seconds = extraction_timeout_seconds

    async def extract(
        self, document: SupportingDocumentInput
    ) -> DocumentExtractionResult:
        try:
            result = await asyncio.wait_for(
                self._extract(document), timeout=self._timeout_seconds
            )
        except TimeoutError:
            result = _failed_extraction(
                document.document_id,
                "Document extraction timed out. Manual review is required.",
            )
        except Exception:
            # Provider, parser, decompression, and malformed-output details are private.
            result = _failed_extraction(document.document_id, _UNCERTAIN_TEXT_WARNING)
        log_development_event(
            logger,
            "supporting_document_extraction_completed",
            document_type=document.document_type,
            content_type=document.content_type,
            extraction_method=result.extraction_method,
            extracted_character_count=len(result.extracted_text),
            readable=result.readable,
            confidence=result.confidence_label,
        )
        return result

    async def _extract(
        self, document: SupportingDocumentInput
    ) -> DocumentExtractionResult:
        content = base64.b64decode(document.content_base64, validate=True)
        warnings: list[str] = []
        media: list[ModelMedia]

        if document.content_type == "application/pdf":
            text, bounded_pdf, pdf_warnings = await asyncio.to_thread(
                _extract_pdf_text,
                content,
                self._max_pdf_pages,
                self._max_extracted_characters,
            )
            warnings.extend(pdf_warnings)
            if _usable_character_count(text) >= _MIN_USABLE_TEXT_CHARACTERS:
                detected_language = _detect_language(text)
                confidence = (
                    "High"
                    if _usable_character_count(text) >= _HIGH_CONFIDENCE_TEXT_CHARACTERS
                    else "Medium"
                )
                return DocumentExtractionResult(
                    document_id=document.document_id,
                    readable=True,
                    extracted_text=text,
                    extraction_method="PdfText",
                    detected_language=detected_language,
                    confidence_label=confidence,
                    content_style="Printed",
                    needs_vision_fallback=False,
                    warnings=_unique_warnings(warnings),
                )
            warnings.append(
                "Selectable PDF text was insufficient; bounded vision OCR was used."
            )
            media = await asyncio.to_thread(
                _render_pdf_pages,
                bounded_pdf,
                self._max_pdf_pages,
            )
        else:
            media = [ModelMedia(content_type=document.content_type, content=content)]

        try:
            vision = await self._vision_extractor.extract(
                document_id=document.document_id,
                media=media,
            )
        except (
            ProviderConfigurationError,
            UnsupportedProviderError,
            VisionCapabilityUnavailableError,
        ):
            return _failed_extraction(
                document.document_id,
                _VISION_UNAVAILABLE_WARNING,
                warnings=warnings,
            )
        except AgentServiceError:
            return _failed_extraction(
                document.document_id,
                _VISION_FAILURE_WARNING,
                warnings=warnings,
            )
        text, truncated = _truncate(vision.extracted_text, self._max_extracted_characters)
        if truncated:
            warnings.append("Extracted text was truncated at the configured character limit.")
        if vision.warnings:
            warnings.append("Vision OCR reported uncertain or unreadable content.")
        confidence = vision.confidence_label
        if vision.content_style in {"Handwritten", "Mixed"} and confidence == "High":
            confidence = "Medium"
        if vision.detected_language in {"Sinhala", "Mixed"} and vision.content_style in {
            "Handwritten",
            "Mixed",
            "Unknown",
        }:
            confidence = "Low" if confidence != "Unknown" else "Unknown"
            warnings.append(_HANDWRITTEN_SINHALA_WARNING)

        readable = _usable_character_count(text) >= _MIN_USABLE_TEXT_CHARACTERS
        if not readable:
            text = ""
            confidence = "Unknown"
            warnings.append(_UNCERTAIN_TEXT_WARNING)

        return DocumentExtractionResult(
            document_id=document.document_id,
            readable=readable,
            extracted_text=text,
            extraction_method="VisionOcr",
            detected_language=vision.detected_language,
            confidence_label=confidence,
            content_style=vision.content_style,
            needs_vision_fallback=False,
            warnings=_unique_warnings(warnings),
        )


def _extract_pdf_text(
    content: bytes,
    max_pages: int,
    max_characters: int,
) -> tuple[str, bytes, list[str]]:
    reader = PdfReader(BytesIO(content), strict=False)
    page_count = len(reader.pages)
    pages_to_process = min(page_count, max_pages)
    warnings: list[str] = []
    if page_count > max_pages:
        warnings.append("PDF pages beyond the configured page limit were not processed.")

    fragments: list[str] = []
    current_length = 0
    character_truncated = False
    for index in range(pages_to_process):
        page_text = reader.pages[index].extract_text() or ""
        remaining = max_characters - current_length
        if remaining <= 0:
            character_truncated = True
            break
        if len(page_text) > remaining:
            fragments.append(page_text[:remaining])
            character_truncated = True
            break
        fragments.append(page_text)
        current_length += len(page_text)
    if character_truncated:
        warnings.append("Extracted text was truncated at the configured character limit.")

    writer = PdfWriter()
    for index in range(pages_to_process):
        writer.add_page(reader.pages[index])
    bounded_buffer = BytesIO()
    writer.write(bounded_buffer)
    return "\n".join(fragments).strip(), bounded_buffer.getvalue(), warnings


def _render_pdf_pages(content: bytes, max_pages: int) -> list[ModelMedia]:
    import pypdfium2 as pdfium

    document = pdfium.PdfDocument(content)
    rendered: list[ModelMedia] = []
    try:
        for index in range(min(len(document), max_pages)):
            page = document[index]
            try:
                width, height = page.get_size()
                largest_dimension = max(width, height)
                if largest_dimension <= 0:
                    raise ValueError("PDF page has invalid dimensions")
                scale = min(1.25, _MAX_RENDERED_PAGE_DIMENSION / largest_dimension)
                bitmap = page.render(scale=scale)
                try:
                    image = bitmap.to_pil()
                    buffer = BytesIO()
                    image.save(buffer, format="PNG", optimize=True)
                    rendered.append(
                        ModelMedia(content_type="image/png", content=buffer.getvalue())
                    )
                finally:
                    bitmap.close()
            finally:
                page.close()
    finally:
        document.close()
    if not rendered:
        raise ValueError("PDF contained no renderable pages")
    return rendered


def _detect_language(text: str) -> str:
    sinhala = sum("\u0d80" <= character <= "\u0dff" for character in text)
    latin = sum(character.isascii() and character.isalpha() for character in text)
    if sinhala and latin:
        return "Mixed"
    if sinhala:
        return "Sinhala"
    if latin:
        return "English"
    return "Unknown"


def _usable_character_count(text: str) -> int:
    return sum(character.isalnum() for character in text)


def _truncate(text: str, limit: int) -> tuple[str, bool]:
    if len(text) <= limit:
        return text, False
    return text[:limit], True


def _unique_warnings(warnings: list[str]) -> list[str]:
    return list(dict.fromkeys(item.strip()[:1000] for item in warnings if item.strip()))


def _failed_extraction(
    document_id: str,
    warning: str,
    *,
    warnings: list[str] | None = None,
) -> DocumentExtractionResult:
    return DocumentExtractionResult(
        document_id=document_id,
        readable=False,
        extracted_text="",
        extraction_method="None",
        detected_language="Unknown",
        confidence_label="Unknown",
        content_style="Unknown",
        needs_vision_fallback=True,
        warnings=_unique_warnings([*(warnings or []), warning]),
    )
