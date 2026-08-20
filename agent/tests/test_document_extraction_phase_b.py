from __future__ import annotations

import asyncio
import base64
import logging
from io import BytesIO
from typing import Any

import pytest
from pypdf import PdfWriter
from pypdf.generic import DecodedStreamObject, DictionaryObject, NameObject

from app.schemas.document_extraction import VisionExtractionOutput
from app.schemas.supporting_documents import SupportingDocumentInput
from app.services.document_extraction import HybridDocumentExtractor
from app.services.exceptions import ModelInvocationError
from app.services.model_provider import ModelProvider
from app.services.supporting_document_verification import ModelSupportingDocumentVerifier


def _input(content: bytes, *, content_type="application/pdf", document_type="IncomeProof"):
    return SupportingDocumentInput.model_validate(
        {
            "documentId": "document-1",
            "documentType": document_type,
            "originalFileName": "evidence.pdf",
            "contentType": content_type,
            "sizeBytes": len(content),
            "contentBase64": base64.b64encode(content).decode("ascii"),
        }
    )


def _pdf(*page_texts: str) -> bytes:
    writer = PdfWriter()
    font = DictionaryObject(
        {
            NameObject("/Type"): NameObject("/Font"),
            NameObject("/Subtype"): NameObject("/Type1"),
            NameObject("/BaseFont"): NameObject("/Helvetica"),
        }
    )
    font_ref = writer._add_object(font)
    for text in page_texts:
        page = writer.add_blank_page(width=612, height=792)
        page[NameObject("/Resources")] = DictionaryObject(
            {
                NameObject("/Font"): DictionaryObject(
                    {NameObject("/F1"): font_ref}
                )
            }
        )
        if text:
            escaped = text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
            stream = DecodedStreamObject()
            stream.set_data(f"BT /F1 12 Tf 72 720 Td ({escaped}) Tj ET".encode("latin-1"))
            page[NameObject("/Contents")] = writer._add_object(stream)
    buffer = BytesIO()
    writer.write(buffer)
    return buffer.getvalue()


class FakeVisionExtractor:
    def __init__(self, output: VisionExtractionOutput | None = None) -> None:
        self.output = output or VisionExtractionOutput(
            extracted_text="Readable printed English income statement for Ada Lovelace ACME Limited",
            detected_language="English",
            confidence_label="High",
            content_style="Printed",
        )
        self.calls = []

    async def extract(self, *, document_id, media):
        self.calls.append((document_id, media))
        return self.output


class NeverVisionExtractor(FakeVisionExtractor):
    async def extract(self, **kwargs):
        raise AssertionError("Digital PDF text should not use vision")


class SlowVisionExtractor(FakeVisionExtractor):
    async def extract(self, **kwargs):
        await asyncio.sleep(0.1)
        return self.output


class FailedVisionExtractor(FakeVisionExtractor):
    async def extract(self, **kwargs):
        raise ModelInvocationError


class FactProvider(ModelProvider):
    def __init__(self, output: Any) -> None:
        self.output = output
        self.inputs = []

    async def generate_structured(self, *, output_schema, instructions, input_data):
        del output_schema, instructions
        self.inputs.append(input_data)
        if isinstance(self.output, Exception):
            raise self.output
        return self.output


class SlowFactProvider(FactProvider):
    async def generate_structured(self, **kwargs):
        await asyncio.sleep(0.1)
        return await super().generate_structured(**kwargs)


def _extractor(vision, *, pages=10, characters=50_000, timeout=1):
    return HybridDocumentExtractor(
        vision,
        max_pdf_pages=pages,
        max_extracted_characters=characters,
        extraction_timeout_seconds=timeout,
    )


@pytest.mark.asyncio
async def test_digital_pdf_uses_local_selectable_text_first() -> None:
    text = "Income Proof Applicant Ada Lovelace Employer ACME Limited Monthly Income 5000"
    result = await _extractor(NeverVisionExtractor()).extract(_input(_pdf(text)))

    assert result.readable is True
    assert result.extraction_method == "PdfText"
    assert result.detected_language == "English"
    assert "Ada Lovelace" in result.extracted_text


