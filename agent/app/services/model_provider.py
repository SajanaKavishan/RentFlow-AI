"""Provider-neutral structured model invocation boundary."""

from __future__ import annotations

import asyncio
import logging
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Any, TypeVar

from pydantic import BaseModel, ValidationError

from app.config import Settings
from app.services.diagnostics import (
    exception_type_name,
    log_development_event,
    provider_status,
    root_exception,
    safe_model_name,
    sanitized_exception_message,
)
from app.services.exceptions import (
    AgentServiceError,
    ModelInvocationError,
    ModelOutputValidationError,
    ModelTimeoutError,
    ProviderConfigurationError,
    UnsupportedProviderError,
    VisionCapabilityUnavailableError,
)

StructuredOutput = TypeVar("StructuredOutput", bound=BaseModel)
logger = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class ModelMedia:
    content_type: str
    content: bytes


@dataclass(frozen=True, slots=True)
class ModelCapabilities:
    text_structured_reasoning: bool
    vision_document_images: bool


class ModelProvider(ABC):
    @property
    def capabilities(self) -> ModelCapabilities:
        # Text is the established provider contract. Vision must always be opted
        # into explicitly by an adapter/model combination.
        return ModelCapabilities(
            text_structured_reasoning=True,
            vision_document_images=False,
        )

    @property
    def model_name(self) -> str:
        return type(self).__name__

    @abstractmethod
    async def generate_structured(
        self,
        *,
        output_schema: type[StructuredOutput],
        instructions: str,
        input_data: dict[str, Any],
    ) -> Any:
        """Return provider output for validation by the shared boundary."""

    async def generate_structured_with_media(
        self,
        *,
        output_schema: type[StructuredOutput],
        instructions: str,
        input_data: dict[str, Any],
        media: list[ModelMedia],
    ) -> Any:
        del output_schema, instructions, input_data, media
        raise VisionCapabilityUnavailableError


class UnavailableModelProvider(ModelProvider):
    def __init__(self, *, configured: bool) -> None:
        self._configured = configured

    @property
    def capabilities(self) -> ModelCapabilities:
        return ModelCapabilities(
            text_structured_reasoning=False,
            vision_document_images=False,
        )

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
            api_key=settings.gemini_api_key or "",
            model=settings.ai_model or "",
        )
    if provider_name == "groq":
        from app.services.groq_provider import GroqModelProvider

        return GroqModelProvider(
            api_key=settings.groq_api_key or "",
            model=settings.ai_model or "",
        )
    # Configuration errors are reported on analysis; health/startup remain available.
    return UnsupportedModelProvider()


def build_vision_model_provider(
    settings: Settings,
    primary_provider: ModelProvider,
) -> ModelProvider:
    """Build an optional dedicated OCR/vision provider without coupling graph logic."""
    if not settings.vision_provider and not settings.vision_model:
        if primary_provider.capabilities.vision_document_images:
            return primary_provider
        return UnavailableModelProvider(configured=False)
    if not settings.vision_provider or not settings.vision_model:
        return UnavailableModelProvider(configured=False)

    provider_name = settings.vision_provider.casefold()
    if provider_name in {"gemini", "google", "google-genai"}:
        from app.services.gemini_provider import GeminiModelProvider

        api_key = settings.vision_api_key or settings.gemini_api_key or ""
        if not api_key:
            return UnavailableModelProvider(configured=False)
        provider = GeminiModelProvider(api_key=api_key, model=settings.vision_model)
        return (
            provider
            if provider.capabilities.vision_document_images
            else UnavailableModelProvider(configured=True)
        )
    if provider_name == "groq":
        from app.services.groq_provider import GroqModelProvider

        api_key = settings.vision_api_key or settings.groq_api_key or ""
        if not api_key:
            return UnavailableModelProvider(configured=False)
        provider = GroqModelProvider(api_key=api_key, model=settings.vision_model)
        return (
            provider
            if provider.capabilities.vision_document_images
            else UnavailableModelProvider(configured=True)
        )
    return UnsupportedModelProvider()


