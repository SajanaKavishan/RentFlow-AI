using RentFlow.Api.DTOs.ApplicationValidation;
using RentFlow.Api.Models;

namespace RentFlow.Api.Services.Interfaces;

public interface IDeterministicApplicationRuleTool
{
    Task<DeterministicRuleValidationResult> ValidateAsync(
        RentalApplication? application,
        IReadOnlyCollection<ApplicationDocument> documents,
        CancellationToken cancellationToken = default);
}
