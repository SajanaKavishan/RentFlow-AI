namespace RentFlow.Api.DTOs.PropertyMatching;

public sealed class PropertyMatchingAgentResponse
{
    public PropertyMatchingAgentResult Result { get; set; } = new();

    public PropertyMatchingExecutionMetadata ExecutionMetadata { get; set; } = new();
}

public sealed class PropertyMatchingAgentResult
{
    public List<PropertyMatchingAgentMatch> Matches { get; set; } = [];

    public string Summary { get; set; } = string.Empty;

    public string AgentVersion { get; set; } = string.Empty;
}

public sealed class PropertyMatchingAgentMatch
{
    public Guid PropertyId { get; set; }

    public int MatchScore { get; set; }

    public List<string> Reasons { get; set; } = [];
}

public sealed class PropertyMatchingExecutionMetadata
{
    public List<string> ExecutedSteps { get; set; } = [];
}