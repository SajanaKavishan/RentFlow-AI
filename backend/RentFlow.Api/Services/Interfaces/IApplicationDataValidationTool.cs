using RentFlow.Api.DTOs.ApplicationValidation;
using RentFlow.Api.Models;

namespace RentFlow.Api.Services.Interfaces;

public interface IApplicationDataValidationTool
{
    Task<ApplicationDataValidationResult> ValidateAsync(
        RentalApplication application,
        CancellationToken cancellationToken = default);
}
