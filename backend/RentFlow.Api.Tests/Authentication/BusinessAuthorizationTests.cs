using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
using Xunit;

namespace RentFlow.Api.Tests.Authentication;

public sealed class BusinessAuthorizationTests
{
    private static readonly Guid TenantA = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid TenantB = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");

    [Theory]
    [InlineData("/api/viewings")]
    [InlineData("/api/rental-applications")]
    [InlineData("/api/rental-applications/11111111-1111-1111-1111-111111111111/documents")]
    [InlineData("/api/rental-applications/11111111-1111-1111-1111-111111111111/validation-runs")]
    public async Task ProtectedBusinessEndpoints_WithoutJwt_ReturnUnauthorized(string route)
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();

        var response = await client.GetAsync(route);

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Viewing_TenantIdentityComesFromJwt_AndTenantIsIsolated()
    {
        using var factory = new AuthApiFactory();
        var otherViewing = await SeedViewingAsync(factory, TenantB);
        using var client = AuthorizedClient(factory, TenantA, UserRole.Tenant);

        var create = await client.PostAsJsonAsync(
            $"/api/viewings?tenantId={TenantB}",
            new
            {
                propertyId = Guid.NewGuid(),
                requestedDateTime = DateTimeOffset.UtcNow.AddDays(3),
                tenantMessage = "JWT owner"
            });
        var createdJson = await create.Content.ReadAsStringAsync();
        var list = await client.GetFromJsonAsync<JsonElement>("/api/viewings");
        var getOther = await client.GetAsync($"/api/viewings/{otherViewing.Id}");
        var cancelOther = await client.PatchAsync(
            $"/api/viewings/{otherViewing.Id}/cancel?tenantId={TenantA}", null);
        var approve = await client.PatchAsJsonAsync(
            $"/api/viewings/{otherViewing.Id}/approve", new { landlordResponse = "ok" });

        Assert.Equal(HttpStatusCode.Created, create.StatusCode);
        Assert.Equal(TenantA, JsonDocument.Parse(createdJson).RootElement.GetProperty("tenantId").GetGuid());
        Assert.Single(list.EnumerateArray());
        Assert.DoesNotContain(otherViewing.Id.ToString(), list.ToString(), StringComparison.OrdinalIgnoreCase);
        Assert.Equal(HttpStatusCode.NotFound, getOther.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, cancelOther.StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, approve.StatusCode);
    }

    [Fact]
    public async Task Viewing_ReviewerRolesCanDecide_AndMaintenanceIsDenied()
    {
        using var factory = new AuthApiFactory();
        var viewing = await SeedViewingAsync(factory, TenantA);
        using var landlord = AuthorizedClient(factory, Guid.NewGuid(), UserRole.Landlord);
        using var maintenance = AuthorizedClient(factory, Guid.NewGuid(), UserRole.MaintenanceTechnician);

        var approved = await landlord.PatchAsJsonAsync(
            $"/api/viewings/{viewing.Id}/approve", new { landlordResponse = "approved" });
        var denied = await maintenance.GetAsync($"/api/viewings/{viewing.Id}");

        Assert.Equal(HttpStatusCode.OK, approved.StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, denied.StatusCode);
    }

    [Fact]
    public async Task RentalApplication_TenantUsesJwtAndCanOnlyOperateOnOwnResources()
    {
        using var factory = new AuthApiFactory();
        var other = await SeedApplicationAsync(factory, TenantB, RentalApplicationStatus.Draft);
        using var client = AuthorizedClient(factory, TenantA, UserRole.Tenant);

        var create = await client.PostAsJsonAsync(
            $"/api/rental-applications?tenantId={TenantB}", ApplicationBody());
        var created = JsonDocument.Parse(await create.Content.ReadAsStringAsync()).RootElement;
        var id = created.GetProperty("id").GetGuid();
        var list = await client.GetFromJsonAsync<JsonElement>("/api/rental-applications");
        var getOther = await client.GetAsync($"/api/rental-applications/{other.Id}");
        var update = await client.PutAsJsonAsync(
            $"/api/rental-applications/{id}?tenantId={TenantB}", ApplicationBody());
        var submit = await client.PatchAsync($"/api/rental-applications/{id}/submit", null);
        var withdraw = await client.PatchAsync($"/api/rental-applications/{id}/withdraw", null);
        var review = await client.PatchAsync($"/api/rental-applications/{other.Id}/review", null);

        Assert.Equal(HttpStatusCode.Created, create.StatusCode);
        Assert.Equal(TenantA, created.GetProperty("tenantId").GetGuid());
        Assert.Single(list.EnumerateArray());
        Assert.Equal(HttpStatusCode.NotFound, getOther.StatusCode);
        Assert.Equal(HttpStatusCode.OK, update.StatusCode);
        Assert.Equal(HttpStatusCode.OK, submit.StatusCode);
        Assert.Equal(HttpStatusCode.OK, withdraw.StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, review.StatusCode);
    }

