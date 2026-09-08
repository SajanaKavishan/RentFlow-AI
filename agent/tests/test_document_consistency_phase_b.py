from __future__ import annotations

from decimal import Decimal

import pytest

from app.schemas.supporting_documents import (
    SupportingDocumentExtractedFacts,
    SupportingDocumentVerificationResult,
)
from app.services.supporting_document_verification import (
    DeterministicCrossDocumentConsistencyAnalyzer,
)


def _result(
    document_type: str,
    *,
    confidence="High",
    category=None,
    **facts,
):
    return SupportingDocumentVerificationResult(
        document_id=f"{document_type}-{len(facts)}",
        document_type=document_type,
        readable=True,
        detected_document_category=category or document_type,
        extracted_facts=SupportingDocumentExtractedFacts(**facts),
        warnings=[],
        confidence_label=confidence,
        extraction_method="PdfText",
        requires_manual_review=confidence in {"Low", "Unknown"},
    )


def _comparisons(findings):
    return [finding.comparison for finding in findings]


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("occupation", "job_title", "expected_collection"),
    [
        ("  Software   Engineer ", "software engineer", "matched_facts"),
        ("Accountant", "Civil Engineer", "mismatches"),
    ],
)
async def test_occupation_conservative_match_and_mismatch(
    occupation, job_title, expected_collection
) -> None:
    result = await DeterministicCrossDocumentConsistencyAnalyzer().analyze(
        {"occupation": occupation},
        [_result("EmploymentLetter", job_title=job_title)],
    )

    assert "occupation_vs_job_title" in _comparisons(getattr(result, expected_collection))


@pytest.mark.asyncio
async def test_low_confidence_occupation_never_creates_hard_mismatch() -> None:
    result = await DeterministicCrossDocumentConsistencyAnalyzer().analyze(
        {"occupation": "Accountant"},
        [_result("EmploymentLetter", confidence="Low", job_title="Engineer")],
    )

    assert "occupation_vs_job_title" not in _comparisons(result.mismatches)
    assert any("Low-confidence" in warning for warning in result.warnings)


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("income", "proof", "tolerance", "expected_collection"),
    [
        (5000, Decimal("5000"), 5, "matched_facts"),
        (5000, Decimal("6000"), 5, "mismatches"),
        (5000, Decimal("5400"), 10, "matched_facts"),
    ],
)
async def test_income_normalization_match_mismatch_and_configurable_tolerance(
    income, proof, tolerance, expected_collection
) -> None:
    result = await DeterministicCrossDocumentConsistencyAnalyzer(
        income_tolerance_percent=tolerance
    ).analyze(
        {"monthlyIncome": income},
        [_result("IncomeProof", income_amount=proof, pay_period="monthly")],
    )

    assert "monthly_income_vs_income_amount" in _comparisons(
        getattr(result, expected_collection)
    )


@pytest.mark.asyncio
async def test_annual_income_is_normalized_to_monthly() -> None:
    result = await DeterministicCrossDocumentConsistencyAnalyzer().analyze(
        {"monthlyIncome": 5000},
        [_result("IncomeProof", income_amount=Decimal("60000"), pay_period="annual")],
    )

    assert "monthly_income_vs_income_amount" in _comparisons(result.matched_facts)


@pytest.mark.asyncio
async def test_named_calendar_month_pay_period_is_treated_as_monthly() -> None:
    result = await DeterministicCrossDocumentConsistencyAnalyzer().analyze(
        {"monthlyIncome": 185000},
        [
            _result(
                "IncomeProof",
                income_amount=Decimal("185000"),
                pay_period="July 2026",
            )
        ],
    )

    assert "monthly_income_vs_income_amount" in _comparisons(result.matched_facts)
    assert not any("pay period" in warning.lower() for warning in result.warnings)


