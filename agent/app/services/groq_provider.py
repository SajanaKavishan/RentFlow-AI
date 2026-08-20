"""Groq adapter for provider-neutral structured model calls."""

from __future__ import annotations

import json
import re
from typing import Any

from groq import AsyncGroq

from app.services.exceptions import ModelInvocationError
from app.services.model_provider import ModelProvider, StructuredOutput

_LOCAL_VALIDATION_ONLY_KEYWORDS = {
    "default",
    "maxItems",
    "maxLength",
    "minItems",
    "minLength",
    "title",
}


def _groq_strict_schema(output_schema: type[StructuredOutput]) -> dict[str, Any]:
    """Build Groq's strict JSON Schema without changing the local model."""
    schema = output_schema.model_json_schema(by_alias=True)
    _normalize_strict_schema(schema)
    return schema


def _normalize_strict_schema(value: Any) -> None:
    if isinstance(value, dict):
        for keyword in _LOCAL_VALIDATION_ONLY_KEYWORDS:
            value.pop(keyword, None)

        properties = value.get("properties")
        if value.get("type") == "object" and isinstance(properties, dict):
            # Groq strict mode requires closed objects and every property to be
            # required. Defaults remain a local Pydantic concern after parsing.
            value["additionalProperties"] = False
            value["required"] = list(properties)

        for nested_value in value.values():
            _normalize_strict_schema(nested_value)
    elif isinstance(value, list):
        for nested_value in value:
            _normalize_strict_schema(nested_value)


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
        try:
            response = await self._client.chat.completions.create(
                model=self._model,
                messages=messages,
                response_format={
                    "type": "json_schema",
                    "json_schema": {
                        "name": _schema_name(output_schema),
                        "strict": True,
                        "schema": _groq_strict_schema(output_schema),
                    },
                },
                temperature=0,
            )
        except Exception as exc:
            # Raw SDK/provider errors remain available only through exception
            # chaining for sanitized development diagnostics.
            raise ModelInvocationError from exc

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
