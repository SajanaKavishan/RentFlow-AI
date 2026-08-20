using RentFlow.Api.DTOs.ApplicationValidation;

namespace RentFlow.Api.Services.Interfaces;

public interface IApplicationValidationOrchestrator
{
    Task<ApplicationValidationWorkflowResponseDto> StartValidationAsync(
        Guid applicationId,
        CancellationToken cancellationToken = default);
}
