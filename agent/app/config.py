"""Environment-backed configuration with no secret values in source control."""

from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class Settings:
    ai_provider: str | None
    ai_model: str | None
    ai_api_key: str | None
    ai_timeout_seconds: float
    agent_version: str
    groq_api_key: str | None = None

    @classmethod
    def from_environment(cls) -> "Settings":
        return cls(
            ai_provider=_optional_environment_value("AI_PROVIDER"),
            ai_model=_optional_environment_value("AI_MODEL"),
            ai_api_key=_optional_environment_value("AI_API_KEY"),
            ai_timeout_seconds=_positive_float("AI_TIMEOUT_SECONDS", default=30.0),
            agent_version=os.getenv("AGENT_VERSION", "0.1.0").strip() or "0.1.0",
            groq_api_key=_optional_environment_value("GROQ_API_KEY"),
        )

    @property
    def provider_is_configured(self) -> bool:
        if not self.ai_provider or not self.ai_model:
            return False
        provider_name = self.ai_provider.casefold()
        if provider_name in {"gemini", "google", "google-genai"}:
            return bool(self.ai_api_key)
        if provider_name == "groq":
            return bool(self.groq_api_key)
        return True


def _optional_environment_value(name: str) -> str | None:
    value = os.getenv(name)
    if value is None:
        return None
    value = value.strip()
    return value or None


def _positive_float(name: str, *, default: float) -> float:
    raw_value = os.getenv(name)
    if not raw_value:
        return default
    try:
        value = float(raw_value)
    except ValueError:
        return default
    return value if value > 0 else default