@pytest.mark.asyncio
async def test_digital_pdf_text_is_sent_only_to_text_fact_provider() -> None:
    provider = FactProvider(
        _fact_output(income_amount=5000, pay_period="monthly", employer_name="ACME")
    )
    verifier = ModelSupportingDocumentVerifier(
        provider,
        _extractor(NeverVisionExtractor()),
        timeout_seconds=1,
        max_model_input_characters=200,
    )

    result = (await verifier.verify([
        _input(_pdf("Income proof for Ada Lovelace at ACME, monthly income 5000."))
    ]))[0]

    assert result.extraction_method == "PdfText"
    assert provider.inputs[0]["extractedText"].startswith("Income proof")


@pytest.mark.asyncio
async def test_selectable_income_pdf_preserves_normalized_allowed_facts(
    caplog: pytest.LogCaptureFixture,
) -> None:
    model_output = _fact_output(
        income_amount="LKR 185,000",
        pay_period="July 2026",
        employer_name="Example Solutions (Pvt) Ltd",
        applicant_name="Test Applicant",
        job_title="Software Engineer",
        document_date="01 August 2026",
    )
    provider = FactProvider(model_output)
    verifier = ModelSupportingDocumentVerifier(
        provider,
        _extractor(NeverVisionExtractor()),
        timeout_seconds=1,
        max_model_input_characters=20_000,
    )
    pdf_text = (
        "INCOME PROOF | Employee Name: Test Applicant | Job Title: Software Engineer | "
        "Employer: Example Solutions (Pvt) Ltd | Gross Monthly Income: LKR 185,000 | "
        "Pay Period: July 2026 | Payment Date: 01 August 2026"
    )

    with caplog.at_level(logging.DEBUG):
        result = (await verifier.verify([_input(_pdf(pdf_text))]))[0]

    assert result.readable is True
    assert result.detected_document_category == "IncomeProof"
    assert result.extraction_method == "PdfText"
    assert result.confidence_label == "High"
    assert result.requires_manual_review is False
    assert result.extracted_facts.applicant_name == "Test Applicant"
    assert result.extracted_facts.income_amount == 185000
    assert result.extracted_facts.pay_period == "July 2026"
    assert result.extracted_facts.employer_name == "Example Solutions (Pvt) Ltd"
    assert result.extracted_facts.document_date == "2026-08-01"
    assert result.extracted_facts.job_title is None
    assert "event=supporting_document_extraction_completed" in caplog.text
    assert "document_type=IncomeProof" in caplog.text
    assert "content_type=application/pdf" in caplog.text
    assert "extraction_method=PdfText" in caplog.text
    assert "extracted_character_count=" in caplog.text
    assert "readable=True" in caplog.text
    assert "confidence=High" in caplog.text
    assert "fact_analysis_ran=True" in caplog.text
    assert "populated_allowed_fields=applicantName,incomeAmount,payPeriod,employerName,documentDate" in caplog.text
    assert pdf_text not in caplog.text
    assert base64.b64encode(_pdf(pdf_text)).decode("ascii") not in caplog.text


@pytest.mark.asyncio
async def test_empty_scanned_pdf_triggers_bounded_rendered_vision_fallback() -> None:
    vision = FakeVisionExtractor()
    result = await _extractor(vision).extract(_input(_pdf("")))

    assert result.extraction_method == "VisionOcr"
    assert len(vision.calls) == 1
    assert vision.calls[0][1][0].content_type == "image/png"
    assert "insufficient" in " ".join(result.warnings).lower()


@pytest.mark.asyncio
async def test_pdf_page_limit_and_character_limit_add_safe_warnings() -> None:
    page_limited = await _extractor(NeverVisionExtractor(), pages=1).extract(
        _input(_pdf("First page has enough selectable English document text for extraction.", "Second page"))
    )
    char_limited = await _extractor(NeverVisionExtractor(), characters=50).extract(
        _input(_pdf("A" * 300))
    )

    assert "page limit" in " ".join(page_limited.warnings).lower()
    assert len(char_limited.extracted_text) == 50
    assert "character limit" in " ".join(char_limited.warnings).lower()


@pytest.mark.asyncio
@pytest.mark.parametrize("content_type", ["image/jpeg", "image/png"])
async def test_images_route_directly_to_vision_ocr(content_type: str) -> None:
    vision = FakeVisionExtractor()
    result = await _extractor(vision).extract(_input(b"image", content_type=content_type))

    assert result.extraction_method == "VisionOcr"
    assert vision.calls[0][1][0].content_type == content_type


