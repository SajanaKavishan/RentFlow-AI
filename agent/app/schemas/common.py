"""Shared strict schema configuration and safety validation."""

from __future__ import annotations

import re
from typing import Any

from pydantic import BaseModel, ConfigDict, Field


class StrictModel(BaseModel):
    model_config = ConfigDict(
        extra="forbid",
        populate_by_name=True,
        strict=True,
        str_strip_whitespace=True,
    )


class Finding(StrictModel):
    code: str = Field(min_length=1, max_length=100)
    message: str = Field(min_length=1, max_length=1000)


_FORBIDDEN_INPUT_KEYS = {
    "age",
    "birthdate",
    "dateofbirth",
    "disability",
    "ethnicity",
    "gender",
    "nationality",
    "pregnancy",
    "race",
    "religion",
    "riskrating",
    "riskscore",
    "sexualorientation",
}


def reject_sensitive_input_keys(value: Any) -> Any:
    """Reject protected-characteristic and tenant-risk fields at every depth."""
    if isinstance(value, dict):
        for key, nested_value in value.items():
            normalized_key = re.sub(r"[^a-z0-9]", "", str(key).lower())
            if normalized_key in _FORBIDDEN_INPUT_KEYS:
                raise ValueError(f"Field '{key}' is not accepted for AI analysis")
            reject_sensitive_input_keys(nested_value)
    elif isinstance(value, list):
        for item in value:
            reject_sensitive_input_keys(item)
    return value
