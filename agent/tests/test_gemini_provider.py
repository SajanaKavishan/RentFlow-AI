from __future__ import annotations

import asyncio
import logging
from types import SimpleNamespace
from typing import Any

import pytest
from google.genai import errors
from pydantic import ValidationError

from app.agents.nodes import create_nodes
from app.config import Settings
from app.schemas.analysis import ApplicationDataAnalysis
from app.schemas.plan import Plan
from app.services.exceptions import (
    ModelInvocationError,
    ModelOutputValidationError,
    ModelTimeoutError,
    UnsupportedProviderError,
)
from app.services.diagnostics import sanitized_exception_message
from app.services.gemini_provider import GeminiModelProvider
from app.services.model_provider import build_model_provider, request_structured_output


class FakeGeminiModels:
    def __init__(self, response=None, error: Exception | None = None) -> None:
        self.response = response
        self.error = error
        self.calls = []

    async def generate_content(self, **kwargs):
        self.calls.append(kwargs)
        if self.error:
            raise self.error
        return self.response


def fake_client(models: FakeGeminiModels):
    return SimpleNamespace(aio=SimpleNamespace(models=models))


def configured_settings(provider: str = "gemini") -> Settings:
    return Settings(
        ai_provider=provider,
        ai_model="gemini-2.5-flash",
        ai_api_key="test-key-not-a-real-secret",
        ai_timeout_seconds=1,
        agent_version="test",
    )


def test_gemini_provider_configuration_builds_real_adapter() -> None:
    provider = build_model_provider(configured_settings())

    assert isinstance(provider, GeminiModelProvider)
    assert provider._model == "gemini-2.5-flash"


@pytest.mark.asyncio
async def test_unsupported_configured_provider_fails_safely() -> None:
    provider = build_model_provider(configured_settings(provider="unknown-provider"))

    with pytest.raises(UnsupportedProviderError):
        await request_structured_output(
            provider,
            output_schema=Plan,
            instructions="Use the fixed plan.",
            input_data={},
            timeout_seconds=1,
        )


@pytest.mark.asyncio
async def test_gemini_adapter_returns_fake_structured_success() -> None:
    models = FakeGeminiModels(
        response=SimpleNamespace(
            parsed={
                "steps": [
                    "analyze_application_data",
                    "analyze_document_metadata",
                    "analyze_consistency",
                    "summarize_findings",
                ]
            },
            text=None,
        )
    )
    provider = GeminiModelProvider(
        api_key="fake-key",
        model="gemini-test-model",
        client=fake_client(models),
    )

    result = await request_structured_output(
        provider,
        output_schema=Plan,
        instructions="Use the fixed plan.",
        input_data={"objective": "test"},
        timeout_seconds=1,
    )

    assert isinstance(result, Plan)
    assert models.calls[0]["model"] == "gemini-test-model"
    assert models.calls[0]["config"].response_mime_type == "application/json"
    provider_schema = models.calls[0]["config"].response_schema
    assert isinstance(provider_schema, type)
    assert issubclass(provider_schema, Plan)


def _schema_keys(value: Any) -> set[str]:
    if isinstance(value, dict):
        return set(value).union(*(_schema_keys(item) for item in value.values()))
    if isinstance(value, list):
        return set().union(*(_schema_keys(item) for item in value))
    return set()


@pytest.mark.asyncio
async def test_gemini_adapter_uses_compatible_schema_without_weakening_local_model() -> None:
    models = FakeGeminiModels(
        response=SimpleNamespace(
            parsed={
                "completeness_findings": [],
                "inconsistency_findings": [],
                "explanation": "Complete.",
            },
            text=None,
        )
    )
    provider = GeminiModelProvider(
        api_key="fake-key",
        model="gemini-2.5-flash",
        client=fake_client(models),
    )

    result = await request_structured_output(
        provider,
        output_schema=ApplicationDataAnalysis,
        instructions="Analyze the data.",
        input_data={},
        timeout_seconds=1,
    )

    assert isinstance(result, ApplicationDataAnalysis)
    provider_schema = models.calls[0]["config"].response_schema
    assert isinstance(provider_schema, type)
    assert issubclass(provider_schema, ApplicationDataAnalysis)
    assert {
        "additionalProperties",
        "minLength",
        "maxLength",
        "maxItems",
    }.isdisjoint(_schema_keys(provider_schema.model_json_schema()))
    assert "additionalProperties" in _schema_keys(ApplicationDataAnalysis.model_json_schema())
    assert "maxLength" in _schema_keys(ApplicationDataAnalysis.model_json_schema())
    assert "maxItems" in _schema_keys(ApplicationDataAnalysis.model_json_schema())


@pytest.mark.asyncio
async def test_gemini_adapter_malformed_text_is_safely_rejected(
    caplog: pytest.LogCaptureFixture,
) -> None:
    models = FakeGeminiModels(response=SimpleNamespace(parsed=None, text="not-json"))
    provider = GeminiModelProvider(
        api_key="fake-key",
        model="gemini-test-model",
        client=fake_client(models),
    )

    with caplog.at_level(logging.DEBUG, logger="app.services.model_provider"):
        with pytest.raises(ModelOutputValidationError):
            await request_structured_output(
                provider,
                output_schema=Plan,
                instructions="Use the fixed plan.",
                input_data={},
                timeout_seconds=1,
                invocation_name="planner",
            )

    assert "node=planner" in caplog.text
    assert "category=structured_output_validation_failure" in caplog.text
    assert "input_value" not in caplog.text


