from __future__ import annotations

import asyncio
import logging
from types import SimpleNamespace
from typing import Any

import httpx
import pytest
from groq import RateLimitError

from app.config import Settings
from app.schemas.analysis import (
    ApplicationDataAnalysis,
    ConsistencyAnalysis,
    DocumentAnalysis,
    FinalAgentSummary,
)
from app.schemas.plan import Plan
from app.services.exceptions import (
    ModelInvocationError,
    ModelOutputValidationError,
    ModelTimeoutError,
)
from app.services.groq_provider import GroqModelProvider, _groq_strict_schema
from app.services.model_provider import build_model_provider, request_structured_output


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
