using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.PricingAnalysis;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

public sealed class PricingAnalysisOrchestrator(
    ApplicationDbContext dbContext,
    IPricingPropertyFactsTool propertyFactsTool,
    IPricingComparableRentalsTool comparableRentalsTool,
    IPricingEvidenceAssessmentTool evidenceAssessmentTool,
    IPricingAnalysisAgentClient agentClient,
    TimeProvider timeProvider,
    ILogger<PricingAnalysisOrchestrator> logger) : IPricingAnalysisOrchestrator
{
    private const string SafeStepErrorMessage = "The pricing analysis step failed unexpectedly.";
    private const string InsufficientRationale =
        "The supplied evidence is insufficient to support a numerical rental recommendation.";

    private static readonly string[] FixedPlan = PricingAnalysisResponseMapper.ExpectedSteps;

    public async Task<PricingAnalysisWorkflowResponseDto> StartAsync(
        Guid propertyId,
        CancellationToken cancellationToken = default)
    {
        if (propertyId == Guid.Empty)
        {
            throw new PricingAnalysisException(PricingAnalysisError.Validation, "A property ID is required.");
        }

        var propertyExists = await dbContext.Properties
            .AsNoTracking()
            .AnyAsync(property => property.Id == propertyId, cancellationToken);
        if (!propertyExists)
        {
            throw new PricingAnalysisException(PricingAnalysisError.NotFound, "The property was not found.");
        }

        var now = timeProvider.GetUtcNow();
        var workflow = new PricingAnalysisWorkflow
        {
            PropertyId = propertyId,
            Objective = PricingAnalysisResponseMapper.Objective,
            EvidencePolicyVersion = PricingAnalysisResponseMapper.PolicyVersion,
            Status = PricingAnalysisWorkflowStatus.Pending,
            CurrentStep = 0,
            CreatedAt = now,
            UpdatedAt = now,
            Steps = FixedPlan.Select((stepName, index) => new PricingAnalysisWorkflowStep
            {
                StepName = stepName,
                StepOrder = index + 1,
                Status = PricingAnalysisWorkflowStepStatus.Pending
            }).ToList()
        };

        dbContext.PricingAnalysisWorkflows.Add(workflow);
        await dbContext.SaveChangesAsync(cancellationToken);

        workflow.Status = PricingAnalysisWorkflowStatus.Running;
        workflow.StartedAt = timeProvider.GetUtcNow();
        workflow.UpdatedAt = workflow.StartedAt.Value;
        await dbContext.SaveChangesAsync(cancellationToken);

        var planResult = await ExecuteStepAsync(
            workflow,
            GetStep(workflow, 1),
            _ => Task.FromResult(FixedPlan),
            _ => "The fixed six-step pricing analysis plan was established.",
            result => JsonSerializer.Serialize(new { workflowPlanVersion = PricingAnalysisResponseMapper.PolicyVersion, expectedSteps = result }, PricingAnalysisResponseMapper.JsonOptions),
            cancellationToken);
        if (planResult is null)
        {
            return PricingAnalysisWorkflowResponseMapper.Map(workflow);
        }

        PricingEvidenceScope? scope = null;
        var loadedFacts = await ExecuteStepAsync(
            workflow,
            GetStep(workflow, 2),
            async token => scope = await propertyFactsTool.GetAsync(propertyId, token)
                ?? throw new InvalidOperationException("The subject property is no longer available."),
            facts => $"Approved subject facts captured: city={facts.SubjectFacts.City}; bedrooms={facts.SubjectFacts.Bedrooms}; bathrooms={facts.SubjectFacts.Bathrooms}; availability={facts.SubjectFacts.IsAvailable}.",
            _ => null,
            cancellationToken);
        if (loadedFacts is null)
        {
            return PricingAnalysisWorkflowResponseMapper.Map(workflow);
        }

        CollectedPricingEvidence? collected = null;
        collected = await ExecuteStepAsync(
            workflow,
            GetStep(workflow, 3),
            async token =>
            {
                var evidence = await comparableRentalsTool.GetAsync(scope!, token)
                    ?? throw new InvalidOperationException("The evidence tool returned no result.");
                var assessment = evidenceAssessmentTool.Assess(evidence)
                    ?? throw new InvalidOperationException("The evidence assessment returned no result.");
                workflow.EvidenceSufficiency = assessment.EvidenceSufficiency;
                workflow.Confidence = assessment.Confidence;
                return new CollectedPricingEvidence(evidence, assessment);
            },
            result => $"Eligible comparable evidence collected: {result.Evidence.Count}; sufficiency={result.Assessment.EvidenceSufficiency}; confidence={result.Assessment.Confidence}.",
            result => JsonSerializer.Serialize(new
            {
                comparables = result.Evidence.Select(ToEvidenceSummary).ToArray(),
                evidenceSufficiency = result.Assessment.EvidenceSufficiency,
                confidence = result.Assessment.Confidence,
                usableEvidenceCount = result.Assessment.UsableEvidenceCount,
                sourceCounts = result.Assessment.SourceCounts
            }, PricingAnalysisResponseMapper.JsonOptions),
            cancellationToken);
        if (collected is null)
        {
            return PricingAnalysisWorkflowResponseMapper.Map(workflow);
        }

        PricingAnalysisAgentRequest? request = null;
        PricingAnalysisAgentResponse? agentResponse = null;
        if (collected.Assessment.EvidenceSufficiency == PricingEvidenceSufficiency.INSUFFICIENT)
        {
            await SkipStepAsync(
                workflow,
                GetStep(workflow, 4),
                "Skipped because deterministic evidence sufficiency is INSUFFICIENT.",
                "No model or Python Agent call was made.",
                cancellationToken);
        }
        else
        {
            agentResponse = await ExecuteStepAsync(
                workflow,
                GetStep(workflow, 4),
                async token =>
                {
                    request = PricingAnalysisRequestMapper.Create(
                        workflow.Id,
                        workflow.PropertyId,
                        workflow.Objective,
                        loadedFacts.SubjectFacts,
                        collected.Evidence,
                        collected.Assessment,
                        workflow.EvidencePolicyVersion);
                    var response = await agentClient.AnalyzeAsync(request, token);
                    return response;
                },
                response => response.ModelDraft!.RecommendedMinRent is null
                    ? $"Validated Agent draft received; no numerical range; {response.ModelDraft.CitedEvidenceRefs!.Count} supplied evidence reference(s) cited."
                    : $"Validated Agent draft received with a numerical range and {response.ModelDraft.CitedEvidenceRefs!.Count} supplied evidence reference(s).",
                _ => null,
                cancellationToken);
            if (agentResponse is null)
            {
                return PricingAnalysisWorkflowResponseMapper.Map(workflow);
            }

        }

        var validated = await ExecuteStepAsync(
            workflow,
            GetStep(workflow, 5),
            _ =>
            {
                if (collected.Assessment.EvidenceSufficiency == PricingEvidenceSufficiency.INSUFFICIENT)
                {
                    if (agentResponse is not null
                        || collected.Assessment.NumericalRecommendationAllowed
                        || collected.Assessment.Confidence != PricingConfidence.LOW)
                    {
                        throw new InvalidOperationException("The insufficient evidence result is inconsistent.");
                    }

                    return Task.FromResult(new ValidatedPricingResult(null));
                }

                PricingAnalysisResponseMapper.ValidateResponse(request!, agentResponse);
                workflow.AgentVersion = agentResponse!.AgentVersion;
                return Task.FromResult(new ValidatedPricingResult(agentResponse));
            },
            result => result.AgentResponse is null
                ? "Deterministic no-recommendation result accepted; evidence sufficiency and low confidence retained."
                : "Agent response accepted; rent bounds and supplied evidence references validated; deterministic assessment retained.",
            _ => null,
            cancellationToken);
        if (validated is null)
        {
            return PricingAnalysisWorkflowResponseMapper.Map(workflow);
        }

        _ = await ExecuteStepAsync(
            workflow,
            GetStep(workflow, 6),
            _ =>
            {
                var finalResult = BuildFinalResult(
                    workflow,
                    loadedFacts.SubjectFacts,
                    collected,
                    validated.AgentResponse);
                workflow.ResultJson = JsonSerializer.Serialize(finalResult, PricingAnalysisResponseMapper.JsonOptions);
                workflow.Status = PricingAnalysisWorkflowStatus.Completed;
                workflow.ErrorMessage = null;
                workflow.CompletedAt = timeProvider.GetUtcNow();
                workflow.UpdatedAt = workflow.CompletedAt.Value;
                return Task.FromResult(finalResult);
            },
            _ => "Application-owned advisory pricing result produced.",
            value => JsonSerializer.Serialize(value, PricingAnalysisResponseMapper.JsonOptions),
            cancellationToken);

        return PricingAnalysisWorkflowResponseMapper.Map(workflow);
    }

    private async Task<T?> ExecuteStepAsync<T>(
        PricingAnalysisWorkflow workflow,
        PricingAnalysisWorkflowStep step,
        Func<CancellationToken, Task<T>> execute,
        Func<T, string> outputSummary,
        Func<T, string?> serializeSafeResult,
        CancellationToken cancellationToken)
        where T : class
    {
        var startedAt = timeProvider.GetUtcNow();
        step.Status = PricingAnalysisWorkflowStepStatus.Running;
        step.StartedAt = startedAt;
        step.CompletedAt = null;
        step.ErrorMessage = null;
        workflow.CurrentStep = step.StepOrder;
        workflow.UpdatedAt = startedAt;
        await dbContext.SaveChangesAsync(cancellationToken);

        try
        {
            var result = await execute(cancellationToken)
                ?? throw new InvalidOperationException("The pricing analysis step returned no result.");

            step.OutputSummary = Truncate(outputSummary(result), 4000);
            step.ResultJson = serializeSafeResult(result);
            step.ValidationSummary = "Step completed successfully.";
            step.Status = PricingAnalysisWorkflowStepStatus.Completed;
            step.CompletedAt = timeProvider.GetUtcNow();
            workflow.UpdatedAt = step.CompletedAt.Value;
            await dbContext.SaveChangesAsync(cancellationToken);
            return result;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            await MarkFailureAsync(workflow, step, "Pricing analysis was cancelled before completion.");
            throw;
        }
        catch (Exception exception)
        {
            logger.LogError(exception,
                "Pricing analysis workflow {WorkflowId} failed at step {StepOrder}.",
                workflow.Id,
                step.StepOrder);
            await MarkFailureAsync(workflow, step, GetSafeFailureMessage(exception));
            return null;
        }
    }

    private async Task SkipStepAsync(
        PricingAnalysisWorkflow workflow,
        PricingAnalysisWorkflowStep step,
        string outputSummary,
        string validationSummary,
        CancellationToken cancellationToken)
    {
        var now = timeProvider.GetUtcNow();
        step.Status = PricingAnalysisWorkflowStepStatus.Skipped;
        step.OutputSummary = outputSummary;
        step.ValidationSummary = validationSummary;
        step.StartedAt = null;
        step.CompletedAt = now;
        workflow.CurrentStep = step.StepOrder;
        workflow.UpdatedAt = now;
        await dbContext.SaveChangesAsync(cancellationToken);
    }

    private async Task MarkFailureAsync(
        PricingAnalysisWorkflow workflow,
        PricingAnalysisWorkflowStep step,
        string safeMessage)
    {
        var failedAt = timeProvider.GetUtcNow();
        step.Status = PricingAnalysisWorkflowStepStatus.Failed;
        step.ErrorMessage = safeMessage;
        step.OutputSummary = null;
        step.ValidationSummary = "Step failed before completion.";
        step.ResultJson = null;
        step.CompletedAt = failedAt;
        workflow.Status = PricingAnalysisWorkflowStatus.Failed;
        workflow.ErrorMessage = safeMessage;
        workflow.ResultJson = null;
        workflow.CompletedAt = failedAt;
        workflow.UpdatedAt = failedAt;
        await dbContext.SaveChangesAsync(CancellationToken.None);
    }

    private static PricingAnalysisWorkflowStep GetStep(PricingAnalysisWorkflow workflow, int order) =>
        workflow.Steps.Single(step => step.StepOrder == order);

    private static PricingAnalysisResultDto BuildFinalResult(
        PricingAnalysisWorkflow workflow,
        PricingPropertyFacts facts,
        CollectedPricingEvidence evidence,
        PricingAnalysisAgentResponse? agentResponse)
    {
        var assessment = evidence.Assessment;
        var draft = agentResponse?.ModelDraft;
        var insufficient = assessment.EvidenceSufficiency == PricingEvidenceSufficiency.INSUFFICIENT;
        var citedRefs = insufficient
            ? Array.Empty<string>()
            : draft!.CitedEvidenceRefs!.ToArray();
        var citedSet = new HashSet<string>(citedRefs, StringComparer.Ordinal);

        return new PricingAnalysisResultDto
        {
            WorkflowId = workflow.Id,
            PropertyId = workflow.PropertyId,
            CurrentRent = facts.MonthlyRent,
            EvidenceSufficiency = assessment.EvidenceSufficiency,
            Confidence = assessment.Confidence,
            UsableEvidenceCount = assessment.UsableEvidenceCount,
            SourceCounts = assessment.SourceCounts,
            RecommendedMinRent = insufficient ? null : draft!.RecommendedMinRent,
            RecommendedMaxRent = insufficient ? null : draft!.RecommendedMaxRent,
            CentralRecommendedRent = insufficient ? null : draft!.CentralRecommendedRent,
            Rationale = insufficient ? InsufficientRationale : draft!.Rationale!,
            CitedEvidenceRefs = citedRefs,
            CitedEvidence = evidence.Evidence
                .Where(item => citedSet.Contains(item.EvidenceRef))
                .Select(ToEvidenceSummary)
                .ToArray(),
            Limitations = (assessment.Limitations ?? Array.Empty<string>())
                .Concat(insufficient
                    ? ["No supported numerical recommendation can be made from the supplied evidence."]
                    : draft!.Limitations!)
                .Distinct(StringComparer.Ordinal)
                .ToArray(),
            Warnings = insufficient
                ? Array.Empty<string>()
                : draft!.Warnings!.ToArray(),
            AdvisoryOnly = true,
            EvidencePolicyVersion = workflow.EvidencePolicyVersion,
            AgentVersion = agentResponse?.AgentVersion
        };
    }

    private static PricingAnalysisEvidenceSummaryDto ToEvidenceSummary(PricingComparableEvidence evidence) => new()
    {
        EvidenceRef = evidence.EvidenceRef,
        SourceType = evidence.SourceType,
        MonthlyRent = evidence.MonthlyRent,
        City = evidence.City,
        Bedrooms = evidence.Bedrooms,
        Bathrooms = evidence.Bathrooms,
        SourceStatus = evidence.SourceStatus,
        EvidenceDate = evidence.EvidenceDate,
        EvidenceStrength = evidence.EvidenceStrength
    };

    private static string GetSafeFailureMessage(Exception exception) => exception switch
    {
        PricingAnalysisAgentClientException { Error: PricingAnalysisAgentClientError.Configuration } =>
            "The pricing analysis agent is not configured correctly.",
        PricingAnalysisAgentClientException { Error: PricingAnalysisAgentClientError.Timeout } =>
            "The pricing analysis agent timed out.",
        PricingAnalysisAgentClientException { Error: PricingAnalysisAgentClientError.ServiceUnavailable } =>
            "The pricing analysis agent is unavailable.",
        PricingAnalysisAgentClientException { Error: PricingAnalysisAgentClientError.UpstreamFailure } =>
            "The pricing analysis agent returned an unsuccessful response.",
        PricingAnalysisAgentClientException { Error: PricingAnalysisAgentClientError.MalformedResponse } =>
            "The pricing analysis agent returned an invalid response.",
        _ => SafeStepErrorMessage
    };

    private static string Truncate(string value, int maxLength) =>
        value.Length <= maxLength ? value : value[..maxLength];

    private sealed record CollectedPricingEvidence(
        IReadOnlyCollection<PricingComparableEvidence> Evidence,
        PricingDeterministicAssessment Assessment);

    private sealed record ValidatedPricingResult(PricingAnalysisAgentResponse? AgentResponse);
}
