namespace RentFlow.Api.DTOs.PropertyMatching;

public sealed class PropertyMatchingResponse
{
    public List<PropertyMatchCandidate> Matches { get; set; } = [];

    public string Summary { get; set; } = string.Empty;

    public bool ExplanationAvailable { get; set; }
}
