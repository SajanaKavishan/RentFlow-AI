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
        Assert.Equal(4, result.CurrentStep);
        Assert.Equal([1, 2, 3, 4], result.Steps.Select(step => step.StepOrder));
        Assert.Equal(
            [
                "Application Data Validator",
                "Document Validation Agent",
                "Deterministic Rule Checker",
                "Agentic Application Review"
            ],
            result.Steps.Select(step => step.AgentName));
        Assert.All(result.Steps, step =>
        {
            Assert.Equal(ApplicationValidationStepStatus.Completed, step.Status);
            Assert.NotNull(step.StartedAt);
            Assert.NotNull(step.CompletedAt);
            Assert.NotNull(step.Result);
            Assert.Equal(System.Text.Json.JsonValueKind.Object, step.Result!.Value.ValueKind);
        });
        Assert.NotNull(result.Summary);
        Assert.True(result.Summary!.ApplicationData.IsValid);
        Assert.True(result.Summary.Documents.IsValid);
        Assert.True(result.Summary.DeterministicRules.Passed);
        Assert.NotNull(result.Summary.AgenticReview);
        Assert.True(result.Summary.AgenticReview!.RequiresHumanApproval);

        var stored = await context.ApplicationValidationWorkflows
            .Include(workflow => workflow.Steps)
            .SingleAsync();
        Assert.Equal(4, stored.Steps.Count);
        Assert.Contains("agentVersion", stored.Steps.Single(step => step.StepOrder == 4).ResultJson);
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
        Assert.Equal([1, 2, 3, 4], queriedFirst!.Steps.Select(step => step.StepOrder));
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
        Assert.Equal(ApplicationValidationStepStatus.Pending, result.Steps.ElementAt(3).Status);
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
        Assert.Equal(RentalApplicationStatus.UnderReview, application.Status);
    }

    [Fact]
    public async Task StartValidationAsync_SendsOnlyCurrentApplicationDocumentsWithoutStorageDetails()
    {
        await using var context = CreateContext();
        var application = AddApplication(context);
        AddRequiredDocuments(context, application.Id);
        var otherApplication = AddApplication(context);
        AddDocument(context, otherApplication.Id, ApplicationDocumentType.IncomeProof);
        await context.SaveChangesAsync();
        var agentClient = new FakeAgentClient();

        await CreateOrchestrator(context, agentClient: agentClient)
            .StartValidationAsync(application.Id);

        var request = Assert.IsType<ApplicationValidationAgentRequest>(agentClient.LastRequest);
        Assert.Equal(application.Id, request.ApplicationId);
        Assert.Equal(2, request.DocumentMetadata.Count);
        Assert.Equal(2, request.SupportingDocuments.Count);
        Assert.All(request.SupportingDocuments, document =>
        {
            Assert.Contains(document.DocumentId, request.DocumentMetadata.Select(item => item.DocumentId));
            Assert.False(string.IsNullOrWhiteSpace(document.ContentBase64));
            Assert.Equal(100, document.SizeBytes);
        });
        Assert.All(request.DocumentMetadata, document =>
        {
            Assert.EndsWith(".pdf", document.FileName);
            Assert.True(document.IsRequired);
        });
        var requestJson = System.Text.Json.JsonSerializer.Serialize(request);
        Assert.DoesNotContain("storageKey", requestJson, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("signedUrl", requestJson, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("publicUrl", requestJson, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task StartValidationAsync_PersistsOnlySafeStructuredDocumentFindings()
    {
        await using var context = CreateContext();
        var application = AddApplication(context);
        AddRequiredDocuments(context, application.Id);
        await context.SaveChangesAsync();
        var documents = await context.ApplicationDocuments
            .Where(document => document.ApplicationId == application.Id)
            .ToListAsync();
        var identity = documents.Single(document =>
            document.DocumentType == ApplicationDocumentType.IdentityDocument);
        var income = documents.Single(document =>
            document.DocumentType == ApplicationDocumentType.IncomeProof);
        var agentClient = new FakeAgentClient
        {
            Result = new AgenticApplicationReviewResult
            {
                Recommendation = "Manual review required",
                Summary = "Structured findings require landlord review.",
                KeyFindings = ["Income evidence was analyzed conservatively."],
                Warnings = ["One document could not be read reliably."],
                RequiresHumanApproval = true,
                AgentVersion = "phase-b-test",
                SupportingDocumentVerification =
                [
                    new SupportingDocumentVerificationResult
                    {
                        DocumentId = income.Id,
                        DocumentType = "IncomeProof",
                        Readable = true,
                        DetectedDocumentCategory = "IncomeProof",
                        ExtractedFacts = new SupportingDocumentExtractedFacts
                        {
                            ApplicantName = "Ada Lovelace",
                            IncomeAmount = 5000m,
                            PayPeriod = "monthly",
                            EmployerName = "ACME"
                        },
                        ConfidenceLabel = "High",
                        ExtractionMethod = "PdfText",
                        RequiresManualReview = false
                    },
                    new SupportingDocumentVerificationResult
                    {
                        DocumentId = identity.Id,
                        DocumentType = "IdentityDocument",
                        Readable = false,
                        DetectedDocumentCategory = "Unknown",
                        ExtractedFacts = new SupportingDocumentExtractedFacts(),
                        Warnings = ["Document text could not be extracted reliably."],
                        ConfidenceLabel = "Unknown",
                        ExtractionMethod = "None",
                        RequiresManualReview = true
                    }
                ],
                CrossDocumentConsistency = new CrossDocumentConsistencyResult
                {
                    MatchedFacts =
                    [
                        new CrossDocumentConsistencyFinding
                        {
                            Comparison = "monthly_income_vs_income_amount",
                            Message = "Monthly income matched within configured tolerance."
                        }
                    ],
                    Warnings = ["Identity text requires manual review."],
                    RequiresManualReview = true
                }
            }
        };

        var result = await CreateOrchestrator(context, agentClient: agentClient)
            .StartValidationAsync(application.Id);

        Assert.Equal(ApplicationValidationWorkflowStatus.AwaitingHumanReview, result.Status);
        Assert.True(result.RequiresHumanApproval);
        var responseReview = Assert.IsType<AgenticApplicationReviewResult>(
            result.Summary!.AgenticReview);
        var responseIncome = Assert.Single(responseReview.SupportingDocumentVerification,
            verification => verification.DocumentType == "IncomeProof");
        Assert.True(responseIncome.Readable);
        Assert.Equal("IncomeProof", responseIncome.DetectedDocumentCategory);
        Assert.Equal("PdfText", responseIncome.ExtractionMethod);
        Assert.Equal("Ada Lovelace", responseIncome.ExtractedFacts.ApplicantName);
        Assert.Equal(5000m, responseIncome.ExtractedFacts.IncomeAmount);
        Assert.Single(responseReview.CrossDocumentConsistency.MatchedFacts);
        var responseJson = System.Text.Json.JsonSerializer.Serialize(result);
        Assert.DoesNotContain("contentBase64", responseJson, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("extractedText", responseJson, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("storageKey", responseJson, StringComparison.OrdinalIgnoreCase);
        context.ChangeTracker.Clear();
        var stored = await context.ApplicationValidationWorkflows
            .Include(workflow => workflow.Steps)
            .SingleAsync();
        var persisted = stored.Steps.Single(step => step.StepOrder == 4).ResultJson!;
        Assert.Contains("supportingDocumentVerification", persisted, StringComparison.Ordinal);
        Assert.Contains("extractionMethod", persisted, StringComparison.Ordinal);
        Assert.Contains("crossDocumentConsistency", persisted, StringComparison.Ordinal);
        Assert.DoesNotContain("contentBase64", persisted, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("extractedText", persisted, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("storageKey", persisted, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("signedUrl", persisted, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(identity.StorageKey, persisted, StringComparison.Ordinal);
        Assert.DoesNotContain(income.StorageKey, persisted, StringComparison.Ordinal);
    }

    [Fact]
    public async Task StartValidationAsync_AgentFailurePreservesDeterministicResultsAndPersistsSafeFailure()
    {
        await using var context = CreateContext();
        var application = AddApplication(context);
        AddRequiredDocuments(context, application.Id);
        await context.SaveChangesAsync();
        var agentClient = new FakeAgentClient
        {
            Exception = new ApplicationValidationAgentClientException(
                ApplicationValidationAgentClientError.ServiceUnavailable,
                "Sensitive upstream detail")
        };

        var result = await CreateOrchestrator(context, agentClient: agentClient)
            .StartValidationAsync(application.Id);

        Assert.Equal(ApplicationValidationWorkflowStatus.Failed, result.Status);
        Assert.Equal("Ready for landlord review", result.Recommendation);
        Assert.True(result.RequiresHumanApproval);
        Assert.All(result.Steps.Take(3), step =>
            Assert.Equal(ApplicationValidationStepStatus.Completed, step.Status));
        var aiStep = result.Steps.Single(step => step.StepOrder == 4);
        Assert.Equal(ApplicationValidationStepStatus.Failed, aiStep.Status);
        Assert.Equal("The validation step failed unexpectedly.", aiStep.ErrorMessage);
        Assert.DoesNotContain("Sensitive", aiStep.ErrorMessage, StringComparison.OrdinalIgnoreCase);

        context.ChangeTracker.Clear();
        var stored = await context.ApplicationValidationWorkflows
            .Include(workflow => workflow.Steps)
            .SingleAsync();
        Assert.Equal(3, stored.Steps.Count(step =>
            step.Status == ApplicationValidationStepStatus.Completed));
        Assert.Equal(ApplicationValidationStepStatus.Failed,
            stored.Steps.Single(step => step.StepOrder == 4).Status);
    }

    [Fact]
    public async Task StartValidationAsync_DocumentPreparationFailureDoesNotFailWorkflow()
    {
        await using var context = CreateContext();
        var application = AddApplication(context);
        AddRequiredDocuments(context, application.Id);
        await context.SaveChangesAsync();
        var agentClient = new FakeAgentClient();

        var result = await CreateOrchestrator(
                context,
                agentClient: agentClient,
                contentService: new ExcludingDocumentContentService())
            .StartValidationAsync(application.Id);

        Assert.Equal(ApplicationValidationWorkflowStatus.AwaitingHumanReview, result.Status);
        Assert.Empty(agentClient.LastRequest!.SupportingDocuments);
        Assert.Contains(agentClient.LastRequest.DeterministicFindings,
            finding => finding.Code == "document.analysis.retrieval_failed");
        Assert.Contains("The document content could not be prepared for analysis.",
            result.Summary!.AgenticReview!.Warnings);
    }

    [Fact]
    public async Task StartValidationAsync_ConflictingAiRecommendationCannotOverrideDeterministicFinding()
    {
        await using var context = CreateContext();
        var application = AddApplication(context);
        AddDocument(context, application.Id, ApplicationDocumentType.IdentityDocument);
        await context.SaveChangesAsync();
        var agentClient = new FakeAgentClient
        {
            Result = CreateAgentResult("Ready for landlord review")
        };

        var result = await CreateOrchestrator(context, agentClient: agentClient)
            .StartValidationAsync(application.Id);

        Assert.Equal("Request missing documents", result.Recommendation);
        Assert.Equal(ApplicationValidationWorkflowStatus.AwaitingHumanReview, result.Status);
        Assert.True(result.RequiresHumanApproval);
        Assert.Equal(RentalApplicationStatus.Submitted, application.Status);
        var aiResult = result.Summary!.AgenticReview!;
        Assert.Equal("Request missing documents", aiResult.Recommendation);
        Assert.Contains(
            "AI recommendation differed from deterministic validation; deterministic findings retained.",
            aiResult.Warnings);
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
        IDeterministicApplicationRuleTool? ruleTool = null,
        IApplicationValidationAgentClient? agentClient = null,
        IApplicationDocumentContentService? contentService = null)
    {
        var timeProvider = new FixedTimeProvider(Now);
        return new ApplicationValidationOrchestrator(
            context,
            new ApplicationDataValidationTool(timeProvider),
            documentTool ?? new DocumentValidationTool(),
            ruleTool ?? new DeterministicApplicationRuleTool(timeProvider),
            agentClient ?? new FakeAgentClient(),
            contentService ?? new FakeApplicationDocumentContentService(),
            timeProvider,
            NullLogger<ApplicationValidationOrchestrator>.Instance);
    }

    private sealed class ExcludingDocumentContentService : IApplicationDocumentContentService
    {
        public Task<SupportingDocumentPreparationResult> PrepareForAnalysisAsync(
            Guid applicationId,
            ApplicationDocument authorizedDocument,
            CancellationToken cancellationToken = default) =>
            Task.FromResult(new SupportingDocumentPreparationResult
            {
                DocumentId = authorizedDocument.Id,
                WarningCode = "retrieval_failed",
                Warning = "The document content could not be prepared for analysis."
            });
    }

    private sealed class FakeApplicationDocumentContentService
        : IApplicationDocumentContentService
    {
        public Task<SupportingDocumentPreparationResult> PrepareForAnalysisAsync(
            Guid applicationId,
            ApplicationDocument authorizedDocument,
            CancellationToken cancellationToken = default)
        {
            Assert.Equal(applicationId, authorizedDocument.ApplicationId);
            return Task.FromResult(new SupportingDocumentPreparationResult
            {
                DocumentId = authorizedDocument.Id,
                Input = new SupportingDocumentAnalysisInput
                {
                    DocumentId = authorizedDocument.Id,
                    DocumentType = authorizedDocument.DocumentType,
                    OriginalFileName = authorizedDocument.OriginalFileName,
                    ContentType = authorizedDocument.ContentType,
                    SizeBytes = authorizedDocument.FileSizeBytes,
                    ContentBase64 = Convert.ToBase64String(new byte[authorizedDocument.FileSizeBytes])
                }
            });
        }
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

    private static AgenticApplicationReviewResult CreateAgentResult(
        string recommendation = "Ready for landlord review")
    {
        return new AgenticApplicationReviewResult
        {
            Recommendation = recommendation,
            Summary = "Structured findings are ready for a landlord's manual review.",
            KeyFindings = ["Deterministic findings were retained."],
            Warnings = [],
            RequiresHumanApproval = true,
            AgentVersion = "test-agent"
        };
    }

    private sealed class FakeAgentClient : IApplicationValidationAgentClient
    {
        public ApplicationValidationAgentRequest? LastRequest { get; private set; }

        public AgenticApplicationReviewResult Result { get; init; } = CreateAgentResult();

        public Exception? Exception { get; init; }

        public Task<AgenticApplicationReviewResult> AnalyzeAsync(
            ApplicationValidationAgentRequest request,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            LastRequest = request;
            return Exception is null
                ? Task.FromResult(Result)
                : Task.FromException<AgenticApplicationReviewResult>(Exception);
        }
    }
}