    [Theory]
    [InlineData(UserRole.Landlord)]
    [InlineData(UserRole.Admin)]
    public async Task RentalApplication_ReviewerRolesCanReview(UserRole role)
    {
        using var factory = new AuthApiFactory();
        var application = await SeedApplicationAsync(factory, TenantA, RentalApplicationStatus.Submitted);
        using var client = AuthorizedClient(factory, Guid.NewGuid(), role);

        var response = await client.PatchAsync(
            $"/api/rental-applications/{application.Id}/review", null);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task RentalApplication_MaintenanceCannotReview()
    {
        using var factory = new AuthApiFactory();
        var application = await SeedApplicationAsync(factory, TenantA, RentalApplicationStatus.Submitted);
        using var client = AuthorizedClient(
            factory, Guid.NewGuid(), UserRole.MaintenanceTechnician);

        var response = await client.PatchAsync(
            $"/api/rental-applications/{application.Id}/review", null);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task Documents_TenantCanUseOwnWorkflow_WithoutStorageKeyExposure()
    {
        using var factory = new AuthApiFactory();
        var application = await SeedApplicationAsync(factory, TenantA, RentalApplicationStatus.Draft);
        using var client = AuthorizedClient(factory, TenantA, UserRole.Tenant, allowAutoRedirect: false);
        using var form = new MultipartFormDataContent();
        var file = new ByteArrayContent([1, 2, 3]);
        file.Headers.ContentType = new MediaTypeHeaderValue("application/pdf");
        form.Add(file, "file", "income.pdf");
        form.Add(new StringContent("IncomeProof"), "documentType");

        var upload = await client.PostAsync(
            $"/api/rental-applications/{application.Id}/documents?tenantId={TenantB}", form);
        var uploadText = await upload.Content.ReadAsStringAsync();
        var documentId = JsonDocument.Parse(uploadText).RootElement.GetProperty("id").GetGuid();
        var list = await client.GetAsync($"/api/rental-applications/{application.Id}/documents");
        var metadata = await client.GetAsync($"/api/application-documents/{documentId}");
        var download = await client.GetAsync($"/api/application-documents/{documentId}/download");
        var delete = await client.DeleteAsync($"/api/application-documents/{documentId}");

        Assert.Equal(HttpStatusCode.Created, upload.StatusCode);
        Assert.DoesNotContain("storageKey", uploadText, StringComparison.OrdinalIgnoreCase);
        Assert.Equal(HttpStatusCode.OK, list.StatusCode);
        Assert.Equal(HttpStatusCode.OK, metadata.StatusCode);
        Assert.Equal(HttpStatusCode.Redirect, download.StatusCode);
        Assert.Equal(1, factory.FileStorage.DownloadUrlCalls);
        Assert.Equal(HttpStatusCode.NoContent, delete.StatusCode);
    }

    [Fact]
    public async Task Documents_ChangingGuidCannotSignAnotherTenantsPrivateFile()
    {
        using var factory = new AuthApiFactory();
        var application = await SeedApplicationAsync(factory, TenantB, RentalApplicationStatus.Draft);
        var document = await SeedDocumentAsync(factory, application.Id);
        using var client = AuthorizedClient(factory, TenantA, UserRole.Tenant, allowAutoRedirect: false);

        var metadata = await client.GetAsync($"/api/application-documents/{document.Id}");
        var download = await client.GetAsync($"/api/application-documents/{document.Id}/download");
        var delete = await client.DeleteAsync($"/api/application-documents/{document.Id}");

        Assert.Equal(HttpStatusCode.NotFound, metadata.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, download.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, delete.StatusCode);
        Assert.Equal(0, factory.FileStorage.DownloadUrlCalls);
    }

    [Fact]
    public async Task Documents_ReviewersCanRead_MaintenanceCannot()
    {
        using var factory = new AuthApiFactory();
        var application = await SeedApplicationAsync(factory, TenantA, RentalApplicationStatus.Submitted);
        var document = await SeedDocumentAsync(factory, application.Id);
        using var landlord = AuthorizedClient(factory, Guid.NewGuid(), UserRole.Landlord, false);
        using var maintenance = AuthorizedClient(factory, Guid.NewGuid(), UserRole.MaintenanceTechnician, false);

        var reviewDownload = await landlord.GetAsync($"/api/application-documents/{document.Id}/download");
        var denied = await maintenance.GetAsync($"/api/application-documents/{document.Id}");

        Assert.Equal(HttpStatusCode.Redirect, reviewDownload.StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, denied.StatusCode);
    }

    [Fact]
    public async Task Validation_IsRejectedBeforeOrchestratorForUnauthorizedRoles()
    {
        using var factory = new AuthApiFactory();
        var applicationId = Guid.NewGuid();
        using var tenant = AuthorizedClient(factory, TenantA, UserRole.Tenant);
        using var maintenance = AuthorizedClient(factory, Guid.NewGuid(), UserRole.MaintenanceTechnician);
        using var landlord = AuthorizedClient(factory, Guid.NewGuid(), UserRole.Landlord);
        using var anonymous = factory.CreateHttpsClient();

        var anonymousResponse = await anonymous.PostAsync(
            $"/api/rental-applications/{applicationId}/validation-runs", null);
        var tenantResponse = await tenant.PostAsync(
            $"/api/rental-applications/{applicationId}/validation-runs", null);
        var maintenanceResponse = await maintenance.PostAsync(
            $"/api/rental-applications/{applicationId}/validation-runs", null);
        Assert.Equal(0, factory.ValidationOrchestrator.Calls);
        var landlordResponse = await landlord.PostAsync(
            $"/api/rental-applications/{applicationId}/validation-runs", null);

        Assert.Equal(HttpStatusCode.Unauthorized, anonymousResponse.StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, tenantResponse.StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, maintenanceResponse.StatusCode);
        Assert.Equal(HttpStatusCode.Created, landlordResponse.StatusCode);
        Assert.Equal(1, factory.ValidationOrchestrator.Calls);
    }

    [Fact]
    public async Task Validation_AdminCanRunAndReviewerCanViewHistory()
    {
        using var factory = new AuthApiFactory();
        var application = await SeedApplicationAsync(
            factory, TenantA, RentalApplicationStatus.Submitted);
        var workflow = await SeedValidationWorkflowAsync(factory, application.Id);
        using var admin = AuthorizedClient(factory, Guid.NewGuid(), UserRole.Admin);
        using var landlord = AuthorizedClient(factory, Guid.NewGuid(), UserRole.Landlord);
        using var tenant = AuthorizedClient(factory, TenantA, UserRole.Tenant);

        var started = await admin.PostAsync(
            $"/api/rental-applications/{application.Id}/validation-runs", null);
        var byId = await landlord.GetAsync(
            $"/api/application-validation-workflows/{workflow.Id}");
        var tenantHistory = await tenant.GetAsync(
            $"/api/rental-applications/{application.Id}/validation-runs");

        Assert.Equal(HttpStatusCode.Created, started.StatusCode);
        Assert.Equal(HttpStatusCode.OK, byId.StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, tenantHistory.StatusCode);
    }

    [Theory]
    [InlineData("not-a-guid", "Tenant")]
    [InlineData("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", null)]
    [InlineData("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "Owner")]
    public async Task TokenWithMissingOrMalformedIdentity_FailsAuthenticationSafely(
        string subject,
        string? role)
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue(
            "Bearer", CreateToken(subject, role));

        var response = await client.GetAsync("/api/viewings");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    private static HttpClient AuthorizedClient(
        AuthApiFactory factory,
        Guid userId,
        UserRole role,
        bool allowAutoRedirect = true)
    {
        var client = factory.CreateHttpsClient(allowAutoRedirect);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue(
            "Bearer", CreateToken(userId.ToString(), role.ToString()));
        return client;
    }

    private static string CreateToken(string subject, string? role)
    {
        var credentials = new SigningCredentials(
            new SymmetricSecurityKey(Encoding.UTF8.GetBytes(
                "test-only-signing-key-that-is-at-least-32-bytes-long")),
            SecurityAlgorithms.HmacSha256);
        var claims = new List<Claim> { new(JwtRegisteredClaimNames.Sub, subject) };
        if (role is not null)
        {
            claims.Add(new Claim("role", role));
        }

        var token = new JwtSecurityToken(
            issuer: "RentFlow.Api.Tests",
            audience: "RentFlow.TestClients",
            claims: claims,
            expires: DateTime.UtcNow.AddMinutes(10),
            signingCredentials: credentials);
        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    private static object ApplicationBody() => new
    {
        propertyId = Guid.NewGuid(),
        moveInDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)),
        monthlyIncome = 250000m,
        occupation = "Engineer",
        numberOfOccupants = 2,
        tenantNote = "Test"
    };

    private static async Task<ViewingRequest> SeedViewingAsync(AuthApiFactory factory, Guid tenantId)
    {
        var viewing = new ViewingRequest
        {
            Id = Guid.NewGuid(), TenantId = tenantId, PropertyId = Guid.NewGuid(),
            RequestedDateTime = DateTimeOffset.UtcNow.AddDays(5),
            Status = ViewingStatus.Pending, CreatedAt = DateTimeOffset.UtcNow
        };
        await SeedAsync(factory, context => context.ViewingRequests.Add(viewing));
        return viewing;
    }

    private static async Task<RentalApplication> SeedApplicationAsync(
        AuthApiFactory factory, Guid tenantId, RentalApplicationStatus status)
    {
        var application = new RentalApplication
        {
            Id = Guid.NewGuid(), TenantId = tenantId, PropertyId = Guid.NewGuid(),
            MoveInDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)),
            MonthlyIncome = 250000m, Occupation = "Engineer", NumberOfOccupants = 1,
            Status = status, CreatedAt = DateTimeOffset.UtcNow
        };
        await SeedAsync(factory, context => context.RentalApplications.Add(application));
        return application;
    }

    private static async Task<ApplicationDocument> SeedDocumentAsync(
        AuthApiFactory factory, Guid applicationId)
    {
        var document = new ApplicationDocument
        {
            Id = Guid.NewGuid(), ApplicationId = applicationId,
            DocumentType = ApplicationDocumentType.IdentityDocument,
            OriginalFileName = "identity.pdf", StorageKey = "private/secret-key.pdf",
            ContentType = "application/pdf", FileSizeBytes = 3,
            UploadedAt = DateTimeOffset.UtcNow
        };
        await SeedAsync(factory, context => context.ApplicationDocuments.Add(document));
        return document;
    }

    private static async Task<ApplicationValidationWorkflow> SeedValidationWorkflowAsync(
        AuthApiFactory factory, Guid applicationId)
    {
        var workflow = new ApplicationValidationWorkflow
        {
            Id = Guid.NewGuid(), ApplicationId = applicationId,
            Objective = "Validate application for landlord review.",
            Status = ApplicationValidationWorkflowStatus.AwaitingHumanReview,
            RequiresHumanApproval = true, CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        await SeedAsync(factory, context => context.ApplicationValidationWorkflows.Add(workflow));
        return workflow;
    }

    private static async Task SeedAsync(
        AuthApiFactory factory,
        Action<ApplicationDbContext> seed)
    {
        using var scope = factory.Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        seed(context);
        await context.SaveChangesAsync();
    }
}
