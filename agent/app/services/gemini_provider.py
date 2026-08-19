"""Google Gemini adapter for provider-neutral structured model calls."""

from __future__ import annotations

import json
from typing import Any

from google import genai
from google.genai import errors, types

from app.services.exceptions import ModelInvocationError
from app.services.model_provider import ModelProvider, StructuredOutput


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
        try:
            response = await self._client.aio.models.generate_content(
                model=self._model,
                contents=prompt,
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    response_schema=output_schema,
                    temperature=0,
                ),
            )
        except errors.APIError as exc:
            # Provider messages can contain request details; map them to our safe taxonomy.
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
