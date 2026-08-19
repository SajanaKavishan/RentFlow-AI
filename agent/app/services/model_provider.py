"""Provider-neutral structured model invocation boundary."""

from __future__ import annotations

import asyncio
from abc import ABC, abstractmethod
from typing import Any, TypeVar

from pydantic import BaseModel, ValidationError

from app.config import Settings
from app.services.exceptions import (
    ModelInvocationError,
    ModelOutputValidationError,
    ModelTimeoutError,
    ProviderConfigurationError,
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


def build_model_provider(settings: Settings) -> ModelProvider:
    # Real provider adapters are deliberately deferred. This never silently fakes output.
    return UnavailableModelProvider(configured=settings.provider_is_configured)


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
    except ProviderConfigurationError:
        raise
    except TimeoutError as exc:
        raise ModelTimeoutError from exc
    except Exception as exc:
        raise ModelInvocationError from exc

    try:
        if isinstance(raw_output, output_schema):
            return raw_output
        return output_schema.model_validate(raw_output)
    except (ValidationError, TypeError, ValueError) as exc:
        raise ModelOutputValidationError from exc