@pytest.mark.asyncio
async def test_gemini_adapter_timeout_is_sanitized(
    caplog: pytest.LogCaptureFixture,
) -> None:
    class SlowModels:
        cancelled = False

        async def generate_content(self, **kwargs):
            del kwargs
            try:
                await asyncio.sleep(0.1)
            except asyncio.CancelledError:
                self.cancelled = True
                raise

    models = SlowModels()
    provider = GeminiModelProvider(
        api_key="fake-key",
        model="gemini-test-model",
        client=fake_client(models),
    )

    with caplog.at_level(logging.DEBUG, logger="app.services.model_provider"):
        with pytest.raises(ModelTimeoutError):
            await request_structured_output(
                provider,
                output_schema=Plan,
                instructions="Use the fixed plan.",
                input_data={},
                timeout_seconds=0.001,
                invocation_name="planner",
            )

    assert models.cancelled is True
    assert "category=timeout" in caplog.text
    assert "exception_type=builtins.TimeoutError" in caplog.text


@pytest.mark.asyncio
async def test_gemini_adapter_provider_failure_is_sanitized(
    caplog: pytest.LogCaptureFixture,
) -> None:
    provider_error = errors.ClientError(
        401,
        {
            "error": {
                "code": 401,
                "message": (
                    "provider-detail api_key=secret-api-key "
                    "Authorization:Bearer secret-authorization"
                ),
                "status": "UNAUTHENTICATED",
            }
        },
        None,
    )
    models = FakeGeminiModels(error=provider_error)
    provider = GeminiModelProvider(
        api_key="fake-key",
        model="gemini-test-model",
        client=fake_client(models),
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

    assert "provider-detail" not in str(captured.value)
    assert "google.genai.errors.ClientError" in caplog.text
    assert "node=planner" in caplog.text
    assert "category=provider_http_failure" in caplog.text
    assert "status=401/UNAUTHENTICATED" in caplog.text
    assert "model=gemini-test-model" in caplog.text
    assert "provider-detail" in caplog.text
    assert "secret-api-key" not in caplog.text
    assert "secret-authorization" not in caplog.text
    assert "[REDACTED]" in caplog.text


@pytest.mark.asyncio
async def test_gemini_diagnostics_are_not_logged_at_production_level(
    caplog: pytest.LogCaptureFixture,
) -> None:
    models = FakeGeminiModels(error=RuntimeError("provider-development-detail"))
    provider = GeminiModelProvider(
        api_key="fake-key",
        model="gemini-2.5-flash",
        client=fake_client(models),
    )

    with caplog.at_level(logging.INFO, logger="app.services.model_provider"):
        with pytest.raises(ModelInvocationError):
            await request_structured_output(
                provider,
                output_schema=Plan,
                instructions="Use the fixed plan.",
                input_data={},
                timeout_seconds=1,
            )

    assert "provider-development-detail" not in caplog.text


@pytest.mark.asyncio
async def test_application_level_provider_exception_is_categorized(
    caplog: pytest.LogCaptureFixture,
) -> None:
    models = FakeGeminiModels(error=RuntimeError("safe-development-diagnostic"))
    provider = GeminiModelProvider(
        api_key="fake-key",
        model="gemini-2.5-flash",
        client=fake_client(models),
    )

    with caplog.at_level(logging.DEBUG, logger="app.services.model_provider"):
        with pytest.raises(ModelInvocationError):
            await request_structured_output(
                provider,
                output_schema=Plan,
                instructions="Use the fixed plan.",
                input_data={},
                timeout_seconds=1,
                invocation_name="planner",
            )

    assert "category=application_level_exception" in caplog.text
    assert "exception_type=builtins.RuntimeError" in caplog.text


@pytest.mark.asyncio
async def test_sdk_pydantic_failure_is_categorized_as_structured_output(
    caplog: pytest.LogCaptureFixture,
) -> None:
    with pytest.raises(ValidationError) as captured:
        Plan.model_validate({"steps": ["invalid-step"]})
    provider = GeminiModelProvider(
        api_key="fake-key",
        model="gemini-2.5-flash",
        client=fake_client(FakeGeminiModels(error=captured.value)),
    )

    with caplog.at_level(logging.DEBUG, logger="app.services.model_provider"):
        with pytest.raises(ModelInvocationError):
            await request_structured_output(
                provider,
                output_schema=Plan,
                instructions="Use the fixed plan.",
                input_data={},
                timeout_seconds=1,
                invocation_name="planner",
            )

    assert "category=structured_output_validation_failure" in caplog.text
    assert "exception_type=pydantic_core._pydantic_core.ValidationError" in caplog.text
    assert "input_value" not in caplog.text


def test_diagnostics_omit_messages_containing_request_data() -> None:
    exc = RuntimeError('{"contents":"private","inputData":{"occupation":"private"}}')

    assert sanitized_exception_message(exc) == (
        "Provider message omitted because it contained request data"
    )


@pytest.mark.asyncio
async def test_langgraph_state_failure_is_categorized(
    caplog: pytest.LogCaptureFixture,
) -> None:
    provider = GeminiModelProvider(
        api_key="fake-key",
        model="gemini-2.5-flash",
        client=fake_client(FakeGeminiModels()),
    )
    plan_node = create_nodes(provider, timeout_seconds=1, agent_version="test")["plan"]

    with caplog.at_level(logging.DEBUG, logger="app.agents.nodes"):
        with pytest.raises(KeyError):
            await plan_node({})

    assert "event=langgraph_node_failed" in caplog.text
    assert "node=planner" in caplog.text
    assert "category=langgraph_state_schema_failure" in caplog.text
    assert "Missing state key 'objective'" in caplog.text
