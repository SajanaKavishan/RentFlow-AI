"""Internal exception taxonomy; messages exposed by the API stay sanitized."""


class AgentServiceError(Exception):
    code = "analysis_failed"
    public_message = "The analysis could not be completed safely."
    retryable = True


class ProviderConfigurationError(AgentServiceError):
    code = "provider_not_configured"
    public_message = "AI analysis is not configured for this service."
    retryable = False


class UnsupportedProviderError(AgentServiceError):
    code = "unsupported_provider"
    public_message = "The configured AI provider is not supported."
    retryable = False


class ModelInvocationError(AgentServiceError):
    code = "model_invocation_failed"
    public_message = "The AI provider could not complete the analysis."

    def __init__(
        self,
        *,
        diagnostic_category: str | None = None,
        diagnostic_message: str | None = None,
    ) -> None:
        super().__init__()
        self.diagnostic_category = diagnostic_category
        self.diagnostic_message = diagnostic_message


class ModelOutputValidationError(AgentServiceError):
    code = "invalid_model_output"
    public_message = "The AI provider returned an invalid structured response."
    retryable = False


class ModelTimeoutError(AgentServiceError):
    code = "model_timeout"
    public_message = "The AI provider timed out before completing the analysis."


class VisionCapabilityUnavailableError(AgentServiceError):
    code = "vision_not_available"
    public_message = "Vision extraction is not available for the configured provider."
    retryable = False
