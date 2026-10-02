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
using RentFlow.Api.DTOs.LeaseAgreements;
using RentFlow.Api.DTOs.Payments;
using RentFlow.Api.DTOs.RentalOffers;
using RentFlow.Api.DTOs.RentSchedules;
using RentFlow.Api.Models;
using Xunit;

namespace RentFlow.Api.Tests.Authentication;

public sealed class BusinessAuthorizationTests
{
    private static readonly Guid TenantA = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid TenantB = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static readonly Guid LandlordA = Guid.Parse("11111111-1111-1111-1111-111111111111");
    private static readonly Guid LandlordB = Guid.Parse("22222222-2222-2222-2222-222222222222");

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
        var property = await SeedPropertyAsync(factory, LandlordA);
        var otherViewing = await SeedViewingAsync(factory, TenantB);
        using var client = AuthorizedClient(factory, TenantA, UserRole.Tenant);

        var create = await client.PostAsJsonAsync(
            $"/api/viewings?tenantId={TenantB}",
            new
            {
                propertyId = property.Id,
                requestedDateTime = new DateTimeOffset(DateTime.UtcNow.Date.AddDays(3).AddHours(3.5)),
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
        var property = await SeedPropertyAsync(factory, LandlordA);
        var viewing = await SeedViewingAsync(factory, TenantA, property.Id);
        using var landlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord);
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
        var property = await SeedPropertyAsync(factory, LandlordA);
        var other = await SeedApplicationAsync(factory, TenantB, RentalApplicationStatus.Draft);
        using var client = AuthorizedClient(factory, TenantA, UserRole.Tenant);

        var create = await client.PostAsJsonAsync(
            $"/api/rental-applications?tenantId={TenantB}", ApplicationBody(property.Id));
        var created = JsonDocument.Parse(await create.Content.ReadAsStringAsync()).RootElement;
        var id = created.GetProperty("id").GetGuid();
        var list = await client.GetFromJsonAsync<JsonElement>("/api/rental-applications");
        var getOther = await client.GetAsync($"/api/rental-applications/{other.Id}");
        var update = await client.PutAsJsonAsync(
            $"/api/rental-applications/{id}?tenantId={TenantB}", ApplicationBody(property.Id));
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
        var property = await SeedPropertyAsync(factory, LandlordA);
        var application = await SeedApplicationAsync(
            factory, TenantA, RentalApplicationStatus.Submitted, property.Id);
        using var client = AuthorizedClient(
            factory, role == UserRole.Landlord ? LandlordA : Guid.NewGuid(), role);

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
        var property = await SeedPropertyAsync(factory, LandlordA);
        var application = await SeedApplicationAsync(
            factory, TenantA, RentalApplicationStatus.Submitted, property.Id);
        var document = await SeedDocumentAsync(factory, application.Id);
        using var landlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord, false);
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
        var property = await SeedPropertyAsync(factory, LandlordA);
        var application = await SeedApplicationAsync(
            factory, TenantA, RentalApplicationStatus.Submitted, property.Id);
        var applicationId = application.Id;
        using var tenant = AuthorizedClient(factory, TenantA, UserRole.Tenant);
        using var maintenance = AuthorizedClient(factory, Guid.NewGuid(), UserRole.MaintenanceTechnician);
        using var landlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord);
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
        var property = await SeedPropertyAsync(factory, LandlordA);
        var application = await SeedApplicationAsync(
            factory, TenantA, RentalApplicationStatus.Submitted, property.Id);
        var workflow = await SeedValidationWorkflowAsync(factory, application.Id);
        using var admin = AuthorizedClient(factory, Guid.NewGuid(), UserRole.Admin);
        using var landlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord);
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

    [Fact]
    public async Task Viewing_CrossRoleRoundTrip_PersistsLandlordDecisionForTenantRefresh()
    {
        using var factory = new AuthApiFactory();
        var propertyId = (await SeedPropertyAsync(factory, LandlordA)).Id;
        using var tenant = AuthorizedClient(factory, TenantA, UserRole.Tenant);
        using var landlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord);

        var create = await tenant.PostAsJsonAsync("/api/viewings", new
        {
            propertyId,
            requestedDateTime = new DateTimeOffset(DateTime.UtcNow.Date.AddDays(4).AddHours(3.5)),
            tenantMessage = "Please confirm accessibility."
        });
        var created = JsonDocument.Parse(await create.Content.ReadAsStringAsync()).RootElement;
        var viewingId = created.GetProperty("id").GetGuid();

        var landlordQueue = await landlord.GetFromJsonAsync<JsonElement>(
            $"/api/viewings/property/{propertyId}");
        var decision = await landlord.PatchAsJsonAsync(
            $"/api/viewings/{viewingId}/approve",
            new { landlordResponse = "Accessibility confirmed." });
        var tenantRefresh = await tenant.GetFromJsonAsync<JsonElement>("/api/viewings");
        var refreshed = tenantRefresh.EnumerateArray().Single();

        Assert.Equal(HttpStatusCode.Created, create.StatusCode);
        Assert.Single(landlordQueue.EnumerateArray());
        Assert.Equal(TenantA, landlordQueue.EnumerateArray().Single()
            .GetProperty("tenantId").GetGuid());
        Assert.Equal(HttpStatusCode.OK, decision.StatusCode);
        Assert.Equal((int)ViewingStatus.Approved, refreshed.GetProperty("status").GetInt32());
        Assert.Equal("Accessibility confirmed.",
            refreshed.GetProperty("landlordResponse").GetString());
    }

    [Fact]
    public async Task RentalApplication_CrossRoleRoundTrip_PreservesDocumentsAndResubmissionRules()
    {
        using var factory = new AuthApiFactory();
        var propertyId = (await SeedPropertyAsync(factory, LandlordA)).Id;
        using var tenant = AuthorizedClient(factory, TenantA, UserRole.Tenant, false);
        using var landlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord, false);

        var create = await tenant.PostAsJsonAsync("/api/rental-applications", new
        {
            propertyId,
            moveInDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)),
            monthlyIncome = 250000m,
            occupation = "Engineer",
            numberOfOccupants = 2,
            tenantNote = "Cross-role workflow"
        });
        var created = JsonDocument.Parse(await create.Content.ReadAsStringAsync()).RootElement;
        var applicationId = created.GetProperty("id").GetGuid();

        using var identityForm = DocumentForm("IdentityDocument", "identity.pdf");
        using var incomeForm = DocumentForm("IncomeProof", "income.pdf");
        var identityUpload = await tenant.PostAsync(
            $"/api/rental-applications/{applicationId}/documents", identityForm);
        var incomeUpload = await tenant.PostAsync(
            $"/api/rental-applications/{applicationId}/documents", incomeForm);
        var submit = await tenant.PatchAsync(
            $"/api/rental-applications/{applicationId}/submit", null);

        var landlordQueue = await landlord.GetFromJsonAsync<JsonElement>(
            $"/api/rental-applications/property/{propertyId}");
        var documents = await landlord.GetFromJsonAsync<JsonElement>(
            $"/api/rental-applications/{applicationId}/documents");
        var validation = await landlord.PostAsync(
            $"/api/rental-applications/{applicationId}/validation-runs", null);
        var validationBody = JsonDocument.Parse(
            await validation.Content.ReadAsStringAsync()).RootElement;

        var changes = await landlord.PatchAsJsonAsync(
            $"/api/rental-applications/{applicationId}/request-changes",
            new { landlordResponse = "Add current employment details." });
        var tenantRefresh = await tenant.GetFromJsonAsync<JsonElement>(
            "/api/rental-applications");
        var changedApplication = tenantRefresh.EnumerateArray().Single();

        var update = await tenant.PutAsJsonAsync(
            $"/api/rental-applications/{applicationId}", new
            {
                moveInDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(35)),
                monthlyIncome = 260000m,
                occupation = "Senior Engineer",
                numberOfOccupants = 2,
                tenantNote = "Employment details updated"
            });
        using var employmentForm = DocumentForm(
            "EmploymentLetter", "employment.pdf");
        var employmentUpload = await tenant.PostAsync(
            $"/api/rental-applications/{applicationId}/documents", employmentForm);
        var resubmit = await tenant.PatchAsync(
            $"/api/rental-applications/{applicationId}/submit", null);
        var landlordRefresh = await landlord.GetFromJsonAsync<JsonElement>(
            $"/api/rental-applications/property/{propertyId}");

        Assert.Equal(HttpStatusCode.Created, create.StatusCode);
        Assert.Equal(HttpStatusCode.Created, identityUpload.StatusCode);
        Assert.Equal(HttpStatusCode.Created, incomeUpload.StatusCode);
        Assert.Equal(HttpStatusCode.OK, submit.StatusCode);
        Assert.Single(landlordQueue.EnumerateArray());
        Assert.Equal(2, documents.GetArrayLength());
        Assert.Equal(HttpStatusCode.Created, validation.StatusCode);
        Assert.Equal((int)ApplicationValidationWorkflowStatus.AwaitingHumanReview,
            validationBody.GetProperty("status").GetInt32());
        Assert.True(validationBody.GetProperty("requiresHumanApproval").GetBoolean());
        Assert.Equal(HttpStatusCode.OK, changes.StatusCode);
        Assert.Equal((int)RentalApplicationStatus.ChangesRequested,
            changedApplication.GetProperty("status").GetInt32());
        Assert.Equal("Add current employment details.",
            changedApplication.GetProperty("landlordResponse").GetString());
        Assert.Equal(HttpStatusCode.OK, update.StatusCode);
        Assert.Equal(HttpStatusCode.Created, employmentUpload.StatusCode);
        Assert.Equal(HttpStatusCode.OK, resubmit.StatusCode);
        Assert.Equal((int)RentalApplicationStatus.Submitted,
            landlordRefresh.EnumerateArray().Single().GetProperty("status").GetInt32());
    }

    [Fact]
    public async Task RentSchedule_GetByIdAndLease_EnforceTenantAndPropertyOwnership()
    {
        using var factory = new AuthApiFactory();
        var property = await SeedPropertyAsync(factory, LandlordA);
        var lease = new LeaseAgreement
        {
            RentalOfferId = Guid.NewGuid(),
            TenantId = TenantA,
            PropertyId = property.Id,
            MonthlyRent = 85000m,
            SecurityDeposit = 170000m,
            StartDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)),
            EndDate = DateOnly.FromDateTime(DateTime.UtcNow.AddMonths(12))
        };
        var scheduleItem = new RentScheduleItem
        {
            LeaseAgreementId = lease.Id,
            DueDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(-2)),
            Amount = lease.MonthlyRent
        };
        await SeedAsync(factory, context =>
        {
            context.LeaseAgreements.Add(lease);
            context.RentScheduleItems.Add(scheduleItem);
        });

        using var tenant = AuthorizedClient(factory, TenantA, UserRole.Tenant);
        using var otherTenant = AuthorizedClient(factory, TenantB, UserRole.Tenant);
        using var landlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord);
        using var otherLandlord = AuthorizedClient(factory, LandlordB, UserRole.Landlord);
        using var admin = AuthorizedClient(factory, Guid.NewGuid(), UserRole.Admin);
        var itemRoute = $"/api/rent-schedules/{scheduleItem.Id}";
        var leaseRoute = $"/api/rent-schedules/lease/{lease.Id}";

        using var otherTenantItem = await otherTenant.GetAsync(itemRoute);
        using var otherTenantLease = await otherTenant.GetAsync(leaseRoute);
        Assert.Equal(HttpStatusCode.NotFound, otherTenantItem.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, otherTenantLease.StatusCode);

        using (var scope = factory.Services.CreateScope())
        {
            var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            var unchangedSchedule = await context.RentScheduleItems
                .AsNoTracking()
                .SingleAsync(item => item.Id == scheduleItem.Id);
            Assert.Equal(RentScheduleStatus.Pending, unchangedSchedule.Status);
        }

        using var tenantItem = await tenant.GetAsync(itemRoute);
        using var landlordItem = await landlord.GetAsync(itemRoute);
        using var otherLandlordItem = await otherLandlord.GetAsync(itemRoute);
        using var adminItem = await admin.GetAsync(itemRoute);
        using var missingItem = await tenant.GetAsync($"/api/rent-schedules/{Guid.NewGuid()}");

        Assert.Equal(HttpStatusCode.OK, tenantItem.StatusCode);
        var tenantItemResult = await tenantItem.Content
            .ReadFromJsonAsync<RentScheduleItemResponseDto>();
        Assert.Equal(scheduleItem.Id, tenantItemResult?.Id);
        Assert.Equal(RentScheduleStatus.Overdue, tenantItemResult?.Status);
        Assert.Equal(HttpStatusCode.OK, landlordItem.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, otherLandlordItem.StatusCode);
        Assert.Equal(HttpStatusCode.OK, adminItem.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, missingItem.StatusCode);

        using var tenantLease = await tenant.GetAsync(leaseRoute);
        using var landlordLease = await landlord.GetAsync(leaseRoute);
        using var otherLandlordLease = await otherLandlord.GetAsync(leaseRoute);
        using var adminLease = await admin.GetAsync(leaseRoute);
        using var missingLease = await tenant.GetAsync(
            $"/api/rent-schedules/lease/{Guid.NewGuid()}");

        Assert.Equal(HttpStatusCode.OK, tenantLease.StatusCode);
        Assert.Equal(scheduleItem.Id,
            (await tenantLease.Content.ReadFromJsonAsync<List<RentScheduleItemResponseDto>>())?.Single().Id);
        Assert.Equal(HttpStatusCode.OK, landlordLease.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, otherLandlordLease.StatusCode);
        Assert.Equal(HttpStatusCode.OK, adminLease.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, missingLease.StatusCode);
    }

    [Fact]
    public async Task RentSchedule_OutstandingSummaries_EnforceAccessBeforeRefresh()
    {
        using var factory = new AuthApiFactory();
        var ownedProperty = await SeedPropertyAsync(factory, LandlordA);
        var otherProperty = await SeedPropertyAsync(factory, LandlordB);
        var ownedLease = CreateLeaseAgreement(ownedProperty.Id, LeaseAgreementStatus.Active);
        var otherLease = CreateLeaseAgreement(otherProperty.Id, LeaseAgreementStatus.Active);
        otherLease.TenantId = TenantB;
        var ownedItem = new RentScheduleItem
        {
            LeaseAgreementId = ownedLease.Id,
            DueDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(-2)),
            Amount = 100.25m,
            Status = RentScheduleStatus.Pending
        };
        var otherItem = new RentScheduleItem
        {
            LeaseAgreementId = otherLease.Id,
            DueDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(-2)),
            Amount = 200.50m,
            Status = RentScheduleStatus.Pending
        };
        await SeedAsync(factory, context =>
        {
            context.LeaseAgreements.AddRange(ownedLease, otherLease);
            context.RentScheduleItems.AddRange(ownedItem, otherItem);
        });

        using var tenant = AuthorizedClient(factory, TenantA, UserRole.Tenant);
        using var landlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord);
        using var otherLandlord = AuthorizedClient(factory, LandlordB, UserRole.Landlord);
        using var admin = AuthorizedClient(factory, Guid.NewGuid(), UserRole.Admin);

        using var inaccessibleTenantLease = await tenant.GetAsync(
            $"/api/rent-schedules/lease/{otherLease.Id}/outstanding");
        Assert.Equal(HttpStatusCode.NotFound, inaccessibleTenantLease.StatusCode);

        using (var scope = factory.Services.CreateScope())
        {
            var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            var unchangedItem = await context.RentScheduleItems
                .AsNoTracking()
                .SingleAsync(item => item.Id == otherItem.Id);
            Assert.Equal(RentScheduleStatus.Pending, unchangedItem.Status);
        }

        using var tenantMine = await tenant.GetAsync("/api/rent-schedules/outstanding/mine");
        using var tenantOwnedLease = await tenant.GetAsync(
            $"/api/rent-schedules/lease/{ownedLease.Id}/outstanding");
        using var landlordOwnedLease = await landlord.GetAsync(
            $"/api/rent-schedules/lease/{ownedLease.Id}/outstanding");
        using var differentLandlord = await otherLandlord.GetAsync(
            $"/api/rent-schedules/lease/{ownedLease.Id}/outstanding");
        using var adminOwnedLease = await admin.GetAsync(
            $"/api/rent-schedules/lease/{ownedLease.Id}/outstanding");

        Assert.Equal(HttpStatusCode.OK, tenantMine.StatusCode);
        Assert.Equal(HttpStatusCode.OK, tenantOwnedLease.StatusCode);
        Assert.Equal(HttpStatusCode.OK, landlordOwnedLease.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, differentLandlord.StatusCode);
        Assert.Equal(HttpStatusCode.OK, adminOwnedLease.StatusCode);

        var tenantSummary = await tenantMine.Content
            .ReadFromJsonAsync<RentScheduleOutstandingSummaryDto>();
        Assert.Equal(100.25m, tenantSummary?.TotalOutstanding);
        Assert.Single(tenantSummary!.Items);
        Assert.Equal(ownedItem.Id, tenantSummary.Items[0].Id);

        using (var scope = factory.Services.CreateScope())
        {
            var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            var stillUnchanged = await context.RentScheduleItems
                .AsNoTracking()
                .SingleAsync(item => item.Id == otherItem.Id);
            Assert.Equal(RentScheduleStatus.Pending, stillUnchanged.Status);
        }
    }

    [Fact]
    public async Task RentSchedule_Generate_RequiresPropertyAccessAndPreservesGenerationRules()
    {
        using var factory = new AuthApiFactory();
        var ownedProperty = await SeedPropertyAsync(factory, LandlordA);
        var otherProperty = await SeedPropertyAsync(factory, LandlordB);
        var ownedLease = CreateLeaseAgreement(ownedProperty.Id, LeaseAgreementStatus.Active);
        var inaccessibleLease = CreateLeaseAgreement(otherProperty.Id, LeaseAgreementStatus.Active);
        var adminLease = CreateLeaseAgreement(otherProperty.Id, LeaseAgreementStatus.Active);
        var inactiveLease = CreateLeaseAgreement(ownedProperty.Id, LeaseAgreementStatus.Pending);
        await SeedAsync(factory, context =>
        {
            context.LeaseAgreements.AddRange(ownedLease, inaccessibleLease, adminLease, inactiveLease);
        });

        using var landlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord);
        using var otherLandlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord);
        using var admin = AuthorizedClient(factory, Guid.NewGuid(), UserRole.Admin);

        using var ownedResponse = await landlord.PostAsync(
            $"/api/rent-schedules/lease/{ownedLease.Id}/generate", null);
        using var duplicateResponse = await landlord.PostAsync(
            $"/api/rent-schedules/lease/{ownedLease.Id}/generate", null);
        using var inaccessibleResponse = await otherLandlord.PostAsync(
            $"/api/rent-schedules/lease/{inaccessibleLease.Id}/generate", null);
        using var adminResponse = await admin.PostAsync(
            $"/api/rent-schedules/lease/{adminLease.Id}/generate", null);
        using var missingResponse = await landlord.PostAsync(
            $"/api/rent-schedules/lease/{Guid.NewGuid()}/generate", null);
        using var inactiveResponse = await landlord.PostAsync(
            $"/api/rent-schedules/lease/{inactiveLease.Id}/generate", null);

        Assert.Equal(HttpStatusCode.OK, ownedResponse.StatusCode);
        Assert.NotEmpty(await ownedResponse.Content.ReadFromJsonAsync<List<RentScheduleItemResponseDto>>() ?? []);
        Assert.Equal(HttpStatusCode.Conflict, duplicateResponse.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, inaccessibleResponse.StatusCode);
        Assert.Equal(HttpStatusCode.OK, adminResponse.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, missingResponse.StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, inactiveResponse.StatusCode);

        using var scope = factory.Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        Assert.Empty(await context.RentScheduleItems
            .Where(item => item.LeaseAgreementId == inaccessibleLease.Id)
            .ToListAsync());
    }

    [Fact]
    public async Task Payment_LandlordList_ReturnsOwnedPaymentsAndExcludesOtherLandlords()
    {
        using var factory = new AuthApiFactory();
        var ownedProperty = await SeedPropertyAsync(factory, LandlordA);
        var otherProperty = await SeedPropertyAsync(factory, LandlordB);

        (LeaseAgreement Lease, RentScheduleItem Schedule, Payment Payment) CreatePayment(
            Guid propertyId, Guid tenantId, PaymentStatus status)
        {
            var lease = CreateLeaseAgreement(propertyId, LeaseAgreementStatus.Active);
            lease.TenantId = tenantId;
            var schedule = new RentScheduleItem
            {
                LeaseAgreementId = lease.Id,
                DueDate = lease.StartDate,
                Amount = lease.MonthlyRent
            };
            var payment = new Payment
            {
                RentScheduleItemId = schedule.Id,
                TenantId = tenantId,
                Amount = schedule.Amount,
                PaymentMethod = "BankTransfer",
                Status = status
            };
            return (lease, schedule, payment);
        }

        var ownedPending = CreatePayment(ownedProperty.Id, TenantA, PaymentStatus.Pending);
        var ownedCompleted = CreatePayment(ownedProperty.Id, TenantB, PaymentStatus.Completed);
        var other = CreatePayment(otherProperty.Id, TenantA, PaymentStatus.Failed);
        await SeedAsync(factory, context =>
        {
            context.LeaseAgreements.AddRange(
                ownedPending.Lease, ownedCompleted.Lease, other.Lease);
            context.RentScheduleItems.AddRange(
                ownedPending.Schedule, ownedCompleted.Schedule, other.Schedule);
            context.Payments.AddRange(
                ownedPending.Payment, ownedCompleted.Payment, other.Payment);
        });
        using var landlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord);
        using var otherLandlord = AuthorizedClient(factory, LandlordB, UserRole.Landlord);

        using var response = await landlord.GetAsync("/api/payments/landlord");
        using var otherResponse = await otherLandlord.GetAsync("/api/payments/landlord");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var payments = await response.Content.ReadFromJsonAsync<List<PaymentResponseDto>>();
        Assert.NotNull(payments);
        Assert.Equal(2, payments.Count);
        Assert.Contains(payments, payment => payment.Id == ownedPending.Payment.Id
            && payment.RentScheduleItemId == ownedPending.Schedule.Id
            && payment.Status == PaymentStatus.Pending);
        Assert.Contains(payments, payment => payment.Id == ownedCompleted.Payment.Id
            && payment.Status == PaymentStatus.Completed);
        Assert.DoesNotContain(payments, payment => payment.Id == other.Payment.Id);

        Assert.Equal(HttpStatusCode.OK, otherResponse.StatusCode);
        var otherPayments = await otherResponse.Content.ReadFromJsonAsync<List<PaymentResponseDto>>();
        Assert.Equal(other.Payment.Id, Assert.Single(otherPayments!).Id);
    }

    [Fact]
    public async Task Payment_LandlordList_ReturnsEmptyCollectionWhenNoPayments()
    {
        using var factory = new AuthApiFactory();
        using var landlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord);

        using var response = await landlord.GetAsync("/api/payments/landlord");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Empty((await response.Content.ReadFromJsonAsync<List<PaymentResponseDto>>())!);
    }

    [Fact]
    public async Task Payment_LandlordList_RejectsAnonymousAndTenant()
    {
        using var factory = new AuthApiFactory();
        using var anonymous = factory.CreateHttpsClient();
        using var tenant = AuthorizedClient(factory, TenantA, UserRole.Tenant);

        using var anonymousResponse = await anonymous.GetAsync("/api/payments/landlord");
        using var tenantResponse = await tenant.GetAsync("/api/payments/landlord");

        Assert.Equal(HttpStatusCode.Unauthorized, anonymousResponse.StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, tenantResponse.StatusCode);
    }

    [Fact]
    public async Task Payment_GetById_EnforcesTenantAndPropertyOwnership()
    {
        using var factory = new AuthApiFactory();
        var property = await SeedPropertyAsync(factory, LandlordA);
        var lease = new LeaseAgreement
        {
            RentalOfferId = Guid.NewGuid(),
            TenantId = TenantA,
            PropertyId = property.Id,
            MonthlyRent = 85000m,
            SecurityDeposit = 170000m,
            StartDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)),
            EndDate = DateOnly.FromDateTime(DateTime.UtcNow.AddMonths(12))
        };
        var scheduleItem = new RentScheduleItem
        {
            LeaseAgreementId = lease.Id,
            DueDate = lease.StartDate,
            Amount = lease.MonthlyRent
        };
        var payment = new Payment
        {
            RentScheduleItemId = scheduleItem.Id,
            TenantId = TenantA,
            Amount = scheduleItem.Amount,
            PaymentMethod = "BankTransfer"
        };
        await SeedAsync(factory, context =>
        {
            context.LeaseAgreements.Add(lease);
            context.RentScheduleItems.Add(scheduleItem);
            context.Payments.Add(payment);
        });

        using var tenant = AuthorizedClient(factory, TenantA, UserRole.Tenant);
        using var otherTenant = AuthorizedClient(factory, TenantB, UserRole.Tenant);
        using var landlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord);
        using var otherLandlord = AuthorizedClient(factory, LandlordB, UserRole.Landlord);
        using var admin = AuthorizedClient(factory, Guid.NewGuid(), UserRole.Admin);
        var route = $"/api/payments/{payment.Id}";

        using var tenantResponse = await tenant.GetAsync(route);
        using var otherTenantResponse = await otherTenant.GetAsync(route);
        using var landlordResponse = await landlord.GetAsync(route);
        using var otherLandlordResponse = await otherLandlord.GetAsync(route);
        using var adminResponse = await admin.GetAsync(route);
        using var missingResponse = await tenant.GetAsync($"/api/payments/{Guid.NewGuid()}");

        Assert.Equal(HttpStatusCode.OK, tenantResponse.StatusCode);
        Assert.Equal(payment.Id,
            (await tenantResponse.Content.ReadFromJsonAsync<PaymentResponseDto>())?.Id);
        Assert.Equal(HttpStatusCode.NotFound, otherTenantResponse.StatusCode);
        Assert.Equal(HttpStatusCode.OK, landlordResponse.StatusCode);
        Assert.Equal(payment.Id,
            (await landlordResponse.Content.ReadFromJsonAsync<PaymentResponseDto>())?.Id);
        Assert.Equal(HttpStatusCode.NotFound, otherLandlordResponse.StatusCode);
        Assert.Equal(HttpStatusCode.OK, adminResponse.StatusCode);
        Assert.Equal(payment.Id,
            (await adminResponse.Content.ReadFromJsonAsync<PaymentResponseDto>())?.Id);
        Assert.Equal(HttpStatusCode.NotFound, missingResponse.StatusCode);
    }

    [Theory]
    [InlineData("complete")]
    [InlineData("fail")]
    public async Task Payment_StateChanges_RequirePropertyAccessAndPreserveLifecycle(string action)
    {
        using var factory = new AuthApiFactory();
        var ownedProperty = await SeedPropertyAsync(factory, LandlordA);
        var otherProperty = await SeedPropertyAsync(factory, LandlordB);

        (LeaseAgreement Lease, RentScheduleItem Schedule, Payment Payment) CreatePayment(
            Guid propertyId,
            PaymentStatus status = PaymentStatus.Pending)
        {
            var lease = CreateLeaseAgreement(propertyId, LeaseAgreementStatus.Active);
            var schedule = new RentScheduleItem
            {
                LeaseAgreementId = lease.Id,
                DueDate = lease.StartDate,
                Amount = lease.MonthlyRent
            };
            var payment = new Payment
            {
                RentScheduleItemId = schedule.Id,
                TenantId = TenantA,
                Amount = schedule.Amount,
                PaymentMethod = "BankTransfer",
                Status = status
            };
            return (lease, schedule, payment);
        }

        var owned = CreatePayment(ownedProperty.Id);
        var inaccessible = CreatePayment(otherProperty.Id);
        var adminPayment = CreatePayment(otherProperty.Id);
        var conflicting = CreatePayment(
            ownedProperty.Id,
            action == "complete" ? PaymentStatus.Completed : PaymentStatus.Failed);
        await SeedAsync(factory, context =>
        {
            context.LeaseAgreements.AddRange(
                owned.Lease, inaccessible.Lease, adminPayment.Lease, conflicting.Lease);
            context.RentScheduleItems.AddRange(
                owned.Schedule, inaccessible.Schedule, adminPayment.Schedule, conflicting.Schedule);
            context.Payments.AddRange(
                owned.Payment, inaccessible.Payment, adminPayment.Payment, conflicting.Payment);
        });

        using var landlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord);
        using var otherLandlord = AuthorizedClient(factory, LandlordB, UserRole.Landlord);
        using var admin = AuthorizedClient(factory, Guid.NewGuid(), UserRole.Admin);
        var route = (Guid paymentId) => $"/api/payments/{paymentId}/{action}";

        using var ownedResponse = await landlord.PatchAsync(route(owned.Payment.Id), null);
        using var inaccessibleResponse = await otherLandlord.PatchAsync(
            route(owned.Payment.Id), null);
        using var propertyDeniedResponse = await landlord.PatchAsync(
            route(inaccessible.Payment.Id), null);
        using var adminResponse = await admin.PatchAsync(route(adminPayment.Payment.Id), null);
        using var missingResponse = await landlord.PatchAsync(route(Guid.NewGuid()), null);
        using var conflictResponse = await landlord.PatchAsync(route(conflicting.Payment.Id), null);

        Assert.Equal(HttpStatusCode.OK, ownedResponse.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, inaccessibleResponse.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, propertyDeniedResponse.StatusCode);
        Assert.Equal(HttpStatusCode.OK, adminResponse.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, missingResponse.StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, conflictResponse.StatusCode);

        using var scope = factory.Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var unchangedPayment = await context.Payments.SingleAsync(
            item => item.Id == inaccessible.Payment.Id);
        var unchangedSchedule = await context.RentScheduleItems.SingleAsync(
            item => item.Id == inaccessible.Schedule.Id);
        Assert.Equal(PaymentStatus.Pending, unchangedPayment.Status);
        Assert.Equal(RentScheduleStatus.Pending, unchangedSchedule.Status);

        var ownedPayment = await context.Payments.SingleAsync(item => item.Id == owned.Payment.Id);
        var ownedSchedule = await context.RentScheduleItems.SingleAsync(
            item => item.Id == owned.Schedule.Id);
        Assert.Equal(
            action == "complete" ? PaymentStatus.Completed : PaymentStatus.Failed,
            ownedPayment.Status);
        Assert.Equal(
            action == "complete" ? RentScheduleStatus.Paid : RentScheduleStatus.Pending,
            ownedSchedule.Status);
    }

    [Fact]
    public async Task RentalOffer_GetById_EnforcesTenantAndPropertyOwnership()
    {
        using var factory = new AuthApiFactory();
        var property = await SeedPropertyAsync(factory, LandlordA);
        var application = await SeedApplicationAsync(
            factory, TenantA, RentalApplicationStatus.Approved, property.Id);
        var offer = new RentalOffer
        {
            RentalApplicationId = application.Id,
            TenantId = TenantA,
            PropertyId = property.Id,
            MonthlyRent = 85000m,
            SecurityDeposit = 170000m,
            ProposedStartDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)),
            ProposedEndDate = DateOnly.FromDateTime(DateTime.UtcNow.AddMonths(12)),
            ExpiresAt = DateTimeOffset.UtcNow.AddDays(7)
        };
        var expiredOffer = new RentalOffer
        {
            RentalApplicationId = application.Id,
            TenantId = TenantA,
            PropertyId = property.Id,
            MonthlyRent = 85000m,
            SecurityDeposit = 170000m,
            ProposedStartDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)),
            ProposedEndDate = DateOnly.FromDateTime(DateTime.UtcNow.AddMonths(12)),
            ExpiresAt = DateTimeOffset.UtcNow.AddMinutes(-1),
            Status = RentalOfferStatus.Pending
        };
        await SeedAsync(factory, context => context.RentalOffers.AddRange(offer, expiredOffer));

        using var tenant = AuthorizedClient(factory, TenantA, UserRole.Tenant);
        using var otherTenant = AuthorizedClient(factory, TenantB, UserRole.Tenant);
        using var landlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord);
        using var otherLandlord = AuthorizedClient(factory, LandlordB, UserRole.Landlord);
        using var admin = AuthorizedClient(factory, Guid.NewGuid(), UserRole.Admin);
        var route = $"/api/rental-offers/{offer.Id}";

        using var tenantResponse = await tenant.GetAsync(route);
        using var otherTenantResponse = await otherTenant.GetAsync(route);
        using var landlordResponse = await landlord.GetAsync(route);
        using var otherLandlordResponse = await otherLandlord.GetAsync(route);
        using var adminResponse = await admin.GetAsync(route);
        using var missingResponse = await tenant.GetAsync($"/api/rental-offers/{Guid.NewGuid()}");

        Assert.Equal(HttpStatusCode.OK, tenantResponse.StatusCode);
        Assert.Equal(offer.Id,
            (await tenantResponse.Content.ReadFromJsonAsync<RentalOfferResponseDto>())?.Id);
        Assert.Equal(HttpStatusCode.NotFound, otherTenantResponse.StatusCode);
        Assert.Equal(HttpStatusCode.OK, landlordResponse.StatusCode);
        Assert.Equal(offer.Id,
            (await landlordResponse.Content.ReadFromJsonAsync<RentalOfferResponseDto>())?.Id);
        Assert.Equal(HttpStatusCode.NotFound, otherLandlordResponse.StatusCode);
        Assert.Equal(HttpStatusCode.OK, adminResponse.StatusCode);
        Assert.Equal(offer.Id,
            (await adminResponse.Content.ReadFromJsonAsync<RentalOfferResponseDto>())?.Id);
        Assert.Equal(HttpStatusCode.NotFound, missingResponse.StatusCode);

        using var unauthorizedExpiredRead = await otherTenant.GetAsync(
            $"/api/rental-offers/{expiredOffer.Id}");
        Assert.Equal(HttpStatusCode.NotFound, unauthorizedExpiredRead.StatusCode);

        using (var scope = factory.Services.CreateScope())
        {
            var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            var unchangedOffer = await context.RentalOffers
                .AsNoTracking()
                .SingleAsync(item => item.Id == expiredOffer.Id);
            Assert.Equal(RentalOfferStatus.Pending, unchangedOffer.Status);
        }

        using var ownerExpiredRead = await tenant.GetAsync(
            $"/api/rental-offers/{expiredOffer.Id}");
        Assert.Equal(HttpStatusCode.OK, ownerExpiredRead.StatusCode);
        Assert.Equal(RentalOfferStatus.Expired,
            (await ownerExpiredRead.Content.ReadFromJsonAsync<RentalOfferResponseDto>())?.Status);
    }

    [Fact]
    public async Task RentalOffer_LandlordList_ContainsOnlyOwnedPropertyOffers()
    {
        using var factory = new AuthApiFactory();
        var ownedProperty = await SeedPropertyAsync(factory, LandlordA);
        var otherProperty = await SeedPropertyAsync(factory, LandlordB);
        var owned = CreateRentalOffer(TenantA, ownedProperty.Id);
        var other = CreateRentalOffer(TenantB, otherProperty.Id);
        await SeedAsync(factory, context => context.RentalOffers.AddRange(owned, other));
        using var landlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord);

        using var response = await landlord.GetAsync("/api/rental-offers/landlord");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var offers = await response.Content.ReadFromJsonAsync<List<RentalOfferResponseDto>>();
        Assert.NotNull(offers);
        Assert.Equal(owned.Id, Assert.Single(offers).Id);
        Assert.DoesNotContain(offers, item => item.Id == other.Id);
    }

    [Fact]
    public async Task RentalOffer_LandlordList_ReturnsEmptyCollectionWhenNoOffers()
    {
        using var factory = new AuthApiFactory();
        using var landlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord);

        using var response = await landlord.GetAsync("/api/rental-offers/landlord");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Empty((await response.Content.ReadFromJsonAsync<List<RentalOfferResponseDto>>())!);
    }

    [Fact]
    public async Task RentalOffer_LandlordList_RejectsAnonymousAndTenant()
    {
        using var factory = new AuthApiFactory();
        using var anonymous = factory.CreateHttpsClient();
        using var tenant = AuthorizedClient(factory, TenantA, UserRole.Tenant);

        using var anonymousResponse = await anonymous.GetAsync("/api/rental-offers/landlord");
        using var tenantResponse = await tenant.GetAsync("/api/rental-offers/landlord");

        Assert.Equal(HttpStatusCode.Unauthorized, anonymousResponse.StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, tenantResponse.StatusCode);
    }

    [Fact]
    public async Task RentalOffer_Create_RequiresLandlordPropertyAccessAndPreservesValidation()
    {
        using var factory = new AuthApiFactory();
        var ownedProperty = await SeedPropertyAsync(factory, LandlordA);
        var otherProperty = await SeedPropertyAsync(factory, LandlordB);
        var ownedApplication = await SeedApplicationAsync(
            factory, TenantA, RentalApplicationStatus.Approved, ownedProperty.Id);
        var inaccessibleApplication = await SeedApplicationAsync(
            factory, TenantB, RentalApplicationStatus.Approved, ownedProperty.Id);
        var adminApplication = await SeedApplicationAsync(
            factory, TenantB, RentalApplicationStatus.Approved, otherProperty.Id);
        var missingPropertyApplication = await SeedApplicationAsync(
            factory, TenantA, RentalApplicationStatus.Approved, Guid.NewGuid());
        var underReviewApplication = await SeedApplicationAsync(
            factory, TenantA, RentalApplicationStatus.UnderReview, ownedProperty.Id);

        using var landlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord);
        using var otherLandlord = AuthorizedClient(factory, LandlordB, UserRole.Landlord);
        using var admin = AuthorizedClient(factory, Guid.NewGuid(), UserRole.Admin);

        using var ownedResponse = await landlord.PostAsJsonAsync(
            "/api/rental-offers", RentalOfferBody(ownedApplication.Id));
        using var inaccessibleResponse = await otherLandlord.PostAsJsonAsync(
            "/api/rental-offers", RentalOfferBody(inaccessibleApplication.Id));
        using var adminResponse = await admin.PostAsJsonAsync(
            "/api/rental-offers", RentalOfferBody(adminApplication.Id));
        using var missingResponse = await landlord.PostAsJsonAsync(
            "/api/rental-offers", RentalOfferBody(Guid.NewGuid()));
        using var missingPropertyResponse = await landlord.PostAsJsonAsync(
            "/api/rental-offers", RentalOfferBody(missingPropertyApplication.Id));
        using var validationResponse = await landlord.PostAsJsonAsync(
            "/api/rental-offers", RentalOfferBody(underReviewApplication.Id));

        Assert.Equal(HttpStatusCode.Created, ownedResponse.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, inaccessibleResponse.StatusCode);
        Assert.Equal(HttpStatusCode.Created, adminResponse.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, missingResponse.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, missingPropertyResponse.StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, validationResponse.StatusCode);
    }

    [Fact]
    public async Task RentalOffer_Withdraw_RequiresLandlordPropertyAccessAndPreservesLifecycle()
    {
        using var factory = new AuthApiFactory();
        var ownedProperty = await SeedPropertyAsync(factory, LandlordA);
        var otherProperty = await SeedPropertyAsync(factory, LandlordB);
        var ownedOffer = CreateRentalOffer(TenantA, ownedProperty.Id);
        var inaccessibleOffer = CreateRentalOffer(TenantB, otherProperty.Id);
        var adminOffer = CreateRentalOffer(TenantB, otherProperty.Id);
        var conflictingOffer = CreateRentalOffer(
            TenantA, ownedProperty.Id, RentalOfferStatus.Accepted);
        await SeedAsync(factory, context =>
        {
            context.RentalOffers.AddRange(
                ownedOffer, inaccessibleOffer, adminOffer, conflictingOffer);
        });

        using var landlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord);
        using var otherLandlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord);
        using var admin = AuthorizedClient(factory, Guid.NewGuid(), UserRole.Admin);

        using var ownedResponse = await landlord.PatchAsync(
            $"/api/rental-offers/{ownedOffer.Id}/withdraw", null);
        using var inaccessibleResponse = await otherLandlord.PatchAsync(
            $"/api/rental-offers/{inaccessibleOffer.Id}/withdraw", null);
        using var adminResponse = await admin.PatchAsync(
            $"/api/rental-offers/{adminOffer.Id}/withdraw", null);
        using var missingResponse = await landlord.PatchAsync(
            $"/api/rental-offers/{Guid.NewGuid()}/withdraw", null);
        using var conflictResponse = await landlord.PatchAsync(
            $"/api/rental-offers/{conflictingOffer.Id}/withdraw", null);

        Assert.Equal(HttpStatusCode.OK, ownedResponse.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, inaccessibleResponse.StatusCode);
        Assert.Equal(HttpStatusCode.OK, adminResponse.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, missingResponse.StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, conflictResponse.StatusCode);

        using var scope = factory.Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        Assert.Equal(RentalOfferStatus.Withdrawn,
            (await context.RentalOffers.SingleAsync(item => item.Id == ownedOffer.Id)).Status);
        Assert.Equal(RentalOfferStatus.Pending,
            (await context.RentalOffers.SingleAsync(item => item.Id == inaccessibleOffer.Id)).Status);
    }

    [Fact]
    public async Task LeaseAgreement_Create_RequiresAccessToAcceptedOfferProperty()
    {
        using var factory = new AuthApiFactory();
        var ownedProperty = await SeedPropertyAsync(factory, LandlordA);
        var otherProperty = await SeedPropertyAsync(factory, LandlordB);
        var ownedOffer = CreateRentalOffer(TenantA, ownedProperty.Id, RentalOfferStatus.Accepted);
        var inaccessibleOffer = CreateRentalOffer(TenantB, ownedProperty.Id, RentalOfferStatus.Accepted);
        var adminOffer = CreateRentalOffer(TenantB, otherProperty.Id, RentalOfferStatus.Accepted);
        var missingPropertyOffer = CreateRentalOffer(
            TenantA, Guid.NewGuid(), RentalOfferStatus.Accepted);
        var pendingOffer = CreateRentalOffer(TenantA, ownedProperty.Id);
        await SeedAsync(factory, context =>
        {
            context.RentalOffers.AddRange(
                ownedOffer, inaccessibleOffer, adminOffer, missingPropertyOffer, pendingOffer);
        });

        using var landlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord);
        using var otherLandlord = AuthorizedClient(factory, LandlordB, UserRole.Landlord);
        using var admin = AuthorizedClient(factory, Guid.NewGuid(), UserRole.Admin);

        using var ownedResponse = await landlord.PostAsJsonAsync(
            "/api/lease-agreements", new { rentalOfferId = ownedOffer.Id });
        using var inaccessibleResponse = await otherLandlord.PostAsJsonAsync(
            "/api/lease-agreements", new { rentalOfferId = inaccessibleOffer.Id });
        using var adminResponse = await admin.PostAsJsonAsync(
            "/api/lease-agreements", new { rentalOfferId = adminOffer.Id });
        using var missingResponse = await landlord.PostAsJsonAsync(
            "/api/lease-agreements", new { rentalOfferId = Guid.NewGuid() });
        using var missingPropertyResponse = await landlord.PostAsJsonAsync(
            "/api/lease-agreements", new { rentalOfferId = missingPropertyOffer.Id });
        using var validationResponse = await landlord.PostAsJsonAsync(
            "/api/lease-agreements", new { rentalOfferId = pendingOffer.Id });

        Assert.Equal(HttpStatusCode.Created, ownedResponse.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, inaccessibleResponse.StatusCode);
        Assert.Equal(HttpStatusCode.Created, adminResponse.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, missingResponse.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, missingPropertyResponse.StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, validationResponse.StatusCode);
    }

    [Theory]
    [InlineData("activate", LeaseAgreementStatus.Pending, LeaseAgreementStatus.Active)]
    [InlineData("terminate", LeaseAgreementStatus.Active, LeaseAgreementStatus.Pending)]
    [InlineData("complete", LeaseAgreementStatus.Active, LeaseAgreementStatus.Pending)]
    public async Task LeaseAgreement_StateChanges_RequirePropertyAccessAndPreserveLifecycle(
        string action,
        LeaseAgreementStatus initialStatus,
        LeaseAgreementStatus conflictingStatus)
    {
        using var factory = new AuthApiFactory();
        var ownedProperty = await SeedPropertyAsync(factory, LandlordA);
        var otherProperty = await SeedPropertyAsync(factory, LandlordB);
        var ownedLease = CreateLeaseAgreement(ownedProperty.Id, initialStatus);
        var inaccessibleLease = CreateLeaseAgreement(otherProperty.Id, initialStatus);
        var adminLease = CreateLeaseAgreement(otherProperty.Id, initialStatus);
        var conflictingLease = CreateLeaseAgreement(ownedProperty.Id, conflictingStatus);
        await SeedAsync(factory, context =>
        {
            context.LeaseAgreements.AddRange(
                ownedLease, inaccessibleLease, adminLease, conflictingLease);
        });

        using var landlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord);
        using var otherLandlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord);
        using var admin = AuthorizedClient(factory, Guid.NewGuid(), UserRole.Admin);

        using var ownedResponse = await CallLeaseActionAsync(landlord, action, ownedLease.Id);
        using var inaccessibleResponse = await CallLeaseActionAsync(
            otherLandlord, action, inaccessibleLease.Id);
        using var adminResponse = await CallLeaseActionAsync(admin, action, adminLease.Id);
        using var missingResponse = await CallLeaseActionAsync(landlord, action, Guid.NewGuid());
        using var conflictResponse = await CallLeaseActionAsync(
            landlord, action, conflictingLease.Id);

        Assert.Equal(HttpStatusCode.OK, ownedResponse.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, inaccessibleResponse.StatusCode);
        Assert.Equal(HttpStatusCode.OK, adminResponse.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, missingResponse.StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, conflictResponse.StatusCode);

        using var scope = factory.Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        Assert.Equal(initialStatus,
            (await context.LeaseAgreements.SingleAsync(item => item.Id == inaccessibleLease.Id)).Status);
    }

    private static LeaseAgreement CreateLeaseAgreement(
        Guid propertyId,
        LeaseAgreementStatus status) => new()
    {
        RentalOfferId = Guid.NewGuid(),
        TenantId = TenantA,
        PropertyId = propertyId,
        MonthlyRent = 85000m,
        SecurityDeposit = 170000m,
        StartDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)),
        EndDate = DateOnly.FromDateTime(DateTime.UtcNow.AddMonths(12)),
        Status = status
    };

    [Fact]
    public async Task LeaseAgreement_LandlordList_ContainsOnlyOwnedPropertyLeases()
    {
        using var factory = new AuthApiFactory();
        var ownedProperty = await SeedPropertyAsync(factory, LandlordA);
        var otherProperty = await SeedPropertyAsync(factory, LandlordB);
        var owned = CreateLeaseAgreement(ownedProperty.Id, LeaseAgreementStatus.Pending);
        var other = CreateLeaseAgreement(otherProperty.Id, LeaseAgreementStatus.Active);
        await SeedAsync(factory, context => context.LeaseAgreements.AddRange(owned, other));
        using var landlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord);

        using var response = await landlord.GetAsync("/api/lease-agreements/landlord");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var leases = await response.Content.ReadFromJsonAsync<List<LeaseAgreementResponseDto>>();
        Assert.NotNull(leases);
        Assert.Equal(owned.Id, Assert.Single(leases).Id);
        Assert.DoesNotContain(leases, item => item.Id == other.Id);
    }

    [Fact]
    public async Task LeaseAgreement_LandlordList_ReturnsEmptyCollectionWhenNoLeases()
    {
        using var factory = new AuthApiFactory();
        using var landlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord);

        using var response = await landlord.GetAsync("/api/lease-agreements/landlord");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Empty((await response.Content.ReadFromJsonAsync<List<LeaseAgreementResponseDto>>())!);
    }

    [Fact]
    public async Task LeaseAgreement_LandlordList_RejectsAnonymousAndTenant()
    {
        using var factory = new AuthApiFactory();
        using var anonymous = factory.CreateHttpsClient();
        using var tenant = AuthorizedClient(factory, TenantA, UserRole.Tenant);

        using var anonymousResponse = await anonymous.GetAsync("/api/lease-agreements/landlord");
        using var tenantResponse = await tenant.GetAsync("/api/lease-agreements/landlord");

        Assert.Equal(HttpStatusCode.Unauthorized, anonymousResponse.StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, tenantResponse.StatusCode);
    }

    private static Task<HttpResponseMessage> CallLeaseActionAsync(
        HttpClient client,
        string action,
        Guid leaseId) => action switch
    {
        "activate" => client.PatchAsync($"/api/lease-agreements/{leaseId}/activate", null),
        "terminate" => client.PatchAsync($"/api/lease-agreements/{leaseId}/terminate", null),
        "complete" => client.PatchAsync($"/api/lease-agreements/{leaseId}/complete", null),
        _ => throw new ArgumentOutOfRangeException(nameof(action))
    };

    private static object RentalOfferBody(Guid rentalApplicationId) => new
    {
        rentalApplicationId,
        monthlyRent = 85000m,
        securityDeposit = 170000m,
        proposedStartDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)),
        proposedEndDate = DateOnly.FromDateTime(DateTime.UtcNow.AddMonths(12)),
        expiresAt = DateTimeOffset.UtcNow.AddDays(7),
        landlordNote = "Authorization test offer."
    };

    private static RentalOffer CreateRentalOffer(
        Guid tenantId,
        Guid propertyId,
        RentalOfferStatus status = RentalOfferStatus.Pending) => new()
    {
        RentalApplicationId = Guid.NewGuid(),
        TenantId = tenantId,
        PropertyId = propertyId,
        MonthlyRent = 85000m,
        SecurityDeposit = 170000m,
        ProposedStartDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)),
        ProposedEndDate = DateOnly.FromDateTime(DateTime.UtcNow.AddMonths(12)),
        ExpiresAt = DateTimeOffset.UtcNow.AddDays(7),
        Status = status
    };

    [Fact]
    public async Task LeaseAgreement_GetById_EnforcesTenantAndPropertyOwnership()
    {
        using var factory = new AuthApiFactory();
        var property = await SeedPropertyAsync(factory, LandlordA);
        var lease = new LeaseAgreement
        {
            RentalOfferId = Guid.NewGuid(),
            TenantId = TenantA,
            PropertyId = property.Id,
            MonthlyRent = 85000m,
            SecurityDeposit = 170000m,
            StartDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)),
            EndDate = DateOnly.FromDateTime(DateTime.UtcNow.AddMonths(12))
        };
        await SeedAsync(factory, context => context.LeaseAgreements.Add(lease));

        using var tenant = AuthorizedClient(factory, TenantA, UserRole.Tenant);
        using var otherTenant = AuthorizedClient(factory, TenantB, UserRole.Tenant);
        using var landlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord);
        using var otherLandlord = AuthorizedClient(factory, LandlordB, UserRole.Landlord);
        using var admin = AuthorizedClient(factory, Guid.NewGuid(), UserRole.Admin);
        var route = $"/api/lease-agreements/{lease.Id}";

        using var tenantResponse = await tenant.GetAsync(route);
        using var otherTenantResponse = await otherTenant.GetAsync(route);
        using var landlordResponse = await landlord.GetAsync(route);
        using var otherLandlordResponse = await otherLandlord.GetAsync(route);
        using var adminResponse = await admin.GetAsync(route);
        using var missingResponse = await tenant.GetAsync($"/api/lease-agreements/{Guid.NewGuid()}");

        Assert.Equal(HttpStatusCode.OK, tenantResponse.StatusCode);
        Assert.Equal(lease.Id,
            (await tenantResponse.Content.ReadFromJsonAsync<LeaseAgreementResponseDto>())?.Id);
        Assert.Equal(HttpStatusCode.NotFound, otherTenantResponse.StatusCode);
        Assert.Equal(HttpStatusCode.OK, landlordResponse.StatusCode);
        Assert.Equal(lease.Id,
            (await landlordResponse.Content.ReadFromJsonAsync<LeaseAgreementResponseDto>())?.Id);
        Assert.Equal(HttpStatusCode.NotFound, otherLandlordResponse.StatusCode);
        Assert.Equal(HttpStatusCode.OK, adminResponse.StatusCode);
        Assert.Equal(lease.Id,
            (await adminResponse.Content.ReadFromJsonAsync<LeaseAgreementResponseDto>())?.Id);
        Assert.Equal(HttpStatusCode.NotFound, missingResponse.StatusCode);
    }

    [Fact]
    public async Task Landlord_CannotAccessAnotherLandlordsPropertyResources()
    {
        using var factory = new AuthApiFactory();
        _ = await SeedPropertyAsync(factory, LandlordA);
        var otherProperty = await SeedPropertyAsync(factory, LandlordB);
        var otherViewing = await SeedViewingAsync(factory, TenantB, otherProperty.Id);
        var otherApplication = await SeedApplicationAsync(
            factory, TenantB, RentalApplicationStatus.Submitted, otherProperty.Id);
        var otherDocument = await SeedDocumentAsync(factory, otherApplication.Id);
        var otherWorkflow = await SeedValidationWorkflowAsync(factory, otherApplication.Id);
        using var landlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord, false);

        var responses = new[]
        {
            await landlord.GetAsync($"/api/viewings/{otherViewing.Id}"),
            await landlord.GetAsync($"/api/viewings/property/{otherProperty.Id}"),
            await landlord.PatchAsJsonAsync($"/api/viewings/{otherViewing.Id}/approve",
                new { landlordResponse = "Not allowed" }),
            await landlord.PatchAsJsonAsync($"/api/viewings/{otherViewing.Id}/reject",
                new { landlordResponse = "Not allowed" }),
            await landlord.GetAsync($"/api/rental-applications/{otherApplication.Id}"),
            await landlord.GetAsync($"/api/rental-applications/property/{otherProperty.Id}"),
            await landlord.PatchAsync(
                $"/api/rental-applications/{otherApplication.Id}/review", null),
            await landlord.PatchAsJsonAsync(
                $"/api/rental-applications/{otherApplication.Id}/approve",
                new { landlordResponse = "Not allowed" }),
            await landlord.PatchAsJsonAsync(
                $"/api/rental-applications/{otherApplication.Id}/reject",
                new { landlordResponse = "Not allowed" }),
            await landlord.PatchAsJsonAsync(
                $"/api/rental-applications/{otherApplication.Id}/request-changes",
                new { landlordResponse = "Not allowed" }),
            await landlord.GetAsync(
                $"/api/rental-applications/{otherApplication.Id}/documents"),
            await landlord.GetAsync($"/api/application-documents/{otherDocument.Id}"),
            await landlord.GetAsync(
                $"/api/application-documents/{otherDocument.Id}/download"),
            await landlord.PostAsync(
                $"/api/rental-applications/{otherApplication.Id}/validation-runs", null),
            await landlord.GetAsync(
                $"/api/rental-applications/{otherApplication.Id}/validation-runs"),
            await landlord.GetAsync(
                $"/api/application-validation-workflows/{otherWorkflow.Id}")
        };

        Assert.All(responses, response => Assert.Equal(HttpStatusCode.NotFound, response.StatusCode));
        Assert.Equal(0, factory.FileStorage.DownloadUrlCalls);
        Assert.Equal(0, factory.ValidationOrchestrator.Calls);

        using var scope = factory.Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        Assert.Equal(ViewingStatus.Pending,
            (await context.ViewingRequests.SingleAsync(item => item.Id == otherViewing.Id)).Status);
        Assert.Equal(RentalApplicationStatus.Submitted,
            (await context.RentalApplications.SingleAsync(
                item => item.Id == otherApplication.Id)).Status);

        foreach (var response in responses)
        {
            response.Dispose();
        }
    }

    [Fact]
    public async Task Landlord_CanReadDownloadAndStartValidationForOwnedProperty()
    {
        using var factory = new AuthApiFactory();
        var property = await SeedPropertyAsync(factory, LandlordA);
        _ = await SeedPropertyAsync(factory, LandlordB);
        var viewing = await SeedViewingAsync(factory, TenantA, property.Id);
        var application = await SeedApplicationAsync(
            factory, TenantA, RentalApplicationStatus.Submitted, property.Id);
        var document = await SeedDocumentAsync(factory, application.Id);
        var workflow = await SeedValidationWorkflowAsync(factory, application.Id);
        using var landlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord, false);

        var responses = new[]
        {
            await landlord.GetAsync($"/api/viewings/{viewing.Id}"),
            await landlord.GetAsync($"/api/viewings/property/{property.Id}"),
            await landlord.GetAsync($"/api/rental-applications/{application.Id}"),
            await landlord.GetAsync($"/api/rental-applications/property/{property.Id}"),
            await landlord.GetAsync($"/api/rental-applications/{application.Id}/documents"),
            await landlord.GetAsync($"/api/application-documents/{document.Id}"),
            await landlord.GetAsync($"/api/application-documents/{document.Id}/download"),
            await landlord.PostAsync(
                $"/api/rental-applications/{application.Id}/validation-runs", null),
            await landlord.GetAsync(
                $"/api/rental-applications/{application.Id}/validation-runs"),
            await landlord.GetAsync($"/api/application-validation-workflows/{workflow.Id}")
        };

        Assert.All(responses, response =>
            Assert.True(response.IsSuccessStatusCode || response.StatusCode == HttpStatusCode.Redirect));
        Assert.Equal(1, factory.FileStorage.DownloadUrlCalls);
        Assert.Equal(1, factory.ValidationOrchestrator.Calls);

        foreach (var response in responses)
        {
            response.Dispose();
        }
    }

    [Fact]
    public async Task Landlord_CanMakeDecisionsForOwnedPropertyResources()
    {
        using var factory = new AuthApiFactory();
        var property = await SeedPropertyAsync(factory, LandlordA);
        _ = await SeedPropertyAsync(factory, LandlordB);
        var viewingToApprove = await SeedViewingAsync(factory, TenantA, property.Id);
        var viewingToReject = await SeedViewingAsync(factory, TenantB, property.Id);
        var applicationToReview = await SeedApplicationAsync(
            factory, TenantA, RentalApplicationStatus.Submitted, property.Id);
        var applicationToApprove = await SeedApplicationAsync(
            factory, TenantB, RentalApplicationStatus.Submitted, property.Id);
        var applicationToReject = await SeedApplicationAsync(
            factory, Guid.NewGuid(), RentalApplicationStatus.Submitted, property.Id);
        var applicationForChanges = await SeedApplicationAsync(
            factory, Guid.NewGuid(), RentalApplicationStatus.Submitted, property.Id);
        using var landlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord);

        var responses = new[]
        {
            await landlord.PatchAsJsonAsync($"/api/viewings/{viewingToApprove.Id}/approve",
                new { landlordResponse = "Approved" }),
            await landlord.PatchAsJsonAsync($"/api/viewings/{viewingToReject.Id}/reject",
                new { landlordResponse = "Rejected" }),
            await landlord.PatchAsync(
                $"/api/rental-applications/{applicationToReview.Id}/review", null),
            await landlord.PatchAsJsonAsync(
                $"/api/rental-applications/{applicationToApprove.Id}/approve",
                new { landlordResponse = "Approved" }),
            await landlord.PatchAsJsonAsync(
                $"/api/rental-applications/{applicationToReject.Id}/reject",
                new { landlordResponse = "Rejected" }),
            await landlord.PatchAsJsonAsync(
                $"/api/rental-applications/{applicationForChanges.Id}/request-changes",
                new { landlordResponse = "Please update" })
        };

        Assert.All(responses, response => Assert.Equal(HttpStatusCode.OK, response.StatusCode));

        foreach (var response in responses)
        {
            response.Dispose();
        }
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
        factory.EnsureActiveUser(userId, role);
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
        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, subject),
            new("token_version", "0")
        };
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

    private static object ApplicationBody(Guid propertyId) => new
    {
        propertyId,
        moveInDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)),
        monthlyIncome = 250000m,
        occupation = "Engineer",
        numberOfOccupants = 2,
        tenantNote = "Test"
    };

    private static MultipartFormDataContent DocumentForm(
        string documentType,
        string fileName)
    {
        var form = new MultipartFormDataContent();
        var file = new ByteArrayContent([1, 2, 3]);
        file.Headers.ContentType = new MediaTypeHeaderValue("application/pdf");
        form.Add(file, "file", fileName);
        form.Add(new StringContent(documentType), "documentType");
        return form;
    }

    private static async Task<Property> SeedPropertyAsync(
        AuthApiFactory factory,
        Guid landlordId)
    {
        var property = new Property
        {
            Id = Guid.NewGuid(),
            LandlordId = landlordId,
            Title = "Authorization test property",
            Description = "Property used to verify landlord resource isolation.",
            Address = "1 Test Street",
            City = "Colombo",
            MonthlyRent = 100000m,
            Bedrooms = 2,
            Bathrooms = 1,
            IsAvailable = true,
            CreatedAt = DateTimeOffset.UtcNow
        };
        await SeedAsync(factory, context =>
        {
            context.Properties.Add(property);
            context.PropertyViewingAvailabilities.AddRange(Enumerable.Range(0, 7).Select(day =>
                new PropertyViewingAvailability { PropertyId = property.Id, DayOfWeek = day,
                    IsEnabled = true, StartTime = new TimeOnly(9, 0), EndTime = new TimeOnly(17, 0) }));
        });
        return property;
    }

    private static async Task<ViewingRequest> SeedViewingAsync(
        AuthApiFactory factory,
        Guid tenantId,
        Guid? propertyId = null)
    {
        var viewing = new ViewingRequest
        {
            Id = Guid.NewGuid(), TenantId = tenantId,
            PropertyId = propertyId ?? Guid.NewGuid(),
            RequestedDateTime = DateTimeOffset.UtcNow.AddDays(5),
            Status = ViewingStatus.Pending, CreatedAt = DateTimeOffset.UtcNow
        };
        await SeedAsync(factory, context => context.ViewingRequests.Add(viewing));
        return viewing;
    }

    private static async Task<RentalApplication> SeedApplicationAsync(
        AuthApiFactory factory,
        Guid tenantId,
        RentalApplicationStatus status,
        Guid? propertyId = null)
    {
        var application = new RentalApplication
        {
            Id = Guid.NewGuid(), TenantId = tenantId,
            PropertyId = propertyId ?? Guid.NewGuid(),
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
