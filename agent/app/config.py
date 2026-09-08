"""Environment-backed configuration with no secret values in source control."""

from __future__ import annotations

import os
from collections.abc import Mapping
from dataclasses import dataclass, field
from pathlib import Path

from dotenv import dotenv_values

_DEFAULT_ENV_FILE = Path(__file__).resolve().parents[1] / ".env"


@dataclass(frozen=True, slots=True)
class Settings:
    ai_provider: str | None
    ai_model: str | None
    ai_api_key: str | None = field(repr=False)
    ai_timeout_seconds: float
    agent_version: str
    groq_api_key: str | None = field(default=None, repr=False)
    vision_provider: str | None = None
    vision_model: str | None = None
    vision_api_key: str | None = field(default=None, repr=False)
    max_pdf_pages: int = 5
    max_extracted_characters: int = 50_000
    max_model_input_characters: int = 20_000
    extraction_timeout_seconds: float = 20.0
    income_tolerance_percent: float = 5.0

    @classmethod
    def from_environment(
        cls,
        env_file: str | os.PathLike[str] | None = None,
    ) -> "Settings":
        file_values = _dotenv_values(env_file)
        return cls(
            ai_provider=_optional_configuration_value("AI_PROVIDER", file_values),
            ai_model=_optional_configuration_value("AI_MODEL", file_values),
            ai_api_key=(
                _optional_configuration_value("GEMINI_API_KEY", file_values)
                or _optional_configuration_value("AI_API_KEY", file_values)
            ),
            ai_timeout_seconds=_positive_float(
                "AI_TIMEOUT_SECONDS",
                file_values,
                default=30.0,
            ),
            agent_version=(
                _configuration_value("AGENT_VERSION", file_values) or "0.1.0"
            ).strip()
            or "0.1.0",
            groq_api_key=_optional_configuration_value("GROQ_API_KEY", file_values),
            vision_provider=_optional_configuration_value("VISION_PROVIDER", file_values),
            vision_model=_optional_configuration_value("VISION_MODEL", file_values),
            vision_api_key=_optional_configuration_value("VISION_API_KEY", file_values),
            max_pdf_pages=_positive_int("MAX_PDF_PAGES", file_values, default=5),
            max_extracted_characters=_positive_int(
                "MAX_EXTRACTED_CHARACTERS", file_values, default=50_000
            ),
            max_model_input_characters=_positive_int(
                "MAX_MODEL_INPUT_CHARACTERS", file_values, default=20_000
            ),
            extraction_timeout_seconds=_positive_float(
                "EXTRACTION_TIMEOUT_SECONDS", file_values, default=20.0
            ),
            income_tolerance_percent=_nonnegative_float(
                "INCOME_TOLERANCE_PERCENT", file_values, default=5.0
            ),
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

    @property
    def gemini_api_key(self) -> str | None:
        """Provider-specific name while retaining AI_API_KEY compatibility."""
        return self.ai_api_key


def _dotenv_values(
    env_file: str | os.PathLike[str] | None,
) -> Mapping[str, str | None]:
    path = Path(env_file) if env_file is not None else _DEFAULT_ENV_FILE
    if not path.is_file():
        return {}
    return dotenv_values(dotenv_path=path)


def _configuration_value(
    name: str,
    file_values: Mapping[str, str | None],
) -> str | None:
    # A real process variable wins even when it is intentionally empty.
    if name in os.environ:
        return os.environ[name]
    return file_values.get(name)


def _optional_configuration_value(
    name: str,
    file_values: Mapping[str, str | None],
) -> str | None:
    value = _configuration_value(name, file_values)
    if value is None:
        return None
    value = value.strip()
    return value or None


def _positive_float(
    name: str,
    file_values: Mapping[str, str | None],
    *,
    default: float,
) -> float:
    raw_value = _configuration_value(name, file_values)
    if not raw_value:
        return default
    try:
        value = float(raw_value)
    except ValueError:
        return default
    return value if value > 0 else default


def _positive_int(
    name: str,
    file_values: Mapping[str, str | None],
    *,
    default: int,
) -> int:
    raw_value = _configuration_value(name, file_values)
    if not raw_value:
        return default
    try:
        value = int(raw_value)
    except ValueError:
        return default
    return value if value > 0 else default


def _nonnegative_float(
    name: str,
    file_values: Mapping[str, str | None],
    *,
    default: float,
) -> float:
    raw_value = _configuration_value(name, file_values)
    if not raw_value:
        return default
    try:
        value = float(raw_value)
    except ValueError:
        return default
    return value if value >= 0 else default