async def request_structured_output(
    provider: ModelProvider,
    *,
    output_schema: type[StructuredOutput],
    instructions: str,
    input_data: dict[str, Any],
    timeout_seconds: float,
    invocation_name: str = "unspecified",
) -> StructuredOutput:
    model_name = safe_model_name(provider.model_name)
    log_development_event(
        logger,
        "model_invocation_started",
        node=invocation_name,
        model=model_name,
    )
    try:
        raw_output = await asyncio.wait_for(
            provider.generate_structured(
                output_schema=output_schema,
                instructions=instructions,
                input_data=input_data,
            ),
            timeout=timeout_seconds,
        )
    except (ProviderConfigurationError, UnsupportedProviderError) as exc:
        _log_invocation_failure(invocation_name, model_name, "application_level_exception", exc)
        raise
    except TimeoutError as exc:
        wrapped = ModelTimeoutError()
        wrapped.__cause__ = exc
        _log_invocation_failure(invocation_name, model_name, "timeout", wrapped)
        raise wrapped
    except AgentServiceError as exc:
        category = _agent_service_failure_category(exc)
        _log_invocation_failure(invocation_name, model_name, category, exc)
        raise
    except Exception as exc:
        wrapped = ModelInvocationError()
        wrapped.__cause__ = exc
        _log_invocation_failure(invocation_name, model_name, "application_level_exception", wrapped)
        raise wrapped

    try:
        if isinstance(raw_output, output_schema):
            validated_output = raw_output
        else:
            validated_output = output_schema.model_validate(raw_output)
    except (ValidationError, TypeError, ValueError) as exc:
        wrapped = ModelOutputValidationError()
        wrapped.__cause__ = exc
        _log_invocation_failure(
            invocation_name,
            model_name,
            "structured_output_validation_failure",
            wrapped,
        )
        raise wrapped

    log_development_event(
        logger,
        "model_invocation_succeeded",
        node=invocation_name,
        model=model_name,
    )
    return validated_output


async def request_structured_media_output(
    provider: ModelProvider,
    *,
    output_schema: type[StructuredOutput],
    instructions: str,
    input_data: dict[str, Any],
    media: list[ModelMedia],
    timeout_seconds: float,
    invocation_name: str,
) -> StructuredOutput:
    model_name = safe_model_name(provider.model_name)
    log_development_event(
        logger,
        "model_invocation_started",
        node=invocation_name,
        model=model_name,
    )
    try:
        raw_output = await asyncio.wait_for(
            provider.generate_structured_with_media(
                output_schema=output_schema,
                instructions=instructions,
                input_data=input_data,
                media=media,
            ),
            timeout=timeout_seconds,
        )
    except (
        ProviderConfigurationError,
        UnsupportedProviderError,
        VisionCapabilityUnavailableError,
    ) as exc:
        _log_invocation_failure(invocation_name, model_name, "application_level_exception", exc)
        raise
    except TimeoutError as exc:
        wrapped = ModelTimeoutError()
        wrapped.__cause__ = exc
        _log_invocation_failure(invocation_name, model_name, "timeout", wrapped)
        raise wrapped
    except AgentServiceError as exc:
        _log_invocation_failure(
            invocation_name, model_name, _agent_service_failure_category(exc), exc
        )
        raise
    except Exception as exc:
        wrapped = ModelInvocationError()
        wrapped.__cause__ = exc
        _log_invocation_failure(invocation_name, model_name, "application_level_exception", wrapped)
        raise wrapped

    try:
        validated_output = (
            raw_output
            if isinstance(raw_output, output_schema)
            else output_schema.model_validate(raw_output)
        )
    except (ValidationError, TypeError, ValueError) as exc:
        wrapped = ModelOutputValidationError()
        wrapped.__cause__ = exc
        _log_invocation_failure(
            invocation_name,
            model_name,
            "structured_output_validation_failure",
            wrapped,
        )
        raise wrapped

    log_development_event(
        logger,
        "model_invocation_succeeded",
        node=invocation_name,
        model=model_name,
    )
    return validated_output


def _log_invocation_failure(
    invocation_name: str,
    model_name: str,
    category: str,
    exc: BaseException,
) -> None:
    log_development_event(
        logger,
        "model_invocation_failed",
        node=invocation_name,
        category=category,
        exception_type=exception_type_name(exc),
        status=provider_status(exc),
        model=model_name,
        message=(
            getattr(exc, "diagnostic_message", None)
            or sanitized_exception_message(exc)
        ),
    )


def _agent_service_failure_category(exc: AgentServiceError) -> str:
    diagnostic_category = getattr(exc, "diagnostic_category", None)
    if diagnostic_category:
        return str(diagnostic_category)
    if not isinstance(exc, ModelInvocationError):
        return "application_level_exception"
    root = root_exception(exc)
    if isinstance(root, ValidationError):
        return "structured_output_validation_failure"
    type_name = exception_type_name(root)
    if isinstance(root, TimeoutError) or "Timeout" in type_name:
        return "timeout"
    if provider_status(root) != "none":
        return "provider_http_failure"
    if type_name.startswith(("google.genai.", "groq.", "httpx.")):
        return "provider_transport_failure"
    return "application_level_exception"
