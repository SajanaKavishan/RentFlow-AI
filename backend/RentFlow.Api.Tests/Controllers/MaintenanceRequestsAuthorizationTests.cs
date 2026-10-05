using RentFlow.Api.Tests.Services;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Maintenance;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Tests.Authentication;
using Xunit;

namespace RentFlow.Api.Tests.Controllers;

public sealed class MaintenanceRequestsAuthorizationTests
{
    private const string ValidPassword = "Secure1!Password";

    [Theory]
    [InlineData(UserRole.Landlord, true, "coordination-workflows")]
    [InlineData(UserRole.Landlord, false, "coordination-workflows")]
    [InlineData(UserRole.Tenant, true, "coordination-workflows")]
    [InlineData(UserRole.MaintenanceTechnician, true, "coordination-workflows")]
    [InlineData(UserRole.Admin, false, "coordination-workflows")]
    [InlineData(UserRole.Landlord, true, "coordination-analysis")]
    [InlineData(UserRole.Landlord, false, "coordination-analysis")]
    [InlineData(UserRole.Tenant, true, "coordination-analysis")]
    [InlineData(UserRole.MaintenanceTechnician, true, "coordination-analysis")]
    [InlineData(UserRole.Admin, false, "coordination-analysis")]
    public async Task PhotoAnalysis_AuthorizesBeforeStorageAndPersistsOnlySafeMetadata(UserRole role, bool owns, string action)
    {
        var agent = new PhotoMaintenanceAgent();
        using var factory = new AuthApiFactory { MaintenanceCoordinationAgentClient = agent };
        using var client = factory.CreateHttpsClient();
        var actor = await AuthenticateAsync(client, $"photos-{role}-{owns}-{action}@example.com", role, factory);
        var requestId = await SeedRequestAsync(factory, tenantId: role == UserRole.Tenant ? actor : null,
            technicianId: role == UserRole.MaintenanceTechnician ? actor : null);
        var source = MaintenancePhotoEvidenceServiceTests.ImageBytes(metadata: true);
        const string key = "private-photo-storage-key";
        await factory.FileStorage.UploadAsync(new MemoryStream(source), key, "image/png");
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            var request = await db.MaintenanceRequests.SingleAsync(item => item.Id == requestId);
            db.Properties.Add(new Property { Id = request.PropertyId, LandlordId = owns ? actor : Guid.NewGuid(),
                Title = "Private property", Address = "private-address", City = "private-city" });
            db.MaintenanceAttachments.Add(new MaintenanceAttachment { MaintenanceRequestId = requestId,
                FileName = "private-original-photo.png", StorageKey = key, ContentType = "image/png", FileSize = source.Length });
            await db.SaveChangesAsync();
        }
        var allowed = role == UserRole.Admin || role == UserRole.Landlord && owns;
        var response = await client.PostAsync($"/api/maintenance-requests/{requestId}/{action}", null);
        Assert.Equal(allowed ? (action == "coordination-workflows" ? HttpStatusCode.Created : HttpStatusCode.OK)
            : HttpStatusCode.Forbidden, response.StatusCode);
        Assert.Equal(allowed ? 1 : 0, factory.FileStorage.DownloadBytesCalls);
        Assert.Equal(0, factory.FileStorage.DownloadUrlCalls);
        Assert.Equal(allowed ? 1 : 0, agent.Calls);
        if (allowed)
        {
            Assert.Single(agent.Request!.EvidencePhotos);
            var payload = JsonSerializer.Serialize(agent.Request);
            foreach (var forbidden in new[] { key, "private-original-photo", "private-address", "private-city",
                         "tenantId", "propertyId", "storageKey", "fileName", "signedUrl", "94770000000", "accessToken" })
                Assert.DoesNotContain(forbidden, payload, StringComparison.OrdinalIgnoreCase);
            if (action == "coordination-workflows")
            {
                var latest = await client.GetAsync($"/api/maintenance-requests/{requestId}/coordination-workflows/latest");
                var body = await latest.Content.ReadAsStringAsync();
                using var json = JsonDocument.Parse(body);
                Assert.Equal(1, json.RootElement.GetProperty("photoEvidence").GetProperty("analyzedPhotoCount").GetInt32());
                Assert.DoesNotContain("mediaBase64", body, StringComparison.OrdinalIgnoreCase);
                Assert.DoesNotContain(agent.Request.EvidencePhotos.Single().MediaBase64, body);
                Assert.DoesNotContain(key, body);
                Assert.DoesNotContain("photoEvidence", json.RootElement.GetProperty("finalResultJson").GetString());
            }
        }
        using var finalScope = factory.Services.CreateScope();
        var context = finalScope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var stored = await context.MaintenanceRequests.SingleAsync(item => item.Id == requestId);
        Assert.Equal(MaintenanceRequestStatus.Submitted, stored.Status);
        Assert.Equal(MaintenanceCategory.Plumbing, stored.Category);
        Assert.Equal(MaintenancePriority.Normal, stored.Priority);
        Assert.Empty(context.MaintenanceStatusHistories);
    }

    private sealed class PhotoMaintenanceAgent : RentFlow.Api.Services.Interfaces.IMaintenanceCoordinationAgentClient
    {
        public int Calls { get; private set; }
        public MaintenanceCoordinationAgentRequest? Request { get; private set; }
        public Task<MaintenanceCoordinationAgentResponse> AnalyzeAsync(MaintenanceCoordinationAgentRequest request, CancellationToken token = default)
        {
            Calls++;
            Request = request;
            Assert.True(request.RemainingBudgetSeconds is > 0 and < 30);
            return Task.FromResult(new MaintenanceCoordinationAgentResponse
            {
                MaintenanceRequestId = request.MaintenanceRequestId, Result = MaintenanceCoordinationTestData.Result(request),
                ExecutionMetadata = new MaintenanceCoordinationExecutionMetadata
                {
                    ExecutedSteps = MaintenanceCoordinationTestData.Metadata().ExecutedSteps,
                    PhotoEvidence = new() { SuppliedPhotoCount = request.Attachments.Count, AnalyzedPhotoCount = request.EvidencePhotos.Count }
                }
            });
        }
    }

    [Theory]
    [InlineData(null)]
    [InlineData("Night")]
    [InlineData(1)]
    public async Task Create_RejectsMissingInvalidOrNumericAccessWindow(object? access)
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        var tenant = await AuthenticateAsync(client, "access-validation@example.com", UserRole.Tenant);
        var input = new { propertyId = Guid.NewGuid(), description = "Kitchen tap leak.", category = 0, priority = 1, preferredAccessWindow = access };
        var response = await client.PostAsJsonAsync($"/api/maintenance-requests?tenantId={tenant}", input);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        using var scope = factory.Services.CreateScope();
        Assert.Empty(scope.ServiceProvider.GetRequiredService<ApplicationDbContext>().MaintenanceRequests);
    }

    [Fact]
    public async Task Create_RequiresActiveTenancyAndReturnsSafeForbidden()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        var tenant = await AuthenticateAsync(client, "no-lease-create@example.com", UserRole.Tenant);
        var response = await client.PostAsJsonAsync($"/api/maintenance-requests?tenantId={tenant}", CreateRequest());
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        var body = await ParseAsync(response);
        Assert.Contains("active lease", body.RootElement.GetProperty("detail").GetString());
        using var scope = factory.Services.CreateScope();
        Assert.Empty(scope.ServiceProvider.GetRequiredService<ApplicationDbContext>().MaintenanceRequests);
        Assert.Empty(scope.ServiceProvider.GetRequiredService<ApplicationDbContext>().MaintenanceStatusHistories);
    }

    [Fact]
    public async Task Create_WithoutTitleReturnsStableReferenceAndStringAccessAcrossApiReads()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        var tenant = await AuthenticateAsync(client, "new-contract@example.com", UserRole.Tenant);
        var landlord = await SeedUserAsync(factory, "new-contract-landlord@example.com", UserRole.Landlord);
        var property = await SeedPropertyWithLeaseAsync(factory, landlord, tenant);
        var response = await client.PostAsJsonAsync($"/api/maintenance-requests?tenantId={tenant}", new { propertyId = property, description = "The A/C is rattling. It happens at night.", category = 7, priority = 2, preferredAccessWindow = "Evening" });
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var created = (await ParseAsync(response)).RootElement;
        Assert.Equal("The A/C is rattling", created.GetProperty("title").GetString());
        Assert.Equal("Evening", created.GetProperty("preferredAccessWindow").GetString());
        var reference = created.GetProperty("referenceCode").GetString();
        Assert.Matches("^MR-[A-F0-9]{16}$", reference!);
        var id = created.GetProperty("id").GetGuid();
        var detail = (await ParseAsync(await client.GetAsync($"/api/maintenance-requests/{id}"))).RootElement;
        var summary = (await ParseAsync(await client.GetAsync($"/api/maintenance-requests/tenant/{tenant}"))).RootElement[0];
        Assert.Equal(reference, detail.GetProperty("referenceCode").GetString());
        Assert.Equal(reference, summary.GetProperty("referenceCode").GetString());
        Assert.Equal("Evening", summary.GetProperty("preferredAccessWindow").GetString());
    }

    [Fact]
    public async Task GetById_WithoutToken_ReturnsUnauthorized()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();

        var response = await client.GetAsync($"/api/maintenance-requests/{Guid.NewGuid()}");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Create_WithWrongRole_ReturnsForbidden()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        await AuthenticateAsync(client, "landlord-create@example.com", UserRole.Landlord);

        var response = await client.PostAsJsonAsync(
            "/api/maintenance-requests",
            CreateRequest());

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task Create_UsesAuthenticatedTenantIdentity()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        var tenantId = await AuthenticateAsync(client, "tenant-create@example.com", UserRole.Tenant);
        var request = CreateRequest();
        request.PropertyId = await SeedPropertyWithLeaseAsync(factory, Guid.NewGuid(), tenantId);

        var response = await client.PostAsJsonAsync(
            "/api/maintenance-requests",
            request);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var body = await ParseAsync(response);
        Assert.Equal(tenantId, body.RootElement.GetProperty("tenantId").GetGuid());
    }

    [Fact]
    public async Task Create_WithAnotherTenantQueryId_ReturnsForbidden()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        await AuthenticateAsync(client, "tenant-spoof@example.com", UserRole.Tenant);

        var response = await client.PostAsJsonAsync(
            $"/api/maintenance-requests?tenantId={Guid.NewGuid()}",
            CreateRequest());

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task GetById_ForAnotherTenantRequest_ReturnsNotFound()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        await AuthenticateAsync(client, "tenant-idor@example.com", UserRole.Tenant);
        var requestId = await SeedRequestAsync(factory, tenantId: Guid.NewGuid());

        var response = await client.GetAsync($"/api/maintenance-requests/{requestId}");

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task GetByTechnician_UsesAuthenticatedTechnicianIdentity()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        var technicianId = await AuthenticateAsync(
            client,
            "technician-worklist@example.com",
            UserRole.MaintenanceTechnician,
            factory);

        var requestId = await SeedRequestAsync(
            factory,
            tenantId: Guid.NewGuid(),
            status: MaintenanceRequestStatus.Assigned,
            technicianId: technicianId);

        var response = await client.GetAsync($"/api/maintenance-requests/technician/{technicianId}");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await ParseAsync(response);
        Assert.Equal(1, body.RootElement.GetArrayLength());
        Assert.Equal(requestId, body.RootElement[0].GetProperty("id").GetGuid());
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task GetById_TenantReceivesOnlyAssignedTechnicianDisplayName(bool assigned)
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        var tenantId = await AuthenticateAsync(client, "tenant-display-name@example.com", UserRole.Tenant);
        const string privateEmail = "private-technician@example.com";
        const string privatePhone = "+94779998888";
        var technicianId = await SeedUserAsync(factory, privateEmail, UserRole.MaintenanceTechnician);
        using (var scope = factory.Services.CreateScope())
        {
            var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            var technician = await context.Users.SingleAsync(user => user.Id == technicianId);
            technician.FullName = " Mike Reyes ";
            technician.PhoneNumber = privatePhone;
            await context.SaveChangesAsync();
        }
        var requestId = await SeedRequestAsync(factory, tenantId,
            assigned ? MaintenanceRequestStatus.Assigned : MaintenanceRequestStatus.Submitted,
            assigned ? technicianId : null);

        var response = await client.GetAsync($"/api/maintenance-requests/{requestId}");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var json = await response.Content.ReadAsStringAsync();
        using var body = JsonDocument.Parse(json);
        Assert.Equal(assigned ? "Mike Reyes" : null,
            body.RootElement.GetProperty("assignedTechnicianName").GetString());
        Assert.DoesNotContain(privateEmail, json);
        Assert.DoesNotContain(privatePhone, json);
        var allowedFields = new[]
        {
            "id", "referenceCode", "preferredAccessWindow", "propertyId", "tenantId", "technicianId",
            "assignedTechnicianName", "assignedTechnicianContactPhone", "title", "description", "category", "priority", "status",
            "tenantAccessNotes", "triageNotes", "assignmentNotes", "cancellationReason",
            "completedAt", "createdAt", "updatedAt"
        };
        Assert.Equal(allowedFields.OrderBy(name => name),
            body.RootElement.EnumerateObject().Select(property => property.Name).OrderBy(name => name));
    }

    [Fact]
    public async Task GetById_DoesNotProjectNonTechnicianAccountIdentity()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        var tenantId = await AuthenticateAsync(client, "tenant-wrong-assignment@example.com", UserRole.Tenant);
        var otherUserId = await SeedUserAsync(factory, "unrelated-account@example.com", UserRole.Tenant);
        var requestId = await SeedRequestAsync(factory, tenantId, MaintenanceRequestStatus.Assigned, otherUserId);

        var response = await client.GetAsync($"/api/maintenance-requests/{requestId}");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var body = await ParseAsync(response);
        Assert.Equal(JsonValueKind.Null, body.RootElement.GetProperty("assignedTechnicianName").ValueKind);
    }

    [Fact]
    public async Task GetByTechnician_WithAnotherTechnicianId_ReturnsForbidden()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        await AuthenticateAsync(client, "technician-forbidden@example.com", UserRole.MaintenanceTechnician, factory);

        var response = await client.GetAsync($"/api/maintenance-requests/technician/{Guid.NewGuid()}");

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task GetTechnicians_WithoutToken_ReturnsUnauthorized()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();

        var response = await client.GetAsync("/api/maintenance-requests/technicians");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task GetTechnicians_WithTenantRole_ReturnsForbidden()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        await AuthenticateAsync(client, "tenant-technician-directory@example.com", UserRole.Tenant);

        var response = await client.GetAsync("/api/maintenance-requests/technicians");

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Theory]
    [InlineData(UserRole.Landlord)]
    [InlineData(UserRole.Admin)]
    public async Task GetTechnicians_ReturnsOnlyActiveTechnicianChoices(UserRole role)
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        await AuthenticateAsync(client, $"directory-{role.ToString().ToLowerInvariant()}@example.com", role, factory);
        var activeTechnicianId = await SeedUserAsync(
            factory,
            "active-directory-technician@example.com",
            UserRole.MaintenanceTechnician);
        await SeedUserAsync(
            factory,
            "inactive-directory-technician@example.com",
            UserRole.MaintenanceTechnician,
            isActive: false);
        await SeedUserAsync(factory, "directory-tenant@example.com", UserRole.Tenant);

        var response = await client.GetAsync("/api/maintenance-requests/technicians");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var body = await ParseAsync(response);
        var choice = Assert.Single(body.RootElement.EnumerateArray());
        Assert.Equal(activeTechnicianId, choice.GetProperty("id").GetGuid());
        Assert.Equal("Maintenance Technician", choice.GetProperty("name").GetString());
        Assert.Equal(
            new[] { "id", "name" },
            choice.EnumerateObject().Select(property => property.Name).OrderBy(name => name));
    }

    [Fact]
    public async Task GetMyTenantProperties_ReturnsOnlyVerifiedCurrentActiveOccupancy()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        var tenantId = await AuthenticateAsync(client, "property-tenant@example.com", UserRole.Tenant);
        using var landlordClient = factory.CreateHttpsClient();
        var landlordId = await AuthenticateAsync(
            landlordClient,
            "property-landlord@example.com",
            UserRole.Landlord,
            factory);
        using var otherTenantClient = factory.CreateHttpsClient();
        var otherTenantId = await AuthenticateAsync(
            otherTenantClient,
            "property-other-tenant@example.com",
            UserRole.Tenant);

        var occupiedPropertyId = await SeedPropertyWithLeaseAsync(
            factory,
            landlordId,
            leaseTenantId: tenantId);
        var pendingPropertyId = await SeedPropertyWithLeaseAsync(
            factory,
            landlordId,
            leaseTenantId: tenantId,
            leaseStatus: LeaseAgreementStatus.Pending);
        var expiredPropertyId = await SeedPropertyWithLeaseAsync(
            factory,
            landlordId,
            leaseTenantId: tenantId,
            currentlyInTerm: false);
        var otherTenantPropertyId = await SeedPropertyWithLeaseAsync(
            factory,
            landlordId,
            leaseTenantId: otherTenantId);
        var inconsistentPropertyId = await SeedPropertyWithLeaseAsync(
            factory,
            landlordId,
            leaseTenantId: tenantId,
            offerTenantId: otherTenantId);

        var response = await client.GetAsync(
            $"/api/properties/tenant/mine?tenantId={otherTenantId}");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var body = await ParseAsync(response);
        var returnedProperties = body.RootElement.EnumerateArray().ToArray();
        var property = Assert.Single(returnedProperties);
        var returnedPropertyId = property.GetProperty("id").GetGuid();
        Assert.Equal(occupiedPropertyId, returnedPropertyId);
        Assert.DoesNotContain(pendingPropertyId, returnedProperties
            .Select(property => property.GetProperty("id").GetGuid()));
        Assert.DoesNotContain(expiredPropertyId, returnedProperties
            .Select(property => property.GetProperty("id").GetGuid()));
        Assert.DoesNotContain(otherTenantPropertyId, returnedProperties
            .Select(property => property.GetProperty("id").GetGuid()));
        Assert.DoesNotContain(inconsistentPropertyId, returnedProperties
            .Select(property => property.GetProperty("id").GetGuid()));
        Assert.Equal(occupiedPropertyId, property.GetProperty("id").GetGuid());
        Assert.Equal(landlordId, property.GetProperty("landlordId").GetGuid());
        Assert.Equal("Current occupied property", property.GetProperty("title").GetString());
        Assert.True(property.TryGetProperty("amenities", out _));
    }

    [Fact]
    public async Task GetMyTenantProperties_WithoutToken_ReturnsUnauthorized()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();

        var response = await client.GetAsync("/api/properties/tenant/mine");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task GetMyTenantProperties_WithLandlordRole_ReturnsForbidden()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        await AuthenticateAsync(client, "property-role-landlord@example.com", UserRole.Landlord);

        var response = await client.GetAsync("/api/properties/tenant/mine");

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task SubmitEstimate_WithTenantRole_ReturnsForbidden()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        await AuthenticateAsync(client, "tenant-estimate@example.com", UserRole.Tenant);

        var response = await client.PostAsJsonAsync(
            $"/api/maintenance-requests/{Guid.NewGuid()}/estimates",
            new SubmitRepairEstimateDto { LaborCost = 25m });

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task SubmitEstimate_UsesAuthenticatedTechnicianIdentity()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        var technicianId = await AuthenticateAsync(
            client,
            "technician-submit@example.com",
            UserRole.MaintenanceTechnician,
            factory);
        var requestId = await SeedRequestAsync(
            factory,
            status: MaintenanceRequestStatus.EstimatePending,
            technicianId: technicianId);

        var response = await client.PostAsJsonAsync(
            $"/api/maintenance-requests/{requestId}/estimates",
            new SubmitRepairEstimateDto { LaborCost = 25m, PartsCost = 10m });

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var body = await ParseAsync(response);
        Assert.Equal(technicianId, body.RootElement.GetProperty("technicianId").GetGuid());
    }

    [Fact]
    public async Task Triage_WithTenantRole_ReturnsForbidden()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        await AuthenticateAsync(client, "tenant-triage@example.com", UserRole.Tenant);

        var response = await client.PatchAsJsonAsync(
            $"/api/maintenance-requests/{Guid.NewGuid()}/triage",
            new TriageMaintenanceRequestDto
            {
                Category = MaintenanceCategory.Plumbing,
                Priority = MaintenancePriority.High
            });

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task ApproveEstimate_UsesAuthenticatedLandlordIdentity()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        var landlordId = await AuthenticateAsync(client, "landlord-approve@example.com", UserRole.Landlord);
        var estimate = await SeedSubmittedEstimateAsync(factory, landlordId);

        var response = await client.PatchAsJsonAsync(
            $"/api/maintenance-requests/{estimate.RequestId}/estimates/{estimate.EstimateId}/approve",
            new ReviewRepairEstimateDto { ReviewNotes = "Approved." });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        using var scope = factory.Services.CreateScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var stored = await dbContext.RepairEstimates.SingleAsync(item => item.Id == estimate.EstimateId);
        Assert.Equal(landlordId, stored.ReviewedByUserId);
    }

    public static IEnumerable<object[]> LandlordScopedEndpoints()
    {
        foreach (var route in new[] { "", "/history", "/estimates", "/estimates/latest",
            "/coordination-analysis", "/coordination-workflows", "/coordination-workflows/latest", "/triage", "/assign-technician",
            "/estimate-pending", "/estimates/ESTIMATE/approve", "/estimates/ESTIMATE/reject",
            "/estimates/ESTIMATE/request-revision", "/coordination-workflows/WORKFLOW",
            "/coordination-workflows/WORKFLOW/approve", "/coordination-workflows/WORKFLOW/reject" })
            yield return [route];
    }

    [Theory]
    [MemberData(nameof(LandlordScopedEndpoints))]
    public async Task OtherLandlord_CannotReadActOrAnalyzeProperty(string suffix)
    {
        var agent = new SafeMaintenanceAgent();
        using var factory = new AuthApiFactory { MaintenanceCoordinationAgentClient = agent };
        using var ownerClient = factory.CreateHttpsClient();
        var owner = await AuthenticateAsync(ownerClient, "owner-scope@example.com", UserRole.Landlord);
        using var otherClient = factory.CreateHttpsClient();
        await AuthenticateAsync(otherClient, "other-scope@example.com", UserRole.Landlord);
        var requestId = await SeedRequestAsync(factory);
        Guid propertyId;
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            var request = await db.MaintenanceRequests.SingleAsync(item => item.Id == requestId);
            var property = new Property { LandlordId = owner, Title = "Owned", Address = "Test", City = "Test" };
            db.Properties.Add(property);
            request.PropertyId = property.Id;
            propertyId = property.Id;
            await db.SaveChangesAsync();
        }
        var path = "/api/maintenance-requests/" + requestId + suffix.Replace("ESTIMATE", Guid.NewGuid().ToString()).Replace("WORKFLOW", Guid.NewGuid().ToString());
        HttpResponseMessage response;
        if (suffix is "/coordination-analysis" or "/coordination-workflows")
            response = await otherClient.PostAsync(path, null);
        else if (suffix is "/triage" or "/assign-technician" or "/estimate-pending" || suffix.EndsWith("/approve") || suffix.EndsWith("/reject") || suffix.EndsWith("/request-revision"))
            response = await otherClient.PatchAsJsonAsync(path, new { category = 0, priority = 1, technicianId = Guid.NewGuid(), reviewNotes = "Review", decisionNotes = "Review" });
        else response = await otherClient.GetAsync(path);
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        Assert.Equal(0, agent.Calls);
        Assert.Equal(HttpStatusCode.Forbidden, (await otherClient.GetAsync("/api/maintenance-requests/property/" + propertyId)).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await ownerClient.GetAsync("/api/maintenance-requests/" + requestId)).StatusCode);
    }

    [Theory]
    [InlineData(UserRole.Landlord)]
    [InlineData(UserRole.Admin)]
    public async Task AuthorizedAnalysisAndDecision_PreserveMaintenanceAndReturnSafeDto(UserRole role)
    {
        var agent = new SafeMaintenanceAgent();
        using var factory = new AuthApiFactory { MaintenanceCoordinationAgentClient = agent };
        using var client = factory.CreateHttpsClient();
        var actor = await AuthenticateAsync(client, "authorized-" + role + "@example.com", role, factory);
        var requestId = await SeedRequestAsync(factory);
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            var request = await db.MaintenanceRequests.SingleAsync(item => item.Id == requestId);
            var property = new Property { LandlordId = role == UserRole.Landlord ? actor : Guid.NewGuid(), Title = "Owned", Address = "Test", City = "Test" };
            db.Properties.Add(property);
            request.PropertyId = property.Id;
            await db.SaveChangesAsync();
        }
        Assert.Equal(HttpStatusCode.OK, (await client.PostAsync($"/api/maintenance-requests/{requestId}/coordination-analysis", null)).StatusCode);
        foreach (var decision in new[] { "approve", "reject" })
        {
            var created = await client.PostAsync($"/api/maintenance-requests/{requestId}/coordination-workflows", null);
            Assert.Equal(HttpStatusCode.Created, created.StatusCode);
            using var run = await ParseAsync(created);
            var workflowId = run.RootElement.GetProperty("id").GetGuid();
            var decided = await client.PatchAsJsonAsync($"/api/maintenance-requests/{requestId}/coordination-workflows/{workflowId}/{decision}", new { decisionNotes = "Human review" });
            Assert.Equal(HttpStatusCode.OK, decided.StatusCode);
            using var body = await ParseAsync(decided);
            Assert.False(body.RootElement.TryGetProperty("maintenanceRequest", out _));
            foreach (var step in body.RootElement.GetProperty("steps").EnumerateArray())
                Assert.False(step.TryGetProperty("workflow", out _));
            Assert.NotNull(body.RootElement.GetProperty("finalResultJson").GetString());
        }
        using var storedScope = factory.Services.CreateScope();
        var stored = await storedScope.ServiceProvider.GetRequiredService<ApplicationDbContext>().MaintenanceRequests.SingleAsync(item => item.Id == requestId);
        Assert.Equal(MaintenanceRequestStatus.Submitted, stored.Status);
        Assert.Equal(MaintenanceCategory.Plumbing, stored.Category);
        Assert.Equal(MaintenancePriority.Normal, stored.Priority);
        Assert.Null(stored.TechnicianId);
    }

    [Theory]
    [InlineData("coordination-analysis")]
    [InlineData("coordination-workflows")]
    public async Task TenantCannotUseLandlordAiWorkflow(string action)
    {
        var agent = new SafeMaintenanceAgent();
        using var factory = new AuthApiFactory { MaintenanceCoordinationAgentClient = agent };
        using var client = factory.CreateHttpsClient();
        var tenant = await AuthenticateAsync(client, "tenant-ai@example.com", UserRole.Tenant);
        var request = await SeedRequestAsync(factory, tenantId: tenant);
        Assert.Equal(HttpStatusCode.Forbidden, (await client.PostAsync($"/api/maintenance-requests/{request}/{action}", null)).StatusCode);
        Assert.Equal(0, agent.Calls);
    }

    [Theory]
    [InlineData(UserRole.Landlord)]
    [InlineData(UserRole.Admin)]
    public async Task LatestWorkflow_ReturnsEmptyOrNewestSafeDtoAndPreservesDecisions(UserRole role)
    {
        var agent = new SafeMaintenanceAgent();
        using var factory = new AuthApiFactory { MaintenanceCoordinationAgentClient = agent };
        using var client = factory.CreateHttpsClient();
        var actor = await AuthenticateAsync(client, "latest-" + role + "@example.com", role, factory);
        var requestId = await SeedRequestAsync(factory);
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            var request = await db.MaintenanceRequests.SingleAsync(item => item.Id == requestId);
            var property = new Property { LandlordId = role == UserRole.Landlord ? actor : Guid.NewGuid(), Title = "Owned", Address = "Test", City = "Test" };
            db.Properties.Add(property);
            request.PropertyId = property.Id;
            await db.SaveChangesAsync();
        }
        var path = $"/api/maintenance-requests/{requestId}/coordination-workflows/latest";
        var empty = await client.GetAsync(path);
        Assert.Equal(HttpStatusCode.NoContent, empty.StatusCode);
        Assert.True(empty.Headers.CacheControl?.NoStore);
        var newerId = Guid.Parse("00000000-0000-0000-0000-000000000002");
        var now = DateTimeOffset.UtcNow;
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            db.MaintenanceCoordinationWorkflows.AddRange(
                new MaintenanceCoordinationWorkflow { Id = Guid.Parse("00000000-0000-0000-0000-000000000003"),
                    MaintenanceRequestId = requestId, CreatedAt = now.AddDays(-1), UpdatedAt = now.AddDays(1),
                    Status = MaintenanceCoordinationWorkflowStatus.Completed, ApprovalStatus = MaintenanceCoordinationApprovalStatus.Approved },
                new MaintenanceCoordinationWorkflow { Id = Guid.Parse("00000000-0000-0000-0000-000000000001"),
                    MaintenanceRequestId = requestId, CreatedAt = now, UpdatedAt = now,
                    Status = MaintenanceCoordinationWorkflowStatus.AwaitingHumanReview },
                new MaintenanceCoordinationWorkflow { Id = newerId,
                    MaintenanceRequestId = requestId, CreatedAt = now, UpdatedAt = now,
                    Status = MaintenanceCoordinationWorkflowStatus.Completed, ApprovalStatus = MaintenanceCoordinationApprovalStatus.Approved,
                    RequiresHumanApproval = true, FinalResultJson = "{\"requiresHumanReview\":true}",
                    Steps = [new MaintenanceCoordinationStep { StepOrder = 1, StepName = "Validation", Status = MaintenanceCoordinationStepStatus.Completed }] });
            await db.SaveChangesAsync();
        }
        foreach (var decision in new[] { MaintenanceCoordinationApprovalStatus.Approved, MaintenanceCoordinationApprovalStatus.Rejected })
        {
            using (var scope = factory.Services.CreateScope())
            {
                var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
                var workflow = await db.MaintenanceCoordinationWorkflows.SingleAsync(item => item.Id == newerId);
                workflow.ApprovalStatus = decision;
                workflow.Status = decision == MaintenanceCoordinationApprovalStatus.Approved
                    ? MaintenanceCoordinationWorkflowStatus.Completed : MaintenanceCoordinationWorkflowStatus.Failed;
                await db.SaveChangesAsync();
            }
            using var latest = await client.GetAsync(path);
            Assert.Equal(HttpStatusCode.OK, latest.StatusCode);
            using var body = await ParseAsync(latest);
            Assert.Equal(newerId, body.RootElement.GetProperty("id").GetGuid());
            Assert.Equal(requestId, body.RootElement.GetProperty("maintenanceRequestId").GetGuid());
            Assert.Equal((int)decision, body.RootElement.GetProperty("approvalStatus").GetInt32());
            Assert.False(body.RootElement.TryGetProperty("maintenanceRequest", out _));
            foreach (var step in body.RootElement.GetProperty("steps").EnumerateArray())
                Assert.False(step.TryGetProperty("workflow", out _));
        }
        Assert.Equal(0, agent.Calls);
    }

    [Fact]
    public async Task LatestWorkflow_RejectsTenantAndUnauthenticatedReads()
    {
        using var factory = new AuthApiFactory();
        var request = await SeedRequestAsync(factory);
        using var client = factory.CreateHttpsClient();
        var path = $"/api/maintenance-requests/{request}/coordination-workflows/latest";
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync(path)).StatusCode);
        await AuthenticateAsync(client, "tenant-latest@example.com", UserRole.Tenant);
        Assert.Equal(HttpStatusCode.Forbidden, (await client.GetAsync(path)).StatusCode);
    }

    private sealed class SafeMaintenanceAgent : RentFlow.Api.Services.Interfaces.IMaintenanceCoordinationAgentClient
    {
        public int Calls { get; private set; }
        public Task<MaintenanceCoordinationAgentResponse> AnalyzeAsync(MaintenanceCoordinationAgentRequest request, CancellationToken cancellationToken = default)
        {
            Calls++;
            return Task.FromResult(MaintenanceCoordinationTestData.Response(request));
        }
    }

    private static async Task<Guid> AuthenticateAsync(
        HttpClient client,
        string email,
        UserRole role,
        AuthApiFactory? factory = null)
    {
        HttpResponseMessage response;
        if (role is UserRole.Tenant or UserRole.Landlord)
        {
            response = await client.PostAsJsonAsync("/api/auth/register", new
            {
                fullName = "Maintenance Auth User",
                email,
                phoneNumber = "+94770000000",
                password = ValidPassword,
                role = role.ToString()
            });
        }
        else
        {
            if (factory is null)
            {
                throw new InvalidOperationException("A factory is required to seed privileged users.");
            }

            await SeedUserAsync(factory, email, role);
            response = await client.PostAsJsonAsync("/api/auth/login", new { email, password = ValidPassword });
        }

        Assert.True(response.IsSuccessStatusCode, await response.Content.ReadAsStringAsync());
        var body = await ParseAsync(response);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue(
            "Bearer",
            body.RootElement.GetProperty("accessToken").GetString());
        return body.RootElement.GetProperty("user").GetProperty("id").GetGuid();
    }

    private static async Task<Guid> SeedUserAsync(
        AuthApiFactory factory,
        string email,
        UserRole role,
        bool isActive = true)
    {
        using var scope = factory.Services.CreateScope();
        var services = scope.ServiceProvider;
        var user = new ApplicationUser
        {
            Id = Guid.NewGuid(),
            FullName = role == UserRole.MaintenanceTechnician
                ? "Maintenance Technician"
                : "Maintenance Auth User",
            Email = email,
            NormalizedEmail = AuthService.NormalizeEmail(email),
            PhoneNumber = "+94770000000",
            Role = role,
            IsActive = isActive,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        user.PasswordHash = services
            .GetRequiredService<IPasswordHasher<ApplicationUser>>()
            .HashPassword(user, ValidPassword);
        services.GetRequiredService<ApplicationDbContext>().Users.Add(user);
        await services.GetRequiredService<ApplicationDbContext>().SaveChangesAsync();
        return user.Id;
    }

    private static async Task<Guid> SeedPropertyWithLeaseAsync(
        AuthApiFactory factory,
        Guid landlordId,
        Guid leaseTenantId,
        Guid? offerTenantId = null,
        LeaseAgreementStatus leaseStatus = LeaseAgreementStatus.Active,
        bool currentlyInTerm = true)
    {
        using var scope = factory.Services.CreateScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var tenantIdForOffer = offerTenantId ?? leaseTenantId;
        var property = new Property
        {
            LandlordId = landlordId,
            Title = "Current occupied property",
            Description = "Test property",
            Address = "123 Test Road",
            City = "Test City",
            MonthlyRent = 1000m,
            Bedrooms = 2,
            Bathrooms = 1,
            IsAvailable = false,
            CreatedAt = DateTimeOffset.UtcNow
        };
        var application = new RentalApplication
        {
            TenantId = tenantIdForOffer,
            PropertyId = property.Id,
            MoveInDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(-1)),
            MonthlyIncome = 5000m,
            Occupation = "Test",
            NumberOfOccupants = 1,
            Status = RentalApplicationStatus.Approved
        };
        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var startDate = today.AddDays(currentlyInTerm ? -1 : -30);
        var endDate = today.AddDays(currentlyInTerm ? 30 : -1);
        var offer = new RentalOffer
        {
            RentalApplicationId = application.Id,
            RentalApplication = application,
            TenantId = tenantIdForOffer,
            PropertyId = property.Id,
            MonthlyRent = property.MonthlyRent,
            SecurityDeposit = 1000m,
            ProposedStartDate = startDate,
            ProposedEndDate = endDate,
            ExpiresAt = DateTimeOffset.UtcNow.AddDays(1),
            Status = RentalOfferStatus.Accepted
        };
        var lease = new LeaseAgreement
        {
            RentalOfferId = offer.Id,
            RentalOffer = offer,
            TenantId = leaseTenantId,
            PropertyId = property.Id,
            MonthlyRent = offer.MonthlyRent,
            SecurityDeposit = offer.SecurityDeposit,
            StartDate = offer.ProposedStartDate,
            EndDate = offer.ProposedEndDate,
            Status = leaseStatus,
            CreatedAt = DateTimeOffset.UtcNow
        };

        dbContext.Properties.Add(property);
        dbContext.RentalApplications.Add(application);
        dbContext.RentalOffers.Add(offer);
        dbContext.LeaseAgreements.Add(lease);
        await dbContext.SaveChangesAsync();
        return property.Id;
    }

    private static async Task<Guid> SeedRequestAsync(
        AuthApiFactory factory,
        Guid? tenantId = null,
        MaintenanceRequestStatus status = MaintenanceRequestStatus.Submitted,
        Guid? technicianId = null)
    {
        using var scope = factory.Services.CreateScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var request = new MaintenanceRequest
        {
            Id = Guid.NewGuid(),
            TenantId = tenantId ?? Guid.NewGuid(),
            PropertyId = Guid.NewGuid(),
            TechnicianId = technicianId,
            Title = "Leak",
            Description = "Kitchen tap leak",
            Category = MaintenanceCategory.Plumbing,
            Priority = MaintenancePriority.Normal,
            Status = status,
            CreatedAt = DateTimeOffset.UtcNow
        };
        dbContext.MaintenanceRequests.Add(request);
        await dbContext.SaveChangesAsync();
        return request.Id;
    }

    private static async Task<(Guid RequestId, Guid EstimateId)> SeedSubmittedEstimateAsync(
        AuthApiFactory factory, Guid landlordId)
    {
        using var scope = factory.Services.CreateScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var property = new Property { LandlordId = landlordId, Title = "Owned property", Address = "Test", City = "Test" };
        dbContext.Properties.Add(property);
        var request = new MaintenanceRequest
        {
            Id = Guid.NewGuid(),
            TenantId = Guid.NewGuid(),
            PropertyId = property.Id,
            TechnicianId = Guid.NewGuid(),
            Title = "Estimate review",
            Description = "Review the estimate",
            Category = MaintenanceCategory.Electrical,
            Priority = MaintenancePriority.Normal,
            Status = MaintenanceRequestStatus.AwaitingLandlordApproval,
            CreatedAt = DateTimeOffset.UtcNow
        };
        var estimate = new RepairEstimate
        {
            Id = Guid.NewGuid(),
            MaintenanceRequestId = request.Id,
            TechnicianId = request.TechnicianId!.Value,
            VersionNumber = 1,
            LaborCost = 25m,
            PartsCost = 10m,
            AdditionalCost = 0m,
            TotalCost = 35m,
            Status = RepairEstimateStatus.Submitted,
            CreatedAt = DateTimeOffset.UtcNow,
            SubmittedAt = DateTimeOffset.UtcNow
        };
        dbContext.MaintenanceRequests.Add(request);
        dbContext.RepairEstimates.Add(estimate);
        await dbContext.SaveChangesAsync();
        return (request.Id, estimate.Id);
    }

    private static CreateMaintenanceRequestDto CreateRequest() => new()
    {
        PropertyId = Guid.NewGuid(),
        Title = "Leak",
        Description = "Kitchen tap leak",
        Category = MaintenanceCategory.Plumbing,
        Priority = MaintenancePriority.Normal,
        PreferredAccessWindow = PreferredAccessWindow.Morning
    };

    private static async Task<JsonDocument> ParseAsync(HttpResponseMessage response) =>
        JsonDocument.Parse(await response.Content.ReadAsStringAsync());
}
