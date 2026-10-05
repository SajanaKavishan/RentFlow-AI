from __future__ import annotations

import asyncio
import logging
from types import SimpleNamespace
from typing import Any

import httpx
import pytest
from groq import BadRequestError, RateLimitError

from app.config import Settings
from app.schemas.analysis import (
    ApplicationDataAnalysis,
    ConsistencyAnalysis,
    DocumentAnalysis,
    FinalAgentSummary,
    FinalAgentSummaryDraft,
)
from app.schemas.document_extraction import VisionExtractionOutput
from app.schemas.plan import Plan
from app.services.exceptions import (
    ModelInvocationError,
    ModelOutputValidationError,
    ModelTimeoutError,
    VisionCapabilityUnavailableError,
)
from app.services.groq_provider import (
    GroqModelProvider,
    _groq_strict_schema,
    _model_invocation_error,
)
from app.services.model_provider import (
    ModelMedia,
    build_model_provider,
    build_vision_model_provider,
    request_structured_media_output,
    request_structured_output,
)


class FakeGroqCompletions:
    def __init__(self, response: Any = None, error: Exception | None = None) -> None:
        self.response = response
        self.error = error
        self.calls: list[dict[str, Any]] = []

    async def create(self, **kwargs: Any) -> Any:
        self.calls.append(kwargs)
        if self.error:
            raise self.error
        return self.response


def fake_client(completions: Any) -> SimpleNamespace:
    return SimpleNamespace(chat=SimpleNamespace(completions=completions))


def completion_response(content: str | None) -> SimpleNamespace:
    message = SimpleNamespace(content=content, refusal=None)
    return SimpleNamespace(choices=[SimpleNamespace(message=message)])


def groq_settings() -> Settings:
    return Settings(
        ai_provider="groq",
        ai_model="openai/gpt-oss-20b",
        ai_api_key=None,
        ai_timeout_seconds=1,
        agent_version="test",
        groq_api_key="test-groq-key-not-a-real-secret",
    )


def _walk_objects(value: Any):
    if isinstance(value, dict):
        if value.get("type") == "object":
            yield value
        for nested in value.values():
            yield from _walk_objects(nested)
    elif isinstance(value, list):
        for nested in value:
            yield from _walk_objects(nested)


def _schema_keys(value: Any) -> set[str]:
    if isinstance(value, dict):
        return set(value).union(*(_schema_keys(item) for item in value.values()))
    if isinstance(value, list):
        return set().union(*(_schema_keys(item) for item in value))
    return set()


@pytest.mark.parametrize(
    ("message", "model", "response_format_type", "expected"),
    [
        (
            "Invalid JSON schema constraint",
            "openai/gpt-oss-20b",
            "json_schema",
            "provider_json_schema_incompatibility",
        ),
        (
            "Request exceeds the context token limit",
            "openai/gpt-oss-20b",
            "json_schema",
            "provider_request_size_or_context",
        ),
        (
            "response_format is unsupported",
            "unsupported-model",
            "json_schema",
            "provider_response_format_unsupported",
        ),
        (
            "Bad request",
            "openai/gpt-oss-20b",
            "json_schema",
            "provider_request_malformed",
        ),
    ],
)
def test_groq_400_diagnostic_categories(
    message: str,
    model: str,
    response_format_type: str,
    expected: str,
) -> None:
    class SyntheticBadRequest(Exception):
        status_code = 400

    error = _model_invocation_error(
        SyntheticBadRequest(message),
        model=model,
        response_format_type=response_format_type,
        request_characters=100,
    )

    assert error.diagnostic_category == expected


