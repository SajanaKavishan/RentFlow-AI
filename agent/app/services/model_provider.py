"""Provider-neutral structured model invocation boundary."""

from __future__ import annotations

import asyncio
from abc import ABC, abstractmethod
from typing import Any, TypeVar

from pydantic import BaseModel, ValidationError

from app.config import Settings
from app.services.exceptions import (
    AgentServiceError,
    ModelInvocationError,
    ModelOutputValidationError,
    ModelTimeoutError,
    ProviderConfigurationError,
    UnsupportedProviderError,
)

StructuredOutput = TypeVar("StructuredOutput", bound=BaseModel)


class ModelProvider(ABC):
    @abstractmethod
    async def generate_structured(
        self,
        *,
        output_schema: type[StructuredOutput],
        instructions: str,
        input_data: dict[str, Any],
    ) -> Any:
        """Return provider output for validation by the shared boundary."""


class UnavailableModelProvider(ModelProvider):
    def __init__(self, *, configured: bool) -> None:
        self._configured = configured

    async def generate_structured(
        self,
        *,
        output_schema: type[StructuredOutput],
        instructions: str,
        input_data: dict[str, Any],
    ) -> Any:
        del output_schema, instructions, input_data
        if not self._configured:
            raise ProviderConfigurationError
        raise ProviderConfigurationError("Configured provider adapter is not installed")


class UnsupportedModelProvider(ModelProvider):
    async def generate_structured(
        self,
        *,
        output_schema: type[StructuredOutput],
        instructions: str,
        input_data: dict[str, Any],
    ) -> Any:
        del output_schema, instructions, input_data
        raise UnsupportedProviderError


def build_model_provider(settings: Settings) -> ModelProvider:
    if not settings.provider_is_configured:
        return UnavailableModelProvider(configured=False)

    provider_name = settings.ai_provider.casefold() if settings.ai_provider else ""
    if provider_name in {"gemini", "google", "google-genai"}:
        from app.services.gemini_provider import GeminiModelProvider

        return GeminiModelProvider(
            api_key=settings.ai_api_key or "",
            model=settings.ai_model or "",
        )
    # Configuration errors are reported on analysis; health/startup remain available.
    return UnsupportedModelProvider()


async def request_structured_output(
    provider: ModelProvider,
    *,
    output_schema: type[StructuredOutput],
    instructions: str,
    input_data: dict[str, Any],
    timeout_seconds: float,
) -> StructuredOutput:
    try:
        raw_output = await asyncio.wait_for(
            provider.generate_structured(
                output_schema=output_schema,
                instructions=instructions,
                input_data=input_data,
            ),
            timeout=timeout_seconds,
        )
    except (ProviderConfigurationError, UnsupportedProviderError):
        raise
    except TimeoutError as exc:
        raise ModelTimeoutError from exc
    except AgentServiceError:
        raise
    except Exception as exc:
        raise ModelInvocationError from exc

    try:
        if isinstance(raw_output, output_schema):
            return raw_output
        return output_schema.model_validate(raw_output)
    except (ValidationError, TypeError, ValueError) as exc:
        raise ModelOutputValidationError from exc
