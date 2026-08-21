"""Real document fact verification and deterministic cross-document checks."""

from __future__ import annotations

import logging
import re
import unicodedata
from decimal import Decimal, InvalidOperation
from itertools import combinations
from typing import Protocol

from app.schemas.document_extraction import DocumentExtractionResult
from app.schemas.supporting_documents import (
    CrossDocumentConsistencyFinding,
    CrossDocumentConsistencyResult,
    SupportingDocumentExtractedFacts,
    SupportingDocumentFactAnalysis,
    SupportingDocumentInput,
    SupportingDocumentVerificationResult,
)
from app.services.document_extraction import HybridDocumentExtractor
from app.services.diagnostics import log_development_event
from app.services.model_provider import ModelProvider, request_structured_output

_CATEGORY_WARNING = "Uploaded content may not match the selected document type."
_ANALYSIS_FAILURE_WARNING = (
    "Document facts could not be verified reliably. Manual review is required."
)
_LOW_CONFIDENCE_WARNING = (
    "Low-confidence document text was not used for a hard mismatch."
)
_CONFIDENCE_ORDER = {"Unknown": 0, "Low": 1, "Medium": 2, "High": 3}
logger = logging.getLogger(__name__)


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


class ModelSupportingDocumentVerifier:
    def __init__(
        self,
        provider: ModelProvider,
        extractor: HybridDocumentExtractor,
        *,
        timeout_seconds: float,
        max_model_input_characters: int,
    ) -> None:
        self._provider = provider
        self._extractor = extractor
        self._timeout_seconds = timeout_seconds
        self._max_model_input_characters = max_model_input_characters

    async def verify(
        self, documents: list[SupportingDocumentInput]
    ) -> list[SupportingDocumentVerificationResult]:
        results: list[SupportingDocumentVerificationResult] = []
        for document in documents:
            extraction = await self._extractor.extract(document)
            results.append(await self._verify_one(document, extraction))
        return results

    async def _verify_one(
        self,
        document: SupportingDocumentInput,
        extraction: DocumentExtractionResult,
    ) -> SupportingDocumentVerificationResult:
        if not extraction.readable:
            result = _safe_unverified_result(document, extraction, extraction.warnings)
            _log_verification(document, result, fact_analysis_ran=False)
            return result

        warnings = list(extraction.warnings)
        sanitized_text, unsafe_controls_removed = _sanitize_model_text(
            extraction.extracted_text
        )
        model_text = sanitized_text[: self._max_model_input_characters]
        if unsafe_controls_removed:
            warnings.append("Unsafe control characters were removed from extracted text.")
        if len(sanitized_text) > self._max_model_input_characters:
            warnings.append(
                "Model input text was truncated at the configured character limit."
            )

        try:
            analysis = await request_structured_output(
                self._provider,
                output_schema=SupportingDocumentFactAnalysis,
                instructions=_fact_instructions(document.document_type),
                input_data={
                    "documentType": document.document_type,
                    "detectedLanguage": extraction.detected_language,
                    "contentStyle": extraction.content_style,
                    "extractedText": model_text,
                },
                timeout_seconds=self._timeout_seconds,
                invocation_name="supporting_document_fact_analysis",
            )
        except Exception:
            result = _safe_unverified_result(
                document,
                extraction,
                [*warnings, _ANALYSIS_FAILURE_WARNING],
            )
            _log_verification(document, result, fact_analysis_ran=True)
            return result

        facts, sensitive_fact_removed = _allow_list_facts(
            document.document_type, analysis.extracted_facts
        )
        confidence = _lower_confidence(
            extraction.confidence_label, analysis.confidence_label
        )
        if analysis.warnings:
            warnings.append("Some document facts could not be verified reliably.")
        if sensitive_fact_removed:
            warnings.append(
                "A non-allow-listed or identifier-like value was excluded from structured facts."
            )
        category_mismatch = (
            analysis.detected_document_category not in {document.document_type, "Unknown"}
        )
        if category_mismatch:
            warnings.append(_CATEGORY_WARNING)
        if analysis.detected_document_category == "Unknown":
            warnings.append("The document category could not be confirmed reliably.")

        uncertain_language_or_handwriting = (
            extraction.content_style in {"Handwritten", "Mixed", "Unknown"}
            or extraction.detected_language in {"Sinhala", "Mixed", "Unknown"}
        )
        requires_manual_review = (
            confidence in {"Low", "Unknown"}
            or category_mismatch
            or bool(warnings)
            or uncertain_language_or_handwriting
        )
        result = SupportingDocumentVerificationResult(
            document_id=document.document_id,
            document_type=document.document_type,
            readable=True,
            detected_document_category=analysis.detected_document_category,
            extracted_facts=facts,
            warnings=_unique(warnings),
            confidence_label=confidence,
            extraction_method=extraction.extraction_method,
            requires_manual_review=requires_manual_review,
        )
        _log_verification(document, result, fact_analysis_ran=True)
        return result