def test_groq_provider_configuration_uses_dedicated_key(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path,
) -> None:
    monkeypatch.setenv("AI_PROVIDER", "groq")
    monkeypatch.setenv("AI_MODEL", "openai/gpt-oss-20b")
    monkeypatch.setenv("GROQ_API_KEY", "groq-only-key")
    monkeypatch.delenv("AI_API_KEY", raising=False)
    isolated_env_file = tmp_path / ".env"
    isolated_env_file.write_text("", encoding="utf-8")

    settings = Settings.from_environment(isolated_env_file)
    provider = build_model_provider(settings)

    assert settings.provider_is_configured is True
    assert settings.ai_api_key is None
    assert isinstance(provider, GroqModelProvider)
    assert provider.model_name == "openai/gpt-oss-20b"


def test_provider_factory_keeps_gemini_and_groq_selectable() -> None:
    groq_provider = build_model_provider(groq_settings())
    gemini_provider = build_model_provider(
        Settings(
            ai_provider="gemini",
            ai_model="gemini-2.5-flash",
            ai_api_key="gemini-key",
            ai_timeout_seconds=1,
            agent_version="test",
        )
    )

    assert isinstance(groq_provider, GroqModelProvider)
    assert type(gemini_provider).__name__ == "GeminiModelProvider"


def test_dedicated_groq_vision_provider_can_use_separate_model_and_key() -> None:
    settings = groq_settings()
    settings = Settings(
        ai_provider=settings.ai_provider,
        ai_model=settings.ai_model,
        ai_api_key=settings.ai_api_key,
        ai_timeout_seconds=settings.ai_timeout_seconds,
        agent_version=settings.agent_version,
        groq_api_key=settings.groq_api_key,
        vision_provider="groq",
        vision_model="qwen/qwen3.6-27b",
        vision_api_key="dedicated-vision-key",
    )
    primary = build_model_provider(settings)

    vision = build_vision_model_provider(settings, primary)

    assert isinstance(vision, GroqModelProvider)
    assert vision.model_name == "qwen/qwen3.6-27b"


def test_text_only_groq_primary_is_not_reused_as_vision_provider() -> None:
    primary = build_model_provider(groq_settings())

    vision = build_vision_model_provider(groq_settings(), primary)

    assert primary.capabilities.text_structured_reasoning is True
    assert primary.capabilities.vision_document_images is False
    assert vision.capabilities.vision_document_images is False


@pytest.mark.parametrize(
    "output_schema",
    [Plan, ApplicationDataAnalysis, DocumentAnalysis, ConsistencyAnalysis, FinalAgentSummary],
)
def test_all_output_schemas_are_transformed_for_groq_strict_mode(output_schema) -> None:
    schema = _groq_strict_schema(output_schema)

    objects = list(_walk_objects(schema))
    assert objects
    for object_schema in objects:
        assert object_schema["additionalProperties"] is False
        assert object_schema["required"] == list(object_schema.get("properties", {}))
    assert {
        "default",
        "maxItems",
        "maxLength",
        "minItems",
        "minLength",
        "pattern",
        "title",
    }.isdisjoint(_schema_keys(schema))

    # Provider normalization must not weaken authoritative local schemas.
    assert "additionalProperties" in _schema_keys(output_schema.model_json_schema())


@pytest.mark.asyncio
async def test_groq_structured_success_uses_strict_json_schema() -> None:
    completions = FakeGroqCompletions(
        response=completion_response(
            '{"steps":["analyze_application_data","analyze_document_metadata",'
            '"verify_supporting_documents","analyze_cross_document_consistency",'
            '"analyze_consistency","summarize_findings"]}'
        )
    )
    provider = GroqModelProvider(
        api_key="fake-key",
        model="openai/gpt-oss-20b",
        client=fake_client(completions),
    )

    result = await request_structured_output(
        provider,
        output_schema=Plan,
        instructions="Use the fixed plan and do not expose hidden reasoning.",
        input_data={"objective": "test"},
        timeout_seconds=1,
        invocation_name="planner",
    )

    assert isinstance(result, Plan)
    call = completions.calls[0]
    assert call["model"] == "openai/gpt-oss-20b"
    assert call["response_format"]["type"] == "json_schema"
    assert call["response_format"]["json_schema"]["strict"] is True
    assert call["response_format"]["json_schema"]["schema"] == _groq_strict_schema(Plan)
    assert call["temperature"] == 0
    assert "properties" not in call["messages"][0]["content"]
    assert "properties" not in call["messages"][1]["content"]