@pytest.mark.asyncio
async def test_extraction_timeout_returns_safe_manual_review_warning() -> None:
    result = await _extractor(SlowVisionExtractor(), timeout=0.001).extract(
        _input(b"image", content_type="image/png")
    )

    assert result.readable is False
    assert result.confidence_label == "Unknown"
    assert "timed out" in " ".join(result.warnings).lower()


@pytest.mark.asyncio
async def test_vision_provider_failure_returns_safe_manual_review_fallback() -> None:
    result = await _extractor(FailedVisionExtractor()).extract(
        _input(b"image", content_type="image/png")
    )

    assert result.readable is False
    assert result.needs_vision_fallback is True
    assert "temporarily unavailable" in " ".join(result.warnings).lower()


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("language", "style", "confidence", "expected_confidence"),
    [
        ("English", "Printed", "High", "High"),
        ("English", "Handwritten", "Low", "Low"),
        ("Sinhala", "Printed", "Medium", "Medium"),
    ],
)
async def test_language_and_handwriting_confidence_is_conservative(
    language, style, confidence, expected_confidence
) -> None:
    vision = FakeVisionExtractor(
        VisionExtractionOutput(
            extracted_text="Readable document text " * 4,
            detected_language=language,
            confidence_label=confidence,
            content_style=style,
        )
    )

    result = await _extractor(vision).extract(_input(b"image", content_type="image/png"))

    assert result.confidence_label == expected_confidence


@pytest.mark.asyncio
async def test_handwritten_sinhala_is_low_confidence_and_requires_warning() -> None:
    vision = FakeVisionExtractor(
        VisionExtractionOutput(
            extracted_text="සිංහල අත් අකුරු ලේඛනය " * 4,
            detected_language="Sinhala",
            confidence_label="High",
            content_style="Handwritten",
        )
    )

    result = await _extractor(vision).extract(_input(b"image", content_type="image/png"))

    assert result.confidence_label == "Low"
    assert any("Handwritten Sinhala" in warning for warning in result.warnings)


def _fact_output(document_type="IncomeProof", **facts):
    return {
        "detectedDocumentCategory": document_type,
        "extractedFacts": {
            "applicantName": facts.get("applicant_name"),
            "incomeAmount": facts.get("income_amount"),
            "payPeriod": facts.get("pay_period"),
            "employerName": facts.get("employer_name"),
            "jobTitle": facts.get("job_title"),
            "documentDate": facts.get("document_date"),
        },
        "warnings": [],
        "confidenceLabel": "High",
    }


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("document_type", "facts", "expected"),
    [
        ("IncomeProof", {"income_amount": 5000, "pay_period": "monthly", "employer_name": "ACME"}, "income_amount"),
        ("EmploymentLetter", {"job_title": "Engineer", "employer_name": "ACME"}, "job_title"),
    ],
)
async def test_real_verifier_extracts_only_type_allowlisted_facts(document_type, facts, expected) -> None:
    provider = FactProvider(_fact_output(document_type, **facts))
    verifier = ModelSupportingDocumentVerifier(
        provider,
        _extractor(FakeVisionExtractor()),
        timeout_seconds=1,
        max_model_input_characters=200,
    )

    result = (await verifier.verify([
        _input(b"image", content_type="image/png", document_type=document_type)
    ]))[0]

    assert result.readable is True
    assert getattr(result.extracted_facts, expected) is not None
    assert "extracted_text" not in result.model_dump()
    assert "content_base64" not in result.model_dump()


@pytest.mark.asyncio
async def test_identity_provider_output_with_prohibited_identifier_fails_closed() -> None:
    unsafe = _fact_output("IdentityDocument", applicant_name="Ada")
    unsafe["extractedFacts"]["nicNumber"] = "prohibited"
    verifier = ModelSupportingDocumentVerifier(
        FactProvider(unsafe),
        _extractor(FakeVisionExtractor()),
        timeout_seconds=1,
        max_model_input_characters=200,
    )

    result = (await verifier.verify([
        _input(b"image", content_type="image/png", document_type="IdentityDocument")
    ]))[0]

    assert result.readable is False
    assert result.extracted_facts.model_dump(exclude_none=True) == {}
    assert result.requires_manual_review is True