@pytest.mark.asyncio
async def test_applicant_name_accepts_case_whitespace_and_punctuation() -> None:
    result = await DeterministicCrossDocumentConsistencyAnalyzer().analyze(
        {"applicantName": "Ada  M. Lovelace"},
        [_result("IdentityDocument", applicant_name="ada m lovelace")],
    )

    assert "applicant_name_consistency" in _comparisons(result.matched_facts)


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "document_name",
    ["Mr. Sajana Kavishan", "Mr Sajana Kavishan"],
)
async def test_applicant_name_ignores_allowlisted_leading_honorific(
    document_name: str,
) -> None:
    result = await DeterministicCrossDocumentConsistencyAnalyzer().analyze(
        {"applicantName": "Sajana Kavishan"},
        [_result("IncomeProof", applicant_name=document_name)],
    )

    assert "applicant_name_consistency" in _comparisons(result.matched_facts)
    assert "applicant_name_consistency" not in _comparisons(result.mismatches)


@pytest.mark.asyncio
async def test_applicant_name_honorific_normalization_handles_case_and_spacing() -> None:
    result = await DeterministicCrossDocumentConsistencyAnalyzer().analyze(
        {"applicantName": "  SAJANA   KAVISHAN  "},
        [_result("EmploymentLetter", applicant_name="mR.  Sajana Kavishan")],
    )

    assert "applicant_name_consistency" in _comparisons(result.matched_facts)
    assert "applicant_name_consistency" not in _comparisons(result.mismatches)


@pytest.mark.asyncio
async def test_genuinely_different_high_confidence_names_are_a_mismatch() -> None:
    result = await DeterministicCrossDocumentConsistencyAnalyzer().analyze(
        {"applicantName": "Sajana Kavishan"},
        [_result("IdentityDocument", applicant_name="Nimal Perera")],
    )

    assert "applicant_name_consistency" in _comparisons(result.mismatches)
    assert "applicant_name_consistency" not in _comparisons(result.matched_facts)


@pytest.mark.asyncio
async def test_arbitrary_leading_name_word_is_not_removed() -> None:
    result = await DeterministicCrossDocumentConsistencyAnalyzer().analyze(
        {"applicantName": "Sajana Kavishan"},
        [_result("IdentityDocument", applicant_name="Professor Sajana Kavishan")],
    )

    assert "applicant_name_consistency" in _comparisons(result.mismatches)


@pytest.mark.asyncio
async def test_consistency_check_cannot_be_both_matched_and_mismatched() -> None:
    result = await DeterministicCrossDocumentConsistencyAnalyzer().analyze(
        {"applicantName": "Sajana Kavishan"},
        [
            _result("IncomeProof", applicant_name="Mr. Sajana Kavishan"),
            _result("EmploymentLetter", applicant_name="Nimal Perera"),
        ],
    )

    assert "applicant_name_consistency" in _comparisons(result.mismatches)
    assert "applicant_name_consistency" not in _comparisons(result.matched_facts)
    assert _comparisons(result.mismatches).count("applicant_name_consistency") == 1


@pytest.mark.asyncio
async def test_employer_names_compare_across_income_and_employment_documents() -> None:
    result = await DeterministicCrossDocumentConsistencyAnalyzer().analyze(
        {},
        [
            _result("IncomeProof", employer_name="ACME (Pvt) Ltd"),
            _result("EmploymentLetter", employer_name="acme pvt ltd"),
        ],
    )

    assert "employer_name_consistency" in _comparisons(result.matched_facts)


@pytest.mark.asyncio
async def test_sinhala_english_name_difference_is_uncertain_not_mismatch() -> None:
    result = await DeterministicCrossDocumentConsistencyAnalyzer().analyze(
        {"applicantName": "Nimal Perera"},
        [_result("IdentityDocument", applicant_name="නිමල් පෙරේරා")],
    )

    assert "applicant_name_consistency" not in _comparisons(result.mismatches)
    assert any("not transliterated" in warning for warning in result.warnings)
    assert result.requires_manual_review is True


@pytest.mark.asyncio
async def test_category_mismatch_is_neutral_and_requires_manual_review() -> None:
    result = await DeterministicCrossDocumentConsistencyAnalyzer().analyze(
        {},
        [_result("IncomeProof", category="EmploymentLetter")],
    )

    assert "document_category_vs_uploaded_type" in _comparisons(result.mismatches)
    assert result.requires_manual_review is True
    serialized = result.model_dump_json()
    assert "risk_score" not in serialized
    assert "fraud_score" not in serialized