@pytest.mark.asyncio
async def test_groq_malformed_response_is_rejected_locally() -> None:
    provider = GroqModelProvider(
        api_key="fake-key",
        model="openai/gpt-oss-20b",
        client=fake_client(FakeGroqCompletions(response=completion_response("not-json"))),
    )

    with pytest.raises(ModelOutputValidationError):
        await request_structured_output(
            provider,
            output_schema=Plan,
            instructions="Use the fixed plan.",
            input_data={},
            timeout_seconds=1,
            invocation_name="planner",
        )


@pytest.mark.asyncio
async def test_gpt_oss_20b_never_sends_image_content() -> None:
    completions = FakeGroqCompletions(response=completion_response("{}"))
    provider = GroqModelProvider(
        api_key="fake-key",
        model="openai/gpt-oss-20b",
        client=fake_client(completions),
    )

    with pytest.raises(VisionCapabilityUnavailableError):
        await request_structured_media_output(
            provider,
            output_schema=VisionExtractionOutput,
            instructions="Perform conservative OCR.",
            input_data={"documentId": "document-1"},
            media=[ModelMedia(content_type="image/jpeg", content=b"image-bytes")],
            timeout_seconds=1,
            invocation_name="document_vision_ocr",
        )

    assert completions.calls == []


@pytest.mark.asyncio
async def test_groq_final_summary_draft_uses_compatible_text_schema() -> None:
    completions = FakeGroqCompletions(
        response=completion_response(
            '{"recommendation":"Manual review required","summary":"Review required.",'
            '"keyFindings":[],"warnings":[],"requiresHumanApproval":true}'
        )
    )
    provider = GroqModelProvider(
        api_key="fake-key",
        model="openai/gpt-oss-20b",
        client=fake_client(completions),
    )

    result = await request_structured_output(
        provider,
        output_schema=FinalAgentSummaryDraft,
        instructions="Create a concise manual-review summary.",
        input_data={"deterministicFindings": []},
        timeout_seconds=1,
        invocation_name="final_summary",
    )

    assert result.requires_human_approval is True
    schema = completions.calls[0]["response_format"]["json_schema"]["schema"]
    assert "pattern" not in _schema_keys(schema)
    assert "SupportingDocumentExtractedFacts" not in schema.get("$defs", {})


@pytest.mark.asyncio
async def test_groq_400_diagnostics_classify_schema_without_logging_request_data(
    caplog: pytest.LogCaptureFixture,
) -> None:
    request = httpx.Request("POST", "https://api.groq.com/openai/v1/chat/completions")
    response = httpx.Response(400, request=request)
    provider_error = BadRequestError(
        "Invalid JSON schema in response_format",
        response=response,
        body={"error": {"message": "Invalid JSON schema in response_format"}},
    )
    provider = GroqModelProvider(
        api_key="fake-key",
        model="openai/gpt-oss-20b",
        client=fake_client(FakeGroqCompletions(error=provider_error)),
    )

    with caplog.at_level(logging.DEBUG, logger="app.services.model_provider"):
        with pytest.raises(ModelInvocationError):
            await request_structured_output(
                provider,
                output_schema=Plan,
                instructions="Use the fixed plan.",
                input_data={"private": "must-not-appear"},
                timeout_seconds=1,
                invocation_name="planner",
            )

    assert "category=provider_json_schema_incompatibility" in caplog.text
    assert "must-not-appear" not in caplog.text


