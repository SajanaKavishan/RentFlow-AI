using RentFlow.Api.Models;
using RentFlow.Api.Services;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public class ApplicationDataValidationToolTests
{
    private static readonly DateTimeOffset Now = new(2026, 8, 19, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task ValidateAsync_ReturnsComplete_ForValidApplication()
    {
        var tool = new ApplicationDataValidationTool(new FixedTimeProvider(Now));

        var result = await tool.ValidateAsync(CreateValidApplication());

        Assert.True(result.IsValid);
        Assert.Equal(100m, result.CompletenessScore);
        Assert.Empty(result.MissingFields);
        Assert.Empty(result.Warnings);
    }

    [Fact]
    public async Task ValidateAsync_ReportsAllInvalidRequiredValues()
    {
        var tool = new ApplicationDataValidationTool(new FixedTimeProvider(Now));
        var application = new RentalApplication
        {
            TenantId = Guid.Empty,
            PropertyId = Guid.Empty,
            MoveInDate = DateOnly.FromDateTime(Now.UtcDateTime),
            MonthlyIncome = 0,
            Occupation = "   ",
            NumberOfOccupants = 0
        };

        var result = await tool.ValidateAsync(application);

        Assert.False(result.IsValid);
        Assert.Equal(0m, result.CompletenessScore);
        Assert.Equal(
            ["TenantId", "PropertyId", "MoveInDate", "MonthlyIncome", "Occupation", "NumberOfOccupants"],
            result.MissingFields);
        Assert.Equal(3, result.Warnings.Count);
    }

    [Fact]
    public async Task ValidateAsync_CalculatesCompletenessDeterministically()
    {
        var tool = new ApplicationDataValidationTool(new FixedTimeProvider(Now));
        var application = CreateValidApplication();
        application.Occupation = string.Empty;

        var first = await tool.ValidateAsync(application);
        var second = await tool.ValidateAsync(application);

        Assert.Equal(83.33m, first.CompletenessScore);
        Assert.Equal(first.CompletenessScore, second.CompletenessScore);
        Assert.Equal(["Occupation"], first.MissingFields);
    }

    private static RentalApplication CreateValidApplication()
    {
        return new RentalApplication
        {
            TenantId = Guid.NewGuid(),
            PropertyId = Guid.NewGuid(),
            MoveInDate = DateOnly.FromDateTime(Now.UtcDateTime).AddDays(30),
            MonthlyIncome = 5000m,
            Occupation = "Engineer",
            NumberOfOccupants = 2,
            Status = RentalApplicationStatus.Submitted
        };
    }
}

public class DocumentValidationToolTests
{
    [Fact]
    public async Task ValidateAsync_Passes_WhenBothRequiredDocumentsArePresent()
    {
        var result = await new DocumentValidationTool().ValidateAsync(
        [
            CreateDocument(ApplicationDocumentType.IdentityDocument),
            CreateDocument(ApplicationDocumentType.IncomeProof)
        ]);

        Assert.True(result.IsValid);
        Assert.Empty(result.MissingDocumentTypes);
        Assert.Contains("IdentityDocument", result.PresentDocumentTypes);
        Assert.Contains("IncomeProof", result.PresentDocumentTypes);
    }

    [Fact]
    public async Task ValidateAsync_Fails_WhenIdentityDocumentIsMissing()
    {
        var result = await new DocumentValidationTool().ValidateAsync(
            [CreateDocument(ApplicationDocumentType.IncomeProof)]);

        Assert.False(result.IsValid);
        Assert.Equal(["IdentityDocument"], result.MissingDocumentTypes);
    }

    [Fact]
    public async Task ValidateAsync_Fails_WhenIncomeProofIsMissing()
    {
        var result = await new DocumentValidationTool().ValidateAsync(
            [CreateDocument(ApplicationDocumentType.IdentityDocument)]);

        Assert.False(result.IsValid);
        Assert.Equal(["IncomeProof"], result.MissingDocumentTypes);
    }

    [Fact]
    public async Task ValidateAsync_MissingEmploymentLetterWarnsButDoesNotBlock()
    {
        var result = await new DocumentValidationTool().ValidateAsync(
        [
            CreateDocument(ApplicationDocumentType.IdentityDocument),
            CreateDocument(ApplicationDocumentType.IncomeProof),
            CreateDocument(ApplicationDocumentType.Other)
        ]);

        Assert.True(result.IsValid);
        Assert.Empty(result.MissingDocumentTypes);
        Assert.Single(result.Warnings);
        Assert.Contains("EmploymentLetter", result.Warnings.Single());
    }

    [Fact]
    public async Task ValidateAsync_OtherDocumentDoesNotSatisfyRequiredTypes()
    {
        var result = await new DocumentValidationTool().ValidateAsync(
            [CreateDocument(ApplicationDocumentType.Other)]);

        Assert.False(result.IsValid);
        Assert.Equal(["IdentityDocument", "IncomeProof"], result.MissingDocumentTypes);
    }

    internal static ApplicationDocument CreateDocument(ApplicationDocumentType type)
    {
        return new ApplicationDocument
        {
            ApplicationId = Guid.NewGuid(),
            DocumentType = type,
            OriginalFileName = "document.pdf",
            StorageKey = Guid.NewGuid().ToString("N"),
            ContentType = "application/pdf",
            FileSizeBytes = 100
        };
    }
}

public class DeterministicApplicationRuleToolTests
{
    private static readonly DateTimeOffset Now = new(2026, 8, 19, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task ValidateAsync_PassesAllRules_ForValidApplication()
    {
        var result = await CreateTool().ValidateAsync(CreateValidApplication(), CreateRequiredDocuments());

        Assert.True(result.Passed);
        Assert.Equal(5, result.PassedRules.Count);
        Assert.Empty(result.FailedRules);
    }

    [Fact]
    public async Task ValidateAsync_FailsPositiveIncomeRule_ForInvalidIncome()
    {
        var application = CreateValidApplication();
        application.MonthlyIncome = 0;

        var result = await CreateTool().ValidateAsync(application, CreateRequiredDocuments());

        Assert.False(result.Passed);
        Assert.Contains(DeterministicApplicationRuleTool.PositiveIncomeRule, result.FailedRules);
    }

    [Fact]
    public async Task ValidateAsync_FailsRequiredDocumentsRule_WhenRequiredMetadataIsMissing()
    {
        var result = await CreateTool().ValidateAsync(
            CreateValidApplication(),
            [DocumentValidationToolTests.CreateDocument(ApplicationDocumentType.Other)]);

        Assert.False(result.Passed);
        Assert.Contains(DeterministicApplicationRuleTool.RequiredDocumentsRule, result.FailedRules);
    }

    [Fact]
    public async Task ValidateAsync_FailsEligibleStatusRule_ForDraftApplication()
    {
        var application = CreateValidApplication();
        application.Status = RentalApplicationStatus.Draft;

        var result = await CreateTool().ValidateAsync(application, CreateRequiredDocuments());

        Assert.False(result.Passed);
        Assert.Contains(DeterministicApplicationRuleTool.EligibleStatusRule, result.FailedRules);
    }

    [Fact]
    public async Task ValidateAsync_FailsFutureMoveInDateRule_ForMoveInDateToday()
    {
        var application = CreateValidApplication();
        application.MoveInDate = DateOnly.FromDateTime(Now.UtcDateTime);

        var result = await CreateTool().ValidateAsync(application, CreateRequiredDocuments());

        Assert.False(result.Passed);
        Assert.Contains(DeterministicApplicationRuleTool.FutureMoveInDateRule, result.FailedRules);
    }

    [Fact]
    public async Task ValidateAsync_FailsApplicationExistsRule_WhenApplicationIsMissing()
    {
        var result = await CreateTool().ValidateAsync(null, CreateRequiredDocuments());

        Assert.False(result.Passed);
        Assert.Contains(DeterministicApplicationRuleTool.ApplicationExistsRule, result.FailedRules);
        Assert.Single(result.Warnings);
    }

    private static DeterministicApplicationRuleTool CreateTool() =>
        new(new FixedTimeProvider(Now));

    private static RentalApplication CreateValidApplication()
    {
        return new RentalApplication
        {
            TenantId = Guid.NewGuid(),
            PropertyId = Guid.NewGuid(),
            MoveInDate = DateOnly.FromDateTime(Now.UtcDateTime).AddDays(30),
            MonthlyIncome = 5000m,
            Occupation = "Engineer",
            NumberOfOccupants = 1,
            Status = RentalApplicationStatus.Submitted
        };
    }

    private static IReadOnlyCollection<ApplicationDocument> CreateRequiredDocuments() =>
    [
        DocumentValidationToolTests.CreateDocument(ApplicationDocumentType.IdentityDocument),
        DocumentValidationToolTests.CreateDocument(ApplicationDocumentType.IncomeProof)
    ];
}

internal sealed class FixedTimeProvider(DateTimeOffset utcNow) : TimeProvider
{
    public override DateTimeOffset GetUtcNow() => utcNow;
}
