"""Internal-only document extraction contracts; extracted text is never persisted."""

from __future__ import annotations

from pydantic import Field

from app.schemas.common import StrictModel
from app.schemas.supporting_documents import (
    ConfidenceLabel,
    ContentStyle,
    DetectedLanguage,
    ExtractionMethod,
)


class DocumentExtractionResult(StrictModel):
    document_id: str = Field(alias="documentId")
    readable: bool
    extracted_text: str = Field(alias="extractedText")
    extraction_method: ExtractionMethod = Field(alias="extractionMethod")
    detected_language: DetectedLanguage = Field(alias="detectedLanguage")
    confidence_label: ConfidenceLabel = Field(alias="confidenceLabel")
    content_style: ContentStyle = Field(alias="contentStyle")
    needs_vision_fallback: bool = Field(alias="needsVisionFallback")
    warnings: list[str] = Field(default_factory=list, max_length=20)


class VisionExtractionOutput(StrictModel):
    extracted_text: str = Field(default="", max_length=200_000, alias="extractedText")
    detected_language: DetectedLanguage = Field(alias="detectedLanguage")
    confidence_label: ConfidenceLabel = Field(alias="confidenceLabel")
    content_style: ContentStyle = Field(alias="contentStyle")
    warnings: list[str] = Field(default_factory=list, max_length=20)
