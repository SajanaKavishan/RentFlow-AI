using RentFlow.Api.DTOs.PropertyMatching;
using RentFlow.Api.Models;

namespace RentFlow.Api.Services.Interfaces;

public interface IPropertyMatchingRuleTool
{
    Task<List<PropertyMatchCandidate>> ScoreAsync(
        IEnumerable<Property> properties,
        PropertyMatchingRequest preferences,
        CancellationToken cancellationToken = default);
}