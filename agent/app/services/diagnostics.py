"""Development-only diagnostics with provider and request-data redaction."""

from __future__ import annotations

import logging
import os
import re
from typing import Any

from pydantic import ValidationError

_ENABLED_VALUES = {"1", "true", "yes", "on"}
_SENSITIVE_MESSAGE_PATTERNS = (
    re.compile(
        r"(?i)\b(?:authorization|proxy-authorization)\s*[:=]\s*"
        r"(?:bearer\s+)?[^\s,;}]+"
    ),
    re.compile(r"(?i)\b(?:x-goog-api-key|api[_-]?key)\s*[:=]\s*[^\s,;}]+"),
    re.compile(r"(?i)\bbearer\s+[a-z0-9._~+/=-]+"),
    re.compile(r"\bAIza[0-9A-Za-z_-]{20,}\b"),
)
_REQUEST_DATA_MARKERS = (
    '"inputdata"',
    '"applicationdata"',
    '"contentbase64"',
    '"documentmetadata"',
    '"deterministicfindings"',
    '"extractedtext"',
    '"contents"',
    '"messages"',
)


def diagnostics_enabled(logger: logging.Logger) -> bool:
    explicit = os.getenv("AI_DEVELOPMENT_DIAGNOSTICS", "").strip().casefold()
    return explicit in _ENABLED_VALUES or logger.isEnabledFor(logging.DEBUG)


def root_exception(exc: BaseException) -> BaseException:
    current = exc
    visited: set[int] = set()
    while id(current) not in visited:
        visited.add(id(current))
        if isinstance(current, TimeoutError):
            break
        nested = current.__cause__ or current.__context__
        if nested is None:
            break
        current = nested
    return current


def exception_type_name(exc: BaseException) -> str:
    root = root_exception(exc)
    return f"{type(root).__module__}.{type(root).__qualname__}"


def sanitized_exception_message(exc: BaseException) -> str:
    return _sanitize_exception_message(root_exception(exc))


def sanitized_provider_error_message(exc: BaseException) -> str:
    """Sanitize an SDK error without exposing its raw response body.

    Provider SDK exception text can contain a useful categorical 400 reason. The
    shared sanitizer suppresses it entirely whenever request-data markers occur.
    """
    return _sanitize_exception_message(exc)


def _sanitize_exception_message(exc: BaseException) -> str:
    if isinstance(exc, ValidationError):
        parts = []
        for error in exc.errors(include_input=False, include_url=False):
            location = ".".join(str(item) for item in error.get("loc", ())) or "root"
            parts.append(
                f"{location}: {error.get('type', 'validation_error')}: "
                f"{error.get('msg', 'validation failed')}"
            )
        message = "; ".join(parts)
    elif isinstance(exc, KeyError):
        message = f"Missing state key {exc.args[0]!r}" if exc.args else "Missing state key"
    else:
        message = str(exc)

    message = message.replace("\r", " ").replace("\n", " ")
    if any(marker in message.casefold() for marker in _REQUEST_DATA_MARKERS):
        return "Provider message omitted because it contained request data"
    for pattern in _SENSITIVE_MESSAGE_PATTERNS:
        message = pattern.sub("[REDACTED]", message)
    return message[:2000] or "No exception message"


def provider_status(exc: BaseException) -> str:
    root = root_exception(exc)
    code = ""
    for candidate in (root, getattr(root, "response", None)):
        if candidate is None:
            continue
        for attribute in ("code", "status_code"):
            value = getattr(candidate, attribute, None)
            if isinstance(value, int):
                code = str(value)
                break
            if isinstance(value, str) and value.isascii() and len(value) <= 40:
                code = value
                break
        if code:
            break
    reason = getattr(root, "status", None)
    safe_reason = (
        reason
        if isinstance(reason, str)
        and reason.isascii()
        and len(reason) <= 80
        and re.fullmatch(r"[A-Z0-9_-]+", reason)
        else ""
    )
    if code and safe_reason:
        return f"{code}/{safe_reason}"
    return code or safe_reason or "none"


def safe_model_name(value: Any) -> str:
    model = str(value)
    return re.sub(r"[^a-zA-Z0-9._:/-]", "?", model)[:200] or "unknown"


def log_development_event(
    logger: logging.Logger,
    event: str,
    **fields: Any,
) -> None:
    if not diagnostics_enabled(logger):
        return
    safe_fields = " ".join(f"{name}={value}" for name, value in fields.items())
    # The explicit flag is useful with Uvicorn's normal INFO configuration. It
    # is opt-in and temporary; DEBUG logging remains the other development path.
    level = logging.DEBUG if logger.isEnabledFor(logging.DEBUG) else logging.WARNING
    logger.log(level, "event=%s %s", event, safe_fields)
