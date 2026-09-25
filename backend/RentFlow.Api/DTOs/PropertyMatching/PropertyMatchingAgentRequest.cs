namespace RentFlow.Api.DTOs.PropertyMatching;

public sealed class PropertyMatchingAgentRequest
{
    public PropertyMatchingRequest Preferences { get; set; } = new();

    public List<PropertyMatchCandidate> Candidates { get; set; } = [];
}