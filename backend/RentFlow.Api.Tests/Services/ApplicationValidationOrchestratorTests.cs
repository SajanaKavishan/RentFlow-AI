using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.ApplicationValidation;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public class ApplicationValidationOrchestratorTests
{
    private static readonly DateTimeOffset Now = new(2026, 8, 19, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task StartValidationAsync_CreatesOrderedStepsAndAwaitsHumanReview()
    {
        await using var context = CreateContext();
        var application = AddApplication(context);
        AddRequiredDocuments(context, application.Id);
        await context.SaveChangesAsync();

        var result = await CreateOrchestrator(context).StartValidationAsync(application.Id);

        Assert.Equal(ApplicationValidationWorkflowStatus.AwaitingHumanReview, result.Status);
        Assert.True(result.RequiresHumanApproval);
        Assert.Equal(100m, result.CompletenessScore);
        Assert.Equal("Ready for landlord review", result.Recommendation);
        Assert.Equal(3, result.CurrentStep);
        Assert.Equal([1, 2, 3], result.Steps.Select(step => step.StepOrder));
        Assert.Equal(
            ["Application Data Validator", "Document Validation Agent", "Deterministic Rule Checker"],
            result.Steps.Select(step => step.AgentName));
        Assert.All(result.Steps, step =>
        {
            Assert.Equal(ApplicationValidationStepStatus.Completed, step.Status);
            Assert.NotNull(step.StartedAt);
            Assert.NotNull(step.CompletedAt);
            Assert.False(string.IsNullOrWhiteSpace(step.ResultJson));
            using var json = JsonDocument.Parse(step.ResultJson!);
            Assert.Equal(JsonValueKind.Object, json.RootElement.ValueKind);
        });
        Assert.NotNull(result.Summary);
        Assert.True(result.Summary!.ApplicationData.IsValid);
        Assert.True(result.Summary.Documents.IsValid);
        Assert.True(result.Summary.DeterministicRules.Passed);

        var stored = await context.ApplicationValidationWorkflows
            .Include(workflow => workflow.Steps)
            .SingleAsync();
        Assert.Equal(3, stored.Steps.Count);
    }

    [Fact]
    public async Task StartValidationAsync_PreservesPreviousRunsAndQueryReturnsOrderedSteps()
    {
        await using var context = CreateContext();
        var application = AddApplication(context);
        AddRequiredDocuments(context, application.Id);
        await context.SaveChangesAsync();
        var orchestrator = CreateOrchestrator(context);

        var first = await orchestrator.StartValidationAsync(application.Id);
        var second = await orchestrator.StartValidationAsync(application.Id);
        var queryService = new ApplicationValidationQueryService(context);
        var workflows = await queryService.GetByApplicationAsync(application.Id);
        var queriedFirst = await queryService.GetByIdAsync(first.Id);

        Assert.NotEqual(first.Id, second.Id);
        Assert.Equal(2, workflows.Count);
        Assert.NotNull(queriedFirst);
        Assert.Equal([1, 2, 3], queriedFirst!.Steps.Select(step => step.StepOrder));
    }

    [Fact]
    public async Task StartValidationAsync_StopsAfterUnexpectedFailureAndPreservesSafeAuditState()
    {
        await using var context = CreateContext();
        var application = AddApplication(context);
        AddRequiredDocuments(context, application.Id);
        await context.SaveChangesAsync();
        var ruleTool = new CountingRuleTool();
        var orchestrator = CreateOrchestrator(
            context,
            documentTool: new ThrowingDocumentTool(),
            ruleTool: ruleTool);

        var result = await orchestrator.StartValidationAsync(application.Id);

        Assert.Equal(ApplicationValidationWorkflowStatus.Failed, result.Status);
        Assert.True(result.RequiresHumanApproval);
        Assert.Equal(ApplicationValidationStepStatus.Completed, result.Steps.ElementAt(0).Status);
        Assert.Equal(ApplicationValidationStepStatus.Failed, result.Steps.ElementAt(1).Status);
        Assert.Equal(ApplicationValidationStepStatus.Pending, result.Steps.ElementAt(2).Status);
        Assert.Equal("The validation step failed unexpectedly.", result.Steps.ElementAt(1).ErrorMessage);
        Assert.DoesNotContain("sensitive", result.Steps.ElementAt(1).ErrorMessage!, StringComparison.OrdinalIgnoreCase);
        Assert.Equal(0, ruleTool.CallCount);
        Assert.Null(result.Summary);

        context.ChangeTracker.Clear();
        var stored = await context.ApplicationValidationWorkflows
            .Include(workflow => workflow.Steps)
            .SingleAsync();
        Assert.Equal(ApplicationValidationWorkflowStatus.Failed, stored.Status);
        Assert.Equal(
            ApplicationValidationStepStatus.Failed,
            stored.Steps.Single(step => step.StepOrder == 2).Status);
    }

    [Fact]
    public async Task StartValidationAsync_RecommendsMissingDocuments_WhenRequiredDocumentIsAbsent()
    {
        await using var context = CreateContext();
        var application = AddApplication(context);
        AddDocument(context, application.Id, ApplicationDocumentType.IdentityDocument);
        await context.SaveChangesAsync();

        var result = await CreateOrchestrator(context).StartValidationAsync(application.Id);

        Assert.Equal("Request missing documents", result.Recommendation);
        Assert.Equal(ApplicationValidationWorkflowStatus.AwaitingHumanReview, result.Status);
        Assert.Contains("IncomeProof", result.Summary!.Documents.MissingDocumentTypes);
    }

    [Fact]
    public async Task StartValidationAsync_RecommendsMissingInformation_WhenApplicationDataIsInvalid()
    {
        await using var context = CreateContext();
        var application = AddApplication(context);
        application.Occupation = "   ";
        AddRequiredDocuments(context, application.Id);
        await context.SaveChangesAsync();

        var result = await CreateOrchestrator(context).StartValidationAsync(application.Id);

        Assert.Equal("Request missing information", result.Recommendation);
        Assert.Equal(83.33m, result.CompletenessScore);
        Assert.Contains("Occupation", result.Summary!.ApplicationData.MissingFields);
    }

    [Fact]
    public async Task StartValidationAsync_RecommendsLandlordReview_ForFullyValidFindings()
    {
        await using var context = CreateContext();
        var application = AddApplication(context, RentalApplicationStatus.UnderReview);
        AddRequiredDocuments(context, application.Id);
        await context.SaveChangesAsync();

        var result = await CreateOrchestrator(context).StartValidationAsync(application.Id);

        Assert.Equal("Ready for landlord review", result.Recommendation);
        Assert.DoesNotContain("Approved", result.Recommendation, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Rejected", result.Recommendation, StringComparison.OrdinalIgnoreCase);
        Assert.True(result.RequiresHumanApproval);
    }

    [Fact]
    public async Task StartValidationAsync_RejectsIneligibleStatusWithoutCreatingWorkflow()
    {
        await using var context = CreateContext();
        var application = AddApplication(context, RentalApplicationStatus.Draft);
        await context.SaveChangesAsync();

        var exception = await Assert.ThrowsAsync<ApplicationValidationException>(() =>
            CreateOrchestrator(context).StartValidationAsync(application.Id));

        Assert.Equal(ApplicationValidationError.Conflict, exception.Error);
        Assert.Empty(context.ApplicationValidationWorkflows);
    }

    private static ApplicationValidationOrchestrator CreateOrchestrator(
        ApplicationDbContext context,
        IDocumentValidationTool? documentTool = null,
        IDeterministicApplicationRuleTool? ruleTool = null)
    {
        var timeProvider = new FixedTimeProvider(Now);
        return new ApplicationValidationOrchestrator(
            context,
            new ApplicationDataValidationTool(timeProvider),
            documentTool ?? new DocumentValidationTool(),
            ruleTool ?? new DeterministicApplicationRuleTool(timeProvider),
            timeProvider,
            NullLogger<ApplicationValidationOrchestrator>.Instance);
    }

    private static ApplicationDbContext CreateContext()
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase($"ApplicationValidationOrchestratorTests-{Guid.NewGuid()}")
            .Options;
        return new ApplicationDbContext(options);
    }

    private static RentalApplication AddApplication(
        ApplicationDbContext context,
        RentalApplicationStatus status = RentalApplicationStatus.Submitted)
    {
        var application = new RentalApplication
        {
            TenantId = Guid.NewGuid(),
            PropertyId = Guid.NewGuid(),
            MoveInDate = DateOnly.FromDateTime(Now.UtcDateTime).AddDays(30),
            MonthlyIncome = 5000m,
            Occupation = "Engineer",
            NumberOfOccupants = 2,
            Status = status,
            CreatedAt = Now,
            SubmittedAt = Now.AddDays(-1)
        };
        context.RentalApplications.Add(application);
        return application;
    }

    private static void AddRequiredDocuments(ApplicationDbContext context, Guid applicationId)
    {
        AddDocument(context, applicationId, ApplicationDocumentType.IdentityDocument);
        AddDocument(context, applicationId, ApplicationDocumentType.IncomeProof);
    }

    private static void AddDocument(
        ApplicationDbContext context,
        Guid applicationId,
        ApplicationDocumentType documentType)
    {
        context.ApplicationDocuments.Add(new ApplicationDocument
        {
            ApplicationId = applicationId,
            DocumentType = documentType,
            OriginalFileName = "document.pdf",
            StorageKey = Guid.NewGuid().ToString("N"),
            ContentType = "application/pdf",
            FileSizeBytes = 100,
            UploadedAt = Now
        });
    }

    private sealed class ThrowingDocumentTool : IDocumentValidationTool
    {
        public Task<DocumentValidationResult> ValidateAsync(
            IReadOnlyCollection<ApplicationDocument> documents,
            CancellationToken cancellationToken = default)
        {
            throw new InvalidOperationException("Sensitive infrastructure detail.");
        }
    }

    private sealed class CountingRuleTool : IDeterministicApplicationRuleTool
    {
        public int CallCount { get; private set; }

        public Task<DeterministicRuleValidationResult> ValidateAsync(
            RentalApplication? application,
            IReadOnlyCollection<ApplicationDocument> documents,
            CancellationToken cancellationToken = default)
        {
            CallCount++;
            return Task.FromResult(new DeterministicRuleValidationResult { Passed = true });
        }
    }
}