@pytest.mark.asyncio
async def test_groq_rate_limit_error_is_sanitized(
    caplog: pytest.LogCaptureFixture,
) -> None:
    request = httpx.Request("POST", "https://api.groq.com/openai/v1/chat/completions")
    response = httpx.Response(429, request=request)
    provider_error = RateLimitError(
        "rate limited api_key=secret-groq-key Authorization:Bearer secret-header",
        response=response,
        body={"error": {"message": "rate limited"}},
    )
    provider = GroqModelProvider(
        api_key="fake-key",
        model="openai/gpt-oss-20b",
        client=fake_client(FakeGroqCompletions(error=provider_error)),
    )

    with caplog.at_level(logging.DEBUG, logger="app.services.model_provider"):
        with pytest.raises(ModelInvocationError) as captured:
            await request_structured_output(
                provider,
                output_schema=Plan,
                instructions="Use the fixed plan.",
                input_data={},
                timeout_seconds=1,
                invocation_name="planner",
            )

    assert "secret-groq-key" not in str(captured.value)
    assert "secret-groq-key" not in caplog.text
    assert "secret-header" not in caplog.text
    assert "exception_type=groq.RateLimitError" in caplog.text
    assert "category=provider_http_failure" in caplog.text
    assert "status=429" in caplog.text
    assert "model=openai/gpt-oss-20b" in caplog.text


@pytest.mark.asyncio
async def test_groq_timeout_is_sanitized() -> None:
    class SlowCompletions:
        cancelled = False

        async def create(self, **kwargs: Any) -> None:
            del kwargs
            try:
                await asyncio.sleep(0.1)
            except asyncio.CancelledError:
                self.cancelled = True
                raise

    completions = SlowCompletions()
    provider = GroqModelProvider(
        api_key="fake-key",
        model="openai/gpt-oss-20b",
        client=fake_client(completions),
    )

    with pytest.raises(ModelTimeoutError):
        await request_structured_output(
            provider,
            output_schema=Plan,
            instructions="Use the fixed plan.",
            input_data={},
            timeout_seconds=0.001,
            invocation_name="planner",
        )

    assert completions.cancelled is True


@pytest.mark.asyncio
async def test_groq_vision_uses_provider_neutral_in_memory_image_media() -> None:
    completions = FakeGroqCompletions(
        response=completion_response(
            '{"extractedText":"Readable printed document text for analysis",'
            '"detectedLanguage":"English","confidenceLabel":"High",'
            '"contentStyle":"Printed","warnings":[]}'
        )
    )
    provider = GroqModelProvider(
        api_key="fake-key", model="qwen/qwen3.6-27b", client=fake_client(completions)
    )

    result = await request_structured_media_output(
        provider,
        output_schema=VisionExtractionOutput,
        instructions="Perform conservative OCR.",
        input_data={"documentId": "document-1"},
        media=[ModelMedia(content_type="image/png", content=b"image-bytes")],
        timeout_seconds=1,
        invocation_name="document_vision_ocr",
    )

    assert result.detected_language == "English"
    content = completions.calls[0]["messages"][1]["content"]
    assert content[1]["type"] == "image_url"
    assert content[1]["image_url"]["url"].startswith("data:image/png;base64,")
    assert completions.calls[0]["response_format"] == {"type": "json_object"}


def test_maintenance_nullable_enums_use_groq_union_types_without_relaxing_local_contract():
    from app.schemas.maintenance import MaintenanceIssueAssessment, MaintenanceCoordinationSummary
    from pydantic import ValidationError
    issue = _groq_strict_schema(MaintenanceIssueAssessment)["properties"]["suggestedCategory"]
    assert issue["type"] == ["string", "null"]
    assert "anyOf" not in issue and "$ref" not in issue
    assert "Plumbing" in issue["enum"] and None in issue["enum"]
    final = _groq_strict_schema(MaintenanceCoordinationSummary)["properties"]
    assert final["nextAction"]["type"] == ["string", "null"]
    assert None in final["nextAction"]["enum"]
    assert final["requiresHumanReview"]["const"] is True
    with pytest.raises(ValidationError):
        MaintenanceIssueAssessment.model_validate({"suggestedCategory": "Electrician",
            "categoryConfidence": "High", "findings": [], "explanation": "Not a canonical category."})
