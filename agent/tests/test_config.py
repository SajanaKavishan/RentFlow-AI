from __future__ import annotations

import logging

from app import config as config_module
from app.config import Settings
from app.services.diagnostics import log_development_event

_CONFIGURATION_NAMES = (
    "AI_PROVIDER",
    "AI_MODEL",
    "AI_API_KEY",
    "GROQ_API_KEY",
    "AI_TIMEOUT_SECONDS",
    "AGENT_VERSION",
)


def _clear_configuration(monkeypatch) -> None:
    for name in _CONFIGURATION_NAMES:
        monkeypatch.delenv(name, raising=False)


def test_dotenv_values_load_when_os_environment_is_absent(
    tmp_path,
    monkeypatch,
) -> None:
    _clear_configuration(monkeypatch)
    env_file = tmp_path / ".env"
    env_file.write_text(
        "\n".join(
            (
                "AI_PROVIDER=groq",
                "AI_MODEL=openai/gpt-oss-20b",
                "GROQ_API_KEY=file-groq-secret",
                "AI_TIMEOUT_SECONDS=12.5",
                "AGENT_VERSION=dotenv-test",
            )
        ),
        encoding="utf-8",
    )

    monkeypatch.setattr(config_module, "_DEFAULT_ENV_FILE", env_file)

    settings = Settings.from_environment()

    assert settings.ai_provider == "groq"
    assert settings.ai_model == "openai/gpt-oss-20b"
    assert settings.groq_api_key == "file-groq-secret"
    assert settings.ai_timeout_seconds == 12.5
    assert settings.agent_version == "dotenv-test"
    assert settings.provider_is_configured is True


def test_os_environment_overrides_dotenv_values(tmp_path, monkeypatch) -> None:
    _clear_configuration(monkeypatch)
    env_file = tmp_path / ".env"
    env_file.write_text(
        "\n".join(
            (
                "AI_PROVIDER=groq",
                "AI_MODEL=openai/gpt-oss-20b",
                "GROQ_API_KEY=file-secret",
                "AI_TIMEOUT_SECONDS=30",
                "AGENT_VERSION=file-version",
            )
        ),
        encoding="utf-8",
    )
    monkeypatch.setenv("AI_PROVIDER", "gemini")
    monkeypatch.setenv("AI_MODEL", "gemini-2.5-flash")
    monkeypatch.setenv("AI_API_KEY", "os-gemini-secret")
    monkeypatch.setenv("GROQ_API_KEY", "os-groq-secret")
    monkeypatch.setenv("AI_TIMEOUT_SECONDS", "7")
    monkeypatch.setenv("AGENT_VERSION", "os-version")

    settings = Settings.from_environment(env_file)

    assert settings.ai_provider == "gemini"
    assert settings.ai_model == "gemini-2.5-flash"
    assert settings.ai_api_key == "os-gemini-secret"
    assert settings.groq_api_key == "os-groq-secret"
    assert settings.ai_timeout_seconds == 7
    assert settings.agent_version == "os-version"


def test_configuration_secrets_are_not_exposed_in_repr_or_diagnostics(
    tmp_path,
    monkeypatch,
    caplog,
) -> None:
    _clear_configuration(monkeypatch)
    env_file = tmp_path / ".env"
    env_file.write_text(
        "\n".join(
            (
                "AI_PROVIDER=groq",
                "AI_MODEL=openai/gpt-oss-20b",
                "AI_API_KEY=file-gemini-secret",
                "GROQ_API_KEY=file-groq-secret",
            )
        ),
        encoding="utf-8",
    )
    settings = Settings.from_environment(env_file)

    with caplog.at_level(logging.DEBUG, logger="app.config"):
        log_development_event(
            logging.getLogger("app.config"),
            "configuration_loaded",
            provider=settings.ai_provider,
            model=settings.ai_model,
        )

    assert "file-gemini-secret" not in repr(settings)
    assert "file-groq-secret" not in repr(settings)
    assert "file-gemini-secret" not in caplog.text
    assert "file-groq-secret" not in caplog.text