class DeterministicCrossDocumentConsistencyAnalyzer:
    def __init__(self, *, income_tolerance_percent: float = 5.0) -> None:
        self._income_tolerance = Decimal(str(income_tolerance_percent)) / Decimal("100")

    async def analyze(
        self,
        application_data: dict[str, object],
        verification: list[SupportingDocumentVerificationResult],
    ) -> CrossDocumentConsistencyResult:
        matched: list[CrossDocumentConsistencyFinding] = []
        mismatches: list[CrossDocumentConsistencyFinding] = []
        warnings: list[str] = []

        self._compare_occupation(application_data, verification, matched, mismatches, warnings)
        self._compare_income(application_data, verification, matched, mismatches, warnings)
        self._compare_names(application_data, verification, matched, mismatches, warnings)
        self._compare_employers(verification, matched, mismatches, warnings)
        self._compare_categories(verification, matched, mismatches, warnings)

        matched, mismatches = _reconcile_consistency_findings(matched, mismatches)

        findings_truncated = len(matched) > 100 or len(mismatches) > 100
        if findings_truncated:
            warnings.append(
                "Consistency findings were truncated at the configured result limit."
            )

        requires_manual_review = (
            bool(mismatches)
            or bool(warnings)
            or any(item.requires_manual_review for item in verification)
        )
        return CrossDocumentConsistencyResult(
            matched_facts=matched[:100],
            mismatches=mismatches[:100],
            warnings=_unique(warnings),
            requires_manual_review=requires_manual_review,
        )

    def _compare_occupation(self, application, verification, matched, mismatches, warnings):
        occupation = _application_value(application, "occupation")
        if not isinstance(occupation, str) or not occupation.strip():
            return
        for item in verification:
            job_title = item.extracted_facts.job_title
            if not job_title:
                continue
            if _is_low_confidence(item):
                warnings.append(_LOW_CONFIDENCE_WARNING)
                continue
            left = _normalize_words(occupation)
            right = _normalize_words(job_title)
            if left == right:
                matched.append(_finding(
                    "occupation_vs_job_title",
                    "Application occupation matches the employment-letter job title after conservative normalization.",
                ))
            elif set(left.split()) & set(right.split()):
                warnings.append(
                    "Occupation and job title differ ambiguously; manual review is required."
                )
            else:
                mismatches.append(_finding(
                    "occupation_vs_job_title",
                    "Application occupation and employment-letter job title do not match after conservative normalization.",
                ))

    def _compare_income(self, application, verification, matched, mismatches, warnings):
        monthly_income = _decimal_value(_application_value(application, "monthlyIncome"))
        if monthly_income is None:
            return
        for item in verification:
            amount = item.extracted_facts.income_amount
            if amount is None:
                continue
            normalized = _monthly_amount(amount, item.extracted_facts.pay_period)
            if normalized is None:
                warnings.append(
                    "Income pay period could not be normalized reliably; manual review is required."
                )
                continue
            if _is_low_confidence(item):
                warnings.append(_LOW_CONFIDENCE_WARNING)
                continue
            tolerance = abs(monthly_income) * self._income_tolerance
            if abs(normalized - monthly_income) <= tolerance:
                matched.append(_finding(
                    "monthly_income_vs_income_amount",
                    "Application monthly income matches normalized income-proof amount within the configured tolerance.",
                ))
            else:
                mismatches.append(_finding(
                    "monthly_income_vs_income_amount",
                    "Application monthly income and normalized income-proof amount differ beyond the configured tolerance.",
                ))

    def _compare_names(self, application, verification, matched, mismatches, warnings):
        names: list[tuple[str, str, str]] = []
        application_name = next(
            (_application_value(application, key) for key in ("applicantName", "fullName", "name")
             if isinstance(_application_value(application, key), str)),
            None,
        )
        if isinstance(application_name, str) and application_name.strip():
            names.append(("application", application_name, "High"))
        names.extend(
            (item.document_type, item.extracted_facts.applicant_name, item.confidence_label)
            for item in verification
            if item.extracted_facts.applicant_name
        )
        for left, right in combinations(names, 2):
            if _different_scripts(left[1], right[1]):
                warnings.append(
                    "Sinhala and English applicant names were not transliterated for hard matching; manual review is required."
                )
            elif "Low" in {left[2], right[2]} or "Unknown" in {left[2], right[2]}:
                warnings.append(_LOW_CONFIDENCE_WARNING)
            else:
                left_name = _normalize_name(left[1])
                right_name = _normalize_name(right[1])
                if left_name and left_name == right_name:
                    matched.append(_finding(
                        "applicant_name_consistency",
                        "Applicant names match after conservative normalization.",
                    ))
                else:
                    mismatches.append(_finding(
                        "applicant_name_consistency",
                        "Applicant names do not match after conservative normalization.",
                    ))

    def _compare_employers(self, verification, matched, mismatches, warnings):
        income_items = [
            item for item in verification
            if item.document_type == "IncomeProof" and item.extracted_facts.employer_name
        ]
        employment_items = [
            item for item in verification
            if item.document_type == "EmploymentLetter" and item.extracted_facts.employer_name
        ]
        for left in income_items:
            for right in employment_items:
                if _is_low_confidence(left) or _is_low_confidence(right):
                    warnings.append(_LOW_CONFIDENCE_WARNING)
                elif _normalize_name(left.extracted_facts.employer_name or "") == _normalize_name(
                    right.extracted_facts.employer_name or ""
                ):
                    matched.append(_finding(
                        "employer_name_consistency",
                        "Employer names match after conservative normalization.",
                    ))
                else:
                    mismatches.append(_finding(
                        "employer_name_consistency",
                        "Employer names do not match after conservative normalization.",
                    ))

    def _compare_categories(self, verification, matched, mismatches, warnings):
        for item in verification:
            category = item.detected_document_category
            if category == item.document_type:
                matched.append(_finding(
                    "document_category_vs_uploaded_type",
                    "Detected document category matches the selected document type.",
                ))
            elif category == "Unknown" or _is_low_confidence(item):
                warnings.append(
                    "The selected document type could not be confirmed reliably; manual review is required."
                )
            else:
                mismatches.append(_finding(
                    "document_category_vs_uploaded_type",
                    _CATEGORY_WARNING,
                ))