@pytest.mark.asyncio
async def test_identifier_like_value_cannot_be_smuggled_into_allowed_name_field() -> None:
    verifier = ModelSupportingDocumentVerifier(
        FactProvider(
            _fact_output(
                "IdentityDocument",
                applicant_name="Passport number N1234567",
            )
        ),
        _extractor(FakeVisionExtractor()),
        timeout_seconds=1,
        max_model_input_characters=200,
    )

    result = (await verifier.verify([
        _input(b"image", content_type="image/png", document_type="IdentityDocument")
    ]))[0]

    assert result.extracted_facts.applicant_name is None
    assert result.requires_manual_review is True
    assert "N1234567" not in result.model_dump_json()


@pytest.mark.asyncio
async def test_category_mismatch_uses_neutral_warning_and_manual_review() -> None:
    provider = FactProvider(_fact_output("EmploymentLetter", job_title="Engineer"))
    verifier = ModelSupportingDocumentVerifier(
        provider,
        _extractor(FakeVisionExtractor()),
        timeout_seconds=1,
        max_model_input_characters=200,
    )

    result = (await verifier.verify([_input(b"image", content_type="image/png")]))[0]

    assert "Uploaded content may not match the selected document type." in result.warnings
    assert result.requires_manual_review is True


@pytest.mark.asyncio
@pytest.mark.parametrize("provider_output", [RuntimeError("rate limited"), "malformed"])
async def test_provider_failures_return_safe_unverified_result(provider_output) -> None:
    verifier = ModelSupportingDocumentVerifier(
        FactProvider(provider_output),
        _extractor(FakeVisionExtractor()),
        timeout_seconds=0.01,
        max_model_input_characters=200,
    )

    result = (await verifier.verify([_input(b"image", content_type="image/png")]))[0]

    assert result.readable is False
    assert result.requires_manual_review is True
    assert "rate limited" not in " ".join(result.warnings)


@pytest.mark.asyncio
async def test_provider_timeout_isolated_to_safe_document_warning() -> None:
    verifier = ModelSupportingDocumentVerifier(
        SlowFactProvider(_fact_output()),
        _extractor(FakeVisionExtractor()),
        timeout_seconds=0.001,
        max_model_input_characters=200,
    )

    result = (await verifier.verify([_input(b"image", content_type="image/png")]))[0]

    assert result.readable is False
    assert result.requires_manual_review is True
    assert any("Manual review" in warning for warning in result.warnings)


@pytest.mark.asyncio
async def test_model_input_character_limit_does_not_persist_full_text() -> None:
    provider = FactProvider(_fact_output(income_amount=5000, pay_period="monthly"))
    vision = FakeVisionExtractor(
        VisionExtractionOutput(
            extracted_text="X" * 500,
            detected_language="English",
            confidence_label="High",
            content_style="Printed",
        )
    )
    verifier = ModelSupportingDocumentVerifier(
        provider,
        _extractor(vision),
        timeout_seconds=1,
        max_model_input_characters=80,
    )

    result = (await verifier.verify([_input(b"image", content_type="image/png")]))[0]

    assert len(provider.inputs[0]["extractedText"]) == 80
    assert any("Model input text was truncated" in warning for warning in result.warnings)
    assert "X" * 80 not in result.model_dump_json()


@pytest.mark.asyncio
async def test_extracted_text_controls_are_sanitized_before_text_provider() -> None:
    provider = FactProvider(_fact_output(income_amount=5000, pay_period="monthly"))
    vision = FakeVisionExtractor(
        VisionExtractionOutput(
            extracted_text="Income\x00 proof for Ada Lovelace at ACME Limited, monthly 5000.",
            detected_language="English",
            confidence_label="High",
            content_style="Printed",
        )
    )
    verifier = ModelSupportingDocumentVerifier(
        provider,
        _extractor(vision),
        timeout_seconds=1,
        max_model_input_characters=200,
    )

    result = (await verifier.verify([
        _input(b"image", content_type="image/png")
    ]))[0]

    assert "\x00" not in provider.inputs[0]["extractedText"]
    assert any("control characters" in warning for warning in result.warnings)
