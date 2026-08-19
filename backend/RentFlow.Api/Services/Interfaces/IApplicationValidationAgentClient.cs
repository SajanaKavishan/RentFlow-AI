using RentFlow.Api.DTOs.ApplicationValidation;

namespace RentFlow.Api.Services.Interfaces;

public interface IApplicationValidationAgentClient
{
    Task<AgenticApplicationReviewResult> AnalyzeAsync(
        ApplicationValidationAgentRequest request,
        CancellationToken cancellationToken = default);
}
