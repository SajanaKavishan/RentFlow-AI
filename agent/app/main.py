"""FastAPI entry point for the private RentFlow AI service."""

from __future__ import annotations

import logging
import hmac

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from app.api.routes import router
from app.config import Settings
from app.schemas.responses import ErrorDetail, ErrorResponse
from app.services.exceptions import AgentServiceError
from app.services.model_provider import (
    ModelProvider,
    build_model_provider,
    build_vision_model_provider,
)

logger = logging.getLogger(__name__)


def create_app(
    *,
    settings: Settings | None = None,
    model_provider: ModelProvider | None = None,
    vision_model_provider: ModelProvider | None = None,
) -> FastAPI:
    resolved_settings = settings or Settings.from_environment()
    app = FastAPI(
        title="RentFlow AI Application Validation Agent",
        version=resolved_settings.agent_version,
    )
    app.state.settings = resolved_settings
    app.state.model_provider = model_provider or build_model_provider(resolved_settings)
    app.state.vision_model_provider = vision_model_provider or build_vision_model_provider(
        resolved_settings, app.state.model_provider
    )
    @app.middleware("http")
    async def authenticate_internal_service(request: Request, call_next):
        if request.url.path.startswith("/internal/"):
            expected = resolved_settings.service_api_key
            if not expected:
                return JSONResponse(status_code=503, content={"error": {"code": "service_auth_not_configured", "message": "Internal analysis is unavailable.", "retryable": False}})
            supplied = request.headers.get("X-RentFlow-Service-Key", "")
            if not hmac.compare_digest(supplied.encode("utf-8"), expected.encode("utf-8")):
                return JSONResponse(status_code=401, content={"error": {"code": "service_unauthorized", "message": "Service authentication required.", "retryable": False}})
        return await call_next(request)

    app.include_router(router)

    @app.exception_handler(AgentServiceError)
    async def handle_agent_service_error(
        request: Request, exc: AgentServiceError
    ) -> JSONResponse:
        del request
        logger.warning("Agent analysis failed with code=%s", exc.code)
        status_code = 503 if exc.code in {
            "provider_not_configured",
            "unsupported_provider",
        } else 502
        body = ErrorResponse(
            error=ErrorDetail(
                code=exc.code,
                message=exc.public_message,
                retryable=exc.retryable,
            )
        )
        return JSONResponse(status_code=status_code, content=body.model_dump(mode="json"))

    @app.exception_handler(Exception)
    async def handle_unexpected_error(request: Request, exc: Exception) -> JSONResponse:
        del request, exc
        # Do not log exception content: provider errors can contain request or credential data.
        logger.error("Unexpected agent graph failure")
        body = ErrorResponse(
            error=ErrorDetail(
                code="analysis_failed",
                message="The analysis could not be completed safely.",
                retryable=True,
            )
        )
        return JSONResponse(status_code=500, content=body.model_dump(mode="json"))

    return app


app = create_app()
