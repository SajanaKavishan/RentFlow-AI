"""Google Gemini adapter for provider-neutral structured model calls."""

from __future__ import annotations

import json
from typing import Any

from google import genai
from google.genai import types

from app.services.exceptions import ModelInvocationError
from app.services.model_provider import ModelProvider, StructuredOutput


def _simplify_gemini_schema(value: Any) -> None:
    """Remove validation constraints that Gemini cannot reliably serve.

    Local Pydantic validation still applies the full schema after the response.
    """
    if isinstance(value, dict):
        # google-genai 1.x serializes False as `additional_properties`, which the
        # Gemini v1beta GenerateContent endpoint rejects. String length keywords
        # are outside its supported subset, and the 100-item caps make these
        # nested schemas exceed Gemini's serving-state limit.
        for key in ("additionalProperties", "minLength", "maxLength"):
            value.pop(key, None)
        if value.get("maxItems", 0) >= 100:
            value.pop("maxItems")
        for nested_value in value.values():
            _simplify_gemini_schema(nested_value)
    elif isinstance(value, list):
        for nested_value in value:
            _simplify_gemini_schema(nested_value)


def _gemini_output_schema(
    output_schema: type[StructuredOutput],
) -> type[StructuredOutput]:
    """Derive a Pydantic class with a Gemini-compatible JSON schema."""

    def model_json_schema(cls: type[StructuredOutput], **kwargs: Any) -> dict[str, Any]:
        del cls
        schema = output_schema.model_json_schema(**kwargs)
        _simplify_gemini_schema(schema)
        return schema

    return type(
        f"{output_schema.__name__}GeminiSchema",
        (output_schema,),
        {
            "__module__": output_schema.__module__,
            "model_json_schema": classmethod(model_json_schema),
        },
    )


class GeminiModelProvider(ModelProvider):
    """Uses Google's supported Gen AI SDK without leaking it into graph nodes."""

    def __init__(self, *, api_key: str, model: str, client: Any | None = None) -> None:
        if not api_key.strip():
            raise ValueError("A Gemini API key is required")
        if not model.strip():
            raise ValueError("A Gemini model is required")

        self._model = model.strip()
        self._client = client or genai.Client(
            api_key=api_key.strip(),
            http_options=types.HttpOptions(api_version="v1beta"),
        )

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
        prompt = json.dumps(
            {"instructions": instructions, "inputData": input_data},
            ensure_ascii=True,
            separators=(",", ":"),
        )
        provider_schema = _gemini_output_schema(output_schema)
        try:
            response = await self._client.aio.models.generate_content(
                model=self._model,
                contents=prompt,
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    response_schema=provider_schema,
                    temperature=0,
                ),
            )
        except Exception as exc:
            # Provider messages can contain request details; expose only our safe taxonomy.
            raise ModelInvocationError from exc

        parsed = getattr(response, "parsed", None)
        if parsed is not None:
            return parsed

        response_text = getattr(response, "text", None)
        if not response_text:
            return None
        try:
            return json.loads(response_text)
        except (json.JSONDecodeError, TypeError):
            # Central schema validation maps this to a sanitized malformed-output error.
            return response_text
