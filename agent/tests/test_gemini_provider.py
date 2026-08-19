from __future__ import annotations

import asyncio
from types import SimpleNamespace

import pytest
from google.genai import errors

from app.config import Settings
from app.schemas.plan import Plan
from app.services.exceptions import (
    ModelInvocationError,
    ModelOutputValidationError,
    ModelTimeoutError,
    UnsupportedProviderError,
)
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
        ai_model="gemini-test-model",
        ai_api_key="test-key-not-a-real-secret",
        ai_timeout_seconds=1,
        agent_version="test",
    )


def test_gemini_provider_configuration_builds_real_adapter() -> None:
    provider = build_model_provider(configured_settings())

    assert isinstance(provider, GeminiModelProvider)


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


@pytest.mark.asyncio
async def test_gemini_adapter_malformed_text_is_safely_rejected() -> None:
    models = FakeGeminiModels(response=SimpleNamespace(parsed=None, text="not-json"))
    provider = GeminiModelProvider(
        api_key="fake-key",
        model="gemini-test-model",
        client=fake_client(models),
    )

    with pytest.raises(ModelOutputValidationError):
        await request_structured_output(
            provider,
            output_schema=Plan,
            instructions="Use the fixed plan.",
            input_data={},
            timeout_seconds=1,
        )


@pytest.mark.asyncio
async def test_gemini_adapter_timeout_is_sanitized() -> None:
    class SlowModels:
        async def generate_content(self, **kwargs):
            del kwargs
            await asyncio.sleep(0.1)

    provider = GeminiModelProvider(
        api_key="fake-key",
        model="gemini-test-model",
        client=fake_client(SlowModels()),
    )

    with pytest.raises(ModelTimeoutError):
        await request_structured_output(
            provider,
            output_schema=Plan,
            instructions="Use the fixed plan.",
            input_data={},
            timeout_seconds=0.001,
        )


@pytest.mark.asyncio
async def test_gemini_adapter_provider_failure_is_sanitized() -> None:
    provider_error = errors.ClientError(
        401,
        {
            "error": {
                "code": 401,
                "message": "provider-secret-detail",
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

    with pytest.raises(ModelInvocationError) as captured:
        await request_structured_output(
            provider,
            output_schema=Plan,
            instructions="Use the fixed plan.",
            input_data={},
            timeout_seconds=1,
        )

    assert "provider-secret-detail" not in str(captured.value)
