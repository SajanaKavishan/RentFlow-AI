using RentFlow.Api.DTOs.ApplicationValidation;

namespace RentFlow.Api.Services.Interfaces;

public interface IApplicationValidationQueryService
{
    Task<ApplicationValidationWorkflowResponseDto?> GetByIdAsync(
        Guid workflowId,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<ApplicationValidationWorkflowResponseDto>> GetByApplicationAsync(
        Guid applicationId,
        CancellationToken cancellationToken = default);
}