def _fact_instructions(document_type: str) -> str:
    allowed = {
        "IncomeProof": "applicantName, incomeAmount, payPeriod, employerName, documentDate",
        "EmploymentLetter": "applicantName, jobTitle, employerName, documentDate",
        "IdentityDocument": "applicantName only when reliably readable",
    }[document_type]
    return (
        f"Analyze supplied OCR text as selected type {document_type}. Extract only: {allowed}. "
        "Classify the plausible document category. Never extract identifiers, date of birth, "
        "gender, religion, ethnicity, disability, facial/health/political/sexual-orientation "
        "data, or parent details. Return incomeAmount as a number without a currency symbol "
        "or thousands separators. Return documentDate as YYYY-MM-DD, including when the "
        "source uses a written month name. Do not translate or transliterate names. Never guess low-"
        "confidence text. Use Unknown/Low and a warning when uncertain. Do not infer fraud, "
        "tenant risk, approval, rejection, or hidden reasoning."
    )


def _allow_list_facts(document_type: str, facts: SupportingDocumentExtractedFacts):
    safe_values = {
        "applicant_name": _safe_text_fact(facts.applicant_name),
        "pay_period": _safe_text_fact(facts.pay_period),
        "employer_name": _safe_text_fact(facts.employer_name),
        "job_title": _safe_text_fact(facts.job_title),
    }
    sensitive_fact_removed = any(
        original is not None and safe_values[name] is None
        for name, original in (
            ("applicant_name", facts.applicant_name),
            ("pay_period", facts.pay_period),
            ("employer_name", facts.employer_name),
            ("job_title", facts.job_title),
        )
    )
    common = {"applicant_name": safe_values["applicant_name"]}
    if document_type == "IncomeProof":
        return SupportingDocumentExtractedFacts(
            **common,
            income_amount=facts.income_amount,
            pay_period=safe_values["pay_period"],
            employer_name=safe_values["employer_name"],
            document_date=facts.document_date,
        ), sensitive_fact_removed
    if document_type == "EmploymentLetter":
        return SupportingDocumentExtractedFacts(
            **common,
            job_title=safe_values["job_title"],
            employer_name=safe_values["employer_name"],
            document_date=facts.document_date,
        ), sensitive_fact_removed
    return SupportingDocumentExtractedFacts(**common), sensitive_fact_removed


def _safe_text_fact(value: str | None) -> str | None:
    if value is None:
        return None
    normalized = re.sub(r"[^a-z0-9]", "", value.casefold())
    prohibited_markers = (
        "nicnumber",
        "passportnumber",
        "birthcertificatenumber",
        "dateofbirth",
        "gender",
        "religion",
        "ethnicity",
        "disability",
        "parentdetails",
    )
    if any(marker in normalized for marker in prohibited_markers):
        return None
    if re.search(r"\d{5,}", value):
        return None
    return value


def _sanitize_model_text(value: str) -> tuple[str, bool]:
    """Remove invisible controls while preserving readable Unicode and line layout."""
    normalized_lines = value.replace("\r\n", "\n").replace("\r", "\n")
    sanitized = "".join(
        character
        for character in normalized_lines
        if character in {"\n", "\t"}
        or not unicodedata.category(character).startswith("C")
    )
    return sanitized.strip(), sanitized != normalized_lines


