using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.PricingAnalysis;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

public sealed class PricingAnalysisQueryService(ApplicationDbContext dbContext)
    : IPricingAnalysisQueryService
{
    public async Task<PricingAnalysisWorkflowResponseDto?> GetByIdAsync(
        Guid workflowId,
        CancellationToken cancellationToken = default)
    {
        if (workflowId == Guid.Empty)
        {
            throw new PricingAnalysisException(
                PricingAnalysisError.Validation,
                "A pricing analysis workflow ID is required.");
        }

        var workflow = await dbContext.PricingAnalysisWorkflows
            .AsNoTracking()
            .Include(item => item.Steps)
            .SingleOrDefaultAsync(item => item.Id == workflowId, cancellationToken);

        return workflow is null ? null : PricingAnalysisWorkflowResponseMapper.Map(workflow);
    }

    public async Task<IReadOnlyList<PricingAnalysisWorkflowResponseDto>> GetByPropertyAsync(
        Guid propertyId,
        CancellationToken cancellationToken = default)
    {
        if (propertyId == Guid.Empty)
        {
            throw new PricingAnalysisException(
                PricingAnalysisError.Validation,
                "A property ID is required.");
        }

        var workflows = await dbContext.PricingAnalysisWorkflows
            .AsNoTracking()
            .Include(item => item.Steps)
            .Where(item => item.PropertyId == propertyId)
            .OrderByDescending(item => item.CreatedAt)
            .ToListAsync(cancellationToken);

        return workflows.Select(PricingAnalysisWorkflowResponseMapper.Map).ToArray();
    }
}
