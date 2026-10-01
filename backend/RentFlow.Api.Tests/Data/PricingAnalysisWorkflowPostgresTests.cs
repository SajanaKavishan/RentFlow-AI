using Microsoft.EntityFrameworkCore;
using Npgsql;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
using Xunit;

namespace RentFlow.Api.Tests.Data;

public sealed class PricingAnalysisWorkflowPostgresTests
{
    [PostgreSqlFact]
    public async Task MigrationEnforcesPricingStepOrderAndRestrictiveAuditRelationships()
    {
        var configuredConnectionString =
            Environment.GetEnvironmentVariable("RENTFLOW_TEST_POSTGRES_CONNECTION_STRING")!;
        var adminConnectionString = new NpgsqlConnectionStringBuilder(configuredConnectionString);
        if (adminConnectionString.Database?.StartsWith(
                "rentflow_component3_test",
                StringComparison.OrdinalIgnoreCase) != true)
        {
            throw new InvalidOperationException(
                "The PostgreSQL pricing workflow test only runs against a database named with the rentflow_component3_test prefix.");
        }

        var schema = $"pricing_workflow_{Guid.NewGuid():N}";
        await using (var adminConnection = new NpgsqlConnection(adminConnectionString.ConnectionString))
        {
            await adminConnection.OpenAsync();
            await using var createSchema = adminConnection.CreateCommand();
            createSchema.CommandText = $"CREATE SCHEMA \"{schema}\"";
            await createSchema.ExecuteNonQueryAsync();
        }

        var schemaConnectionString = new NpgsqlConnectionStringBuilder(adminConnectionString.ConnectionString)
        {
            SearchPath = schema
        }.ConnectionString;
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseNpgsql(schemaConnectionString)
            .Options;

        try
        {
            await using var context = new ApplicationDbContext(options);
            await context.Database.MigrateAsync();

            var landlord = CreateLandlord();
            var property = CreateProperty(landlord.Id);
            context.Users.Add(landlord);
            context.Properties.Add(property);
            var workflow = CreateWorkflow(property.Id, "Primary pricing audit");
            workflow.Steps.Add(new PricingAnalysisWorkflowStep
            {
                StepName = "plan",
                StepOrder = 1,
                Status = PricingAnalysisWorkflowStepStatus.Completed
            });
            context.PricingAnalysisWorkflows.Add(workflow);
            await context.SaveChangesAsync();

            var duplicateOrderException = await Assert.ThrowsAsync<PostgresException>(() =>
                context.Database.ExecuteSqlInterpolatedAsync($"""
                    INSERT INTO "PricingAnalysisWorkflowSteps"
                        ("Id", "WorkflowId", "StepName", "StepOrder", "Status")
                    VALUES
                        ({Guid.NewGuid()}, {workflow.Id}, {"duplicate-plan"}, {1}, {(int)PricingAnalysisWorkflowStepStatus.Pending})
                    """));
            Assert.Equal(PostgresErrorCodes.UniqueViolation, duplicateOrderException.SqlState);

            var otherWorkflow = CreateWorkflow(property.Id, "Second pricing audit");
            otherWorkflow.Steps.Add(new PricingAnalysisWorkflowStep
            {
                StepName = "plan",
                StepOrder = 1
            });
            context.PricingAnalysisWorkflows.Add(otherWorkflow);
            await context.SaveChangesAsync();

            var skippedStep = new PricingAnalysisWorkflowStep
            {
                WorkflowId = otherWorkflow.Id,
                StepName = "analyse_pricing_evidence",
                StepOrder = 4,
                Status = PricingAnalysisWorkflowStepStatus.Skipped
            };
            context.PricingAnalysisWorkflowSteps.Add(skippedStep);
            await context.SaveChangesAsync();

            var propertyDeleteException = await Assert.ThrowsAsync<PostgresException>(() =>
                context.Properties.Where(item => item.Id == property.Id).ExecuteDeleteAsync());
            AssertRestrictiveForeignKeyViolation(
                propertyDeleteException,
                "FK_PricingAnalysisWorkflows_Properties_PropertyId");

            var persistedWorkflow = await context.PricingAnalysisWorkflows
                .Include(item => item.Steps)
                .SingleAsync(item => item.Id == otherWorkflow.Id);
            Assert.Contains(persistedWorkflow.Steps, step => step.Status == PricingAnalysisWorkflowStepStatus.Skipped);

            var workflowDeleteException = await Assert.ThrowsAsync<PostgresException>(() =>
                context.PricingAnalysisWorkflows
                    .Where(item => item.Id == persistedWorkflow.Id)
                    .ExecuteDeleteAsync());
            AssertRestrictiveForeignKeyViolation(
                workflowDeleteException,
                "FK_PricingAnalysisWorkflowSteps_PricingAnalysisWorkflows_Workf~");
        }
        finally
        {
            await using var adminConnection = new NpgsqlConnection(adminConnectionString.ConnectionString);
            await adminConnection.OpenAsync();
            await using var dropSchema = adminConnection.CreateCommand();
            dropSchema.CommandText = $"DROP SCHEMA IF EXISTS \"{schema}\" CASCADE";
            await dropSchema.ExecuteNonQueryAsync();
        }
    }

    private static void AssertRestrictiveForeignKeyViolation(
        PostgresException exception,
        string expectedConstraint)
    {
        Assert.Contains(
            exception.SqlState,
            new[]
            {
                PostgresErrorCodes.RestrictViolation,
                PostgresErrorCodes.ForeignKeyViolation
            });
        Assert.Equal(expectedConstraint, exception.ConstraintName);
    }

    private static ApplicationUser CreateLandlord()
    {
        var id = Guid.NewGuid();
        return new ApplicationUser
        {
            Id = id,
            FullName = "Pricing Test Landlord",
            Email = $"{id:N}@example.test",
            NormalizedEmail = $"{id:N}@EXAMPLE.TEST".ToUpperInvariant(),
            PhoneNumber = "0000000000",
            PasswordHash = "test-only",
            Role = UserRole.Landlord,
            CreatedAt = DateTimeOffset.UtcNow
        };
    }

    private static Property CreateProperty(Guid landlordId) => new()
    {
        LandlordId = landlordId,
        Title = "Pricing persistence test property",
        Description = "A property used by the PostgreSQL persistence test.",
        Address = "1 Test Road",
        City = "Colombo",
        MonthlyRent = 1250m,
        Bedrooms = 2,
        Bathrooms = 1
    };

    private static PricingAnalysisWorkflow CreateWorkflow(Guid propertyId, string objective) => new()
    {
        PropertyId = propertyId,
        Objective = objective,
        EvidencePolicyVersion = "pricing-v1"
    };
}
