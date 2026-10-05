"""Groq adapter for provider-neutral structured model calls."""

from __future__ import annotations

import base64
import json
import re
from typing import Any

from groq import AsyncGroq

from app.services.diagnostics import (
    provider_status,
    sanitized_provider_error_message,
)
from app.services.exceptions import (
    ModelInvocationError,
    VisionCapabilityUnavailableError,
)
from app.services.model_provider import (
    ModelCapabilities,
    ModelMedia,
    ModelProvider,
    StructuredOutput,
)

_LOCAL_VALIDATION_ONLY_KEYWORDS = {
    "default",
    "maxItems",
    "maxLength",
    "minItems",
    "minLength",
    # Groq strict Structured Outputs rejects Pydantic regex constraints even
    # though the full local model continues to enforce them after generation.
    "pattern",
    "title",
}

_GROQ_STRICT_JSON_SCHEMA_MODELS = {
    "openai/gpt-oss-20b",
    "openai/gpt-oss-120b",
}
_GROQ_VISION_MODELS = {
    "qwen/qwen3.6-27b",
}
_CONTEXT_SIZE_DIAGNOSTIC_CHARACTERS = 400_000


def _groq_strict_schema(output_schema: type[StructuredOutput]) -> dict[str, Any]:
    """Build Groq's strict JSON Schema without changing the local model."""
    schema = output_schema.model_json_schema(by_alias=True)
    _normalize_strict_schema(schema, schema.get("$defs", {}))
    return schema


def _normalize_strict_schema(value: Any, definitions: dict[str, Any] | None = None) -> None:
    if isinstance(value, dict):
        # Groq rejects nullable primitive anyOf/$ref combinations. Its documented
        # union-type representation keeps the same enum/null semantics.
        branches = value.get("anyOf")
        if isinstance(branches, list) and len(branches) == 2:
            nulls = [branch for branch in branches if isinstance(branch, dict) and branch.get("type") == "null"]
            others = [branch for branch in branches if branch not in nulls]
            if len(nulls) == 1 and len(others) == 1 and isinstance(others[0], dict):
                candidate = others[0]
                reference = candidate.get("$ref", "")
                if reference.startswith("#/$defs/"):
                    candidate = (definitions or {}).get(reference.removeprefix("#/$defs/"), candidate)
                if isinstance(candidate.get("type"), str) and candidate["type"] in {"string", "integer", "number", "boolean"}:
                    value.pop("anyOf")
                    value.update(candidate)
                    value["type"] = [candidate["type"], "null"]
                    if "enum" in candidate:
                        value["enum"] = [*candidate["enum"], None]
                    elif "const" in candidate:
                        value.pop("const", None)
                        value["enum"] = [candidate["const"], None]
        for keyword in _LOCAL_VALIDATION_ONLY_KEYWORDS:
            value.pop(keyword, None)

        properties = value.get("properties")
        if value.get("type") == "object" and isinstance(properties, dict):
            # Groq strict mode requires closed objects and every property to be
            # required. Defaults remain a local Pydantic concern after parsing.
            value["additionalProperties"] = False
            value["required"] = list(properties)

        for nested_value in value.values():
            _normalize_strict_schema(nested_value, definitions)
    elif isinstance(value, list):
        for nested_value in value:
            _normalize_strict_schema(nested_value, definitions)


def _schema_name(output_schema: type[StructuredOutput]) -> str:
    normalized = re.sub(r"[^a-zA-Z0-9_-]", "_", output_schema.__name__)
    return normalized[:64] or "structured_output"


