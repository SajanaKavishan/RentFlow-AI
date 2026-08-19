using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.ApplicationValidation;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

public class ApplicationValidationQueryService(ApplicationDbContext dbContext)
    : IApplicationValidationQueryService
{
    public async Task<ApplicationValidationWorkflowResponseDto?> GetByIdAsync(
        Guid workflowId,
        CancellationToken cancellationToken = default)
    {
        var workflow = await dbContext.ApplicationValidationWorkflows
            .AsNoTracking()
            .Include(item => item.Steps)
            .SingleOrDefaultAsync(item => item.Id == workflowId, cancellationToken);

        return workflow is null ? null : ApplicationValidationResponseMapper.Map(workflow);
    }

    public async Task<IReadOnlyList<ApplicationValidationWorkflowResponseDto>> GetByApplicationAsync(
        Guid applicationId,
        CancellationToken cancellationToken = default)
    {
        var workflows = await dbContext.ApplicationValidationWorkflows
            .AsNoTracking()
            .Include(item => item.Steps)
            .Where(item => item.ApplicationId == applicationId)
            .OrderByDescending(item => item.CreatedAt)
            .ToListAsync(cancellationToken);

        return workflows.Select(ApplicationValidationResponseMapper.Map).ToArray();
    }
}