def _safe_unverified_result(document, extraction, warnings):
    return SupportingDocumentVerificationResult(
        document_id=document.document_id,
        document_type=document.document_type,
        readable=False,
        detected_document_category="Unknown",
        warnings=_unique(list(warnings)),
        confidence_label="Unknown",
        extraction_method=extraction.extraction_method,
        requires_manual_review=True,
    )


def _log_verification(document, result, *, fact_analysis_ran: bool) -> None:
    facts = result.extracted_facts
    populated_fields = [
        field_name
        for field_name, value in (
            ("applicantName", facts.applicant_name),
            ("incomeAmount", facts.income_amount),
            ("payPeriod", facts.pay_period),
            ("employerName", facts.employer_name),
            ("jobTitle", facts.job_title),
            ("documentDate", facts.document_date),
        )
        if value is not None
    ]
    log_development_event(
        logger,
        "supporting_document_verification_completed",
        document_type=document.document_type,
        content_type=document.content_type,
        extraction_method=result.extraction_method,
        readable=result.readable,
        confidence=result.confidence_label,
        fact_analysis_ran=fact_analysis_ran,
        detected_category=result.detected_document_category,
        populated_allowed_fields=",".join(populated_fields) or "none",
    )


def _lower_confidence(left: str, right: str) -> str:
    return min((left, right), key=_CONFIDENCE_ORDER.__getitem__)


def _is_low_confidence(item: SupportingDocumentVerificationResult) -> bool:
    return item.confidence_label in {"Low", "Unknown"}


def _application_value(data: dict[str, object], requested: str):
    normalized = re.sub(r"[^a-z0-9]", "", requested.casefold())
    for key, value in data.items():
        if re.sub(r"[^a-z0-9]", "", str(key).casefold()) == normalized:
            return value
    return None


def _normalize_words(value: str) -> str:
    return " ".join(value.casefold().split())


def _normalize_name(value: str) -> str:
    normalized = unicodedata.normalize("NFKC", value).casefold()
    parts = "".join(
        character if character.isalnum() else " " for character in normalized
    ).split()
    if parts and parts[0] in {"mr", "mrs", "ms", "miss", "dr"}:
        parts = parts[1:]
    return " ".join(parts)


def _different_scripts(left: str, right: str) -> bool:
    left_sinhala = any("\u0d80" <= character <= "\u0dff" for character in left)
    right_sinhala = any("\u0d80" <= character <= "\u0dff" for character in right)
    left_latin = any(character.isascii() and character.isalpha() for character in left)
    right_latin = any(character.isascii() and character.isalpha() for character in right)
    return (left_sinhala and right_latin) or (right_sinhala and left_latin)


def _decimal_value(value: object) -> Decimal | None:
    try:
        return Decimal(str(value))
    except (InvalidOperation, TypeError, ValueError):
        return None


def _monthly_amount(amount: Decimal, pay_period: str | None) -> Decimal | None:
    if not pay_period:
        return None
    period = _normalize_words(pay_period)
    if period in {"monthly", "month", "per month", "pcm"}:
        return amount
    if re.fullmatch(
        r"(?:january|february|march|april|may|june|july|august|september|"
        r"october|november|december)\s+\d{4}",
        period,
    ):
        # A named calendar-month pay period represents one monthly payment.
        return amount
    if period in {"annual", "annually", "yearly", "per year", "pa"}:
        return amount / Decimal("12")
    if period in {"weekly", "week", "per week"}:
        return amount * Decimal("52") / Decimal("12")
    if period in {"biweekly", "bi-weekly", "fortnightly", "per fortnight"}:
        return amount * Decimal("26") / Decimal("12")
    return None


def _finding(comparison: str, message: str) -> CrossDocumentConsistencyFinding:
    return CrossDocumentConsistencyFinding(comparison=comparison, message=message)


def _reconcile_consistency_findings(
    matched: list[CrossDocumentConsistencyFinding],
    mismatches: list[CrossDocumentConsistencyFinding],
) -> tuple[list[CrossDocumentConsistencyFinding], list[CrossDocumentConsistencyFinding]]:
    """Return one conservative outcome per consistency check."""
    mismatch_by_check = {
        finding.comparison: finding
        for finding in mismatches
    }
    matched_by_check = {
        finding.comparison: finding
        for finding in matched
        if finding.comparison not in mismatch_by_check
    }
    return list(matched_by_check.values()), list(mismatch_by_check.values())


def _unique(values: list[str]) -> list[str]:
    return list(dict.fromkeys(value.strip()[:1000] for value in values if value.strip()))[:100]