class GroqModelProvider(ModelProvider):
    """Uses the official asynchronous Groq SDK and strict Structured Outputs."""

    def __init__(self, *, api_key: str, model: str, client: Any | None = None) -> None:
        if not api_key.strip():
            raise ValueError("A Groq API key is required")
        if not model.strip():
            raise ValueError("A Groq model is required")

        self._model = model.strip()
        # Shared asyncio.wait_for owns the per-node deadline, so SDK retries are
        # disabled to keep timeout and rate-limit behavior deterministic.
        self._client = client or AsyncGroq(api_key=api_key.strip(), max_retries=0)

    @property
    def model_name(self) -> str:
        return self._model

    @property
    def capabilities(self) -> ModelCapabilities:
        return ModelCapabilities(
            text_structured_reasoning=True,
            vision_document_images=self._model.casefold() in _GROQ_VISION_MODELS,
        )

    async def generate_structured(
        self,
        *,
        output_schema: type[StructuredOutput],
        instructions: str,
        input_data: dict[str, Any],
    ) -> Any:
        messages = [
            {"role": "system", "content": instructions},
            {
                "role": "user",
                "content": json.dumps(
                    {"inputData": input_data},
                    ensure_ascii=True,
                    separators=(",", ":"),
                ),
            },
        ]
        response_format = {
            "type": "json_schema",
            "json_schema": {
                "name": _schema_name(output_schema),
                "strict": True,
                "schema": _groq_strict_schema(output_schema),
            },
        }
        try:
            response = await self._client.chat.completions.create(
                model=self._model,
                messages=messages,
                response_format=response_format,
                temperature=0,
            )
        except Exception as exc:
            # Raw SDK/provider errors remain available only through exception
            # chaining for sanitized development diagnostics.
            raise _model_invocation_error(
                exc,
                model=self._model,
                response_format_type="json_schema",
                request_characters=len(json.dumps(messages, ensure_ascii=True)),
            ) from exc

        choices = getattr(response, "choices", None)
        if not choices:
            return None
        message = getattr(choices[0], "message", None)
        if message is None or getattr(message, "refusal", None):
            return None
        content = getattr(message, "content", None)
        if not content:
            return None
        try:
            return json.loads(content)
        except (json.JSONDecodeError, TypeError):
            # Shared local validation maps malformed content to a safe error.
            return content

    async def generate_structured_with_media(
        self,
        *,
        output_schema: type[StructuredOutput],
        instructions: str,
        input_data: dict[str, Any],
        media: list[ModelMedia],
    ) -> Any:
        if not self.capabilities.vision_document_images:
            raise VisionCapabilityUnavailableError

        user_content: list[dict[str, Any]] = [
            {
                "type": "text",
                "text": json.dumps(
                    {"inputData": input_data},
                    ensure_ascii=True,
                    separators=(",", ":"),
                ),
            }
        ]
        for item in media:
            if not item.content_type.startswith("image/"):
                raise VisionCapabilityUnavailableError
            encoded = base64.b64encode(item.content).decode("ascii")
            user_content.append(
                {
                    "type": "image_url",
                    "image_url": {
                        "url": f"data:{item.content_type};base64,{encoded}"
                    },
                }
            )

        # Groq's current vision model supports JSON Object Mode, not JSON Schema
        # Mode. The provider-neutral boundary still validates the full Pydantic
        # model locally.
        schema = _groq_strict_schema(output_schema)
        vision_instructions = (
            f"{instructions}\nReturn only one JSON object matching this schema: "
            + json.dumps(schema, ensure_ascii=True, separators=(",", ":"))
        )
        messages = [
            {"role": "system", "content": vision_instructions},
            {"role": "user", "content": user_content},
        ]
        try:
            response = await self._client.chat.completions.create(
                model=self._model,
                messages=messages,
                response_format={"type": "json_object"},
                temperature=0,
            )
        except Exception as exc:
            raise _model_invocation_error(
                exc,
                model=self._model,
                response_format_type="json_object",
                request_characters=len(json.dumps(messages, ensure_ascii=True)),
            ) from exc

        choices = getattr(response, "choices", None)
        message = getattr(choices[0], "message", None) if choices else None
        content = getattr(message, "content", None) if message is not None else None
        if message is None or getattr(message, "refusal", None) or not content:
            return None
        try:
            return json.loads(content)
        except (json.JSONDecodeError, TypeError):
            return content


def _model_invocation_error(
    exc: BaseException,
    *,
    model: str,
    response_format_type: str,
    request_characters: int,
) -> ModelInvocationError:
    message = sanitized_provider_error_message(exc)
    category: str | None = None
    if provider_status(exc).startswith("400"):
        normalized = message.casefold()
        if "schema" in normalized:
            category = "provider_json_schema_incompatibility"
        elif any(
            marker in normalized
            for marker in ("context", "token limit", "too large", "maximum length")
        ) or request_characters > _CONTEXT_SIZE_DIAGNOSTIC_CHARACTERS:
            category = "provider_request_size_or_context"
        elif (
            "response_format" in normalized
            or (
                response_format_type == "json_schema"
                and model.casefold() not in _GROQ_STRICT_JSON_SCHEMA_MODELS
            )
        ):
            category = "provider_response_format_unsupported"
        else:
            category = "provider_request_malformed"
    return ModelInvocationError(
        diagnostic_category=category,
        diagnostic_message=message,
    )
