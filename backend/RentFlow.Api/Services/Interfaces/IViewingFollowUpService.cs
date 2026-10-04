using RentFlow.Api.DTOs.ViewingFollowUps;
using RentFlow.Api.Models;

namespace RentFlow.Api.Services.Interfaces;

public interface IViewingFollowUpService
{
    Task<ViewingFollowUpDto?> ClaimNextAsync(Guid tenantId, CancellationToken cancellationToken = default);
    Task<ViewingFollowUpResponseDto> RespondAsync(Guid tenantId, Guid followUpId, ViewingFollowUpDecision decision,
        CancellationToken cancellationToken = default);
}
