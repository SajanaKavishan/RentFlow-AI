namespace RentFlow.Api.DTOs.ApplicationValidation;

public class ApplicationValidationAgentRequest
{
    public Guid WorkflowId { get; init; }

    public Guid ApplicationId { get; init; }

    public string Objective { get; init; } = string.Empty;

    public ApplicationValidationAgentApplicationData ApplicationData { get; init; } = new();

    public IReadOnlyCollection<ApplicationValidationAgentDocumentMetadata> DocumentMetadata { get; init; }
        = Array.Empty<ApplicationValidationAgentDocumentMetadata>();

    public IReadOnlyCollection<ApplicationValidationAgentDeterministicFinding> DeterministicFindings { get; init; }
        = Array.Empty<ApplicationValidationAgentDeterministicFinding>();
}

public class ApplicationValidationAgentApplicationData
{
    public DateOnly MoveInDate { get; init; }

    public decimal MonthlyIncome { get; init; }

    public string Occupation { get; init; } = string.Empty;

    public int NumberOfOccupants { get; init; }
}

public class ApplicationValidationAgentDocumentMetadata
{
    public Guid DocumentId { get; init; }

    public string DocumentType { get; init; } = string.Empty;

    public string? FileName { get; init; }

    public bool IsRequired { get; init; }
}

public class ApplicationValidationAgentDeterministicFinding
{
    public string Code { get; init; } = string.Empty;

    public string Severity { get; init; } = string.Empty;

    public string Message { get; init; } = string.Empty;

    public string? Field { get; init; }
}

public class ApplicationValidationAgentResponse
{
    public Guid WorkflowId { get; init; }

    public Guid ApplicationId { get; init; }

    public AgenticApplicationReviewResult Result { get; init; } = new();

    public ApplicationValidationAgentExecutionMetadata ExecutionMetadata { get; init; } = new();
}

public class AgenticApplicationReviewResult
{
    public string Recommendation { get; init; } = string.Empty;

    public string Summary { get; init; } = string.Empty;

    public IReadOnlyCollection<string> KeyFindings { get; init; } = Array.Empty<string>();

    public IReadOnlyCollection<string> Warnings { get; init; } = Array.Empty<string>();

    public bool RequiresHumanApproval { get; init; }

    public string AgentVersion { get; init; } = string.Empty;
}

public class ApplicationValidationAgentExecutionMetadata
{
    public IReadOnlyCollection<string> ExecutedSteps { get; init; } = Array.Empty<string>();
}
