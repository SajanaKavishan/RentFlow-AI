"""Phase A deterministic fakes for future OCR/multimodal document agents."""

from __future__ import annotations

from typing import Protocol

from app.schemas.supporting_documents import (
    CrossDocumentConsistencyResult,
    SupportingDocumentInput,
    SupportingDocumentVerificationResult,
)


class SupportingDocumentVerifier(Protocol):
    async def verify(
        self, documents: list[SupportingDocumentInput]
    ) -> list[SupportingDocumentVerificationResult]: ...


class CrossDocumentConsistencyAnalyzer(Protocol):
    async def analyze(
        self,
        application_data: dict[str, object],
        verification: list[SupportingDocumentVerificationResult],
    ) -> CrossDocumentConsistencyResult: ...


class PhaseAFakeSupportingDocumentVerifier:
    async def verify(
        self, documents: list[SupportingDocumentInput]
    ) -> list[SupportingDocumentVerificationResult]:
        return [
            SupportingDocumentVerificationResult(
                document_id=document.document_id,
                document_type=document.document_type,
                readable=False,
                detected_document_category="NotAssessed",
                warnings=["Document extraction is deferred to Phase B."],
                confidence_label="NotAssessed",
            )
            for document in documents
        ]


class PhaseAFakeCrossDocumentConsistencyAnalyzer:
    async def analyze(
        self,
        application_data: dict[str, object],
        verification: list[SupportingDocumentVerificationResult],
    ) -> CrossDocumentConsistencyResult:
        del application_data
        warnings = (
            ["Cross-document fact comparison is deferred to Phase B."]
            if verification
            else []
        )
        return CrossDocumentConsistencyResult(
            warnings=warnings,
            requires_manual_review=bool(verification),
        )
