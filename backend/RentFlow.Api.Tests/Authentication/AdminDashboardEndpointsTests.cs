using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using RentFlow.Api.Configuration;
using RentFlow.Api.Controllers;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
using Xunit;

namespace RentFlow.Api.Tests.Authentication;

public sealed class AdminDashboardEndpointsTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-10-06T10:00:00Z");
    private sealed class Clock : TimeProvider { public override DateTimeOffset GetUtcNow() => Now; }

    [Theory]
    [InlineData("summary")] [InlineData("activity")] [InlineData("workflows")] [InlineData("health")]
    public async Task ReportsRequireActiveAdmin(string report)
    {
        using var factory = new AuthApiFactory(new Clock());
        using var anonymous = factory.CreateHttpsClient();
        var path = $"/api/admin/dashboard/{report}";
        Assert.Equal(HttpStatusCode.Unauthorized, (await anonymous.GetAsync(path)).StatusCode);
        foreach (var role in new[] { UserRole.Tenant, UserRole.Landlord, UserRole.MaintenanceTechnician })
        {
            using var denied = Client(factory, Guid.NewGuid(), role);
            Assert.Equal(HttpStatusCode.Forbidden, (await denied.GetAsync(path)).StatusCode);
        }
        var id = Guid.NewGuid(); using var stale = Client(factory, id, UserRole.Admin);
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            (await db.Users.FindAsync(id))!.IsActive = false; await db.SaveChangesAsync();
        }
        Assert.Equal(HttpStatusCode.Unauthorized, (await stale.GetAsync(path)).StatusCode);
    }

    [Fact]
    public async Task SummaryUsesActiveApplicationsAndCompletedPaymentsInsideSriLankanMonth()
    {
        using var factory = new AuthApiFactory(new Clock()); using var admin = Client(factory, Guid.NewGuid(), UserRole.Admin);
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            db.Properties.AddRange(new Property { Title = "One" }, new Property { Title = "Two" });
            foreach (var status in Enum.GetValues<RentalApplicationStatus>()) db.RentalApplications.Add(new RentalApplication { Status = status });
            db.Payments.AddRange(
                new Payment { Amount = 100, Status = PaymentStatus.Completed, PaidAt = DateTimeOffset.Parse("2026-09-30T18:29:59Z") },
                new Payment { Amount = 200, Status = PaymentStatus.Completed, PaidAt = DateTimeOffset.Parse("2026-09-30T18:30:00Z") },
                new Payment { Amount = 300, Status = PaymentStatus.Completed, PaidAt = DateTimeOffset.Parse("2026-10-31T18:30:00Z") },
                new Payment { Amount = 400, Status = PaymentStatus.Pending, PaidAt = Now },
                new Payment { Amount = 500, Status = PaymentStatus.Failed, PaidAt = Now });
            await db.SaveChangesAsync();
        }
        var summary = await admin.GetFromJsonAsync<AdminDashboardSummary>("/api/admin/dashboard/summary");
        Assert.Equal(new AdminDashboardSummary(2, 3, 200, "2026-10"), summary);
    }

    [Fact]
    public async Task WorkflowsSeparatePricingCompletedFromAwaitingReviewAndActivityIsBounded()
    {
        using var factory = new AuthApiFactory(new Clock()); using var admin = Client(factory, Guid.NewGuid(), UserRole.Admin);
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            db.ApplicationValidationWorkflows.Add(new ApplicationValidationWorkflow { Status = ApplicationValidationWorkflowStatus.AwaitingHumanReview });
            db.PricingAnalysisWorkflows.Add(new PricingAnalysisWorkflow { Status = PricingAnalysisWorkflowStatus.Completed });
            db.MaintenanceCoordinationWorkflows.Add(new MaintenanceCoordinationWorkflow { Status = MaintenanceCoordinationWorkflowStatus.Failed });
            for (var i = 0; i < 15; i++) db.Properties.Add(new Property { Title = $"Home {i}", CreatedAt = Now.AddMinutes(i) });
            await db.SaveChangesAsync();
        }
        var reports = (await admin.GetFromJsonAsync<List<AdminWorkflowTotals>>("/api/admin/dashboard/workflows"))!;
        Assert.Equal(1, reports[0].AwaitingReview); Assert.Equal(1, reports[1].Completed); Assert.Equal(0, reports[1].AwaitingReview);
        Assert.Equal(1, reports[2].Failed);
        var activity = (await admin.GetFromJsonAsync<List<AdminActivity>>("/api/admin/dashboard/activity"))!;
        Assert.Equal(10, activity.Count); Assert.Equal("Home 14", activity[0].Description);
        Assert.True(activity.Zip(activity.Skip(1)).All(pair => pair.First.OccurredAt >= pair.Second.OccurredAt));
        var nextPage = (await admin.GetFromJsonAsync<List<AdminActivity>>("/api/admin/dashboard/activity?page=2&pageSize=10"))!;
        Assert.Equal(5, nextPage.Count); Assert.Equal("Home 4", nextPage[0].Description);
        Assert.Empty(activity.Select(item => item.Description).Intersect(nextPage.Select(item => item.Description)));
        Assert.Equal(HttpStatusCode.BadRequest, (await admin.GetAsync("/api/admin/dashboard/activity?page=0")).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await admin.GetAsync("/api/admin/dashboard/activity?pageSize=51")).StatusCode);
    }

    [Theory]
    [InlineData("healthy", "available")] [InlineData("failed", "unavailable")]
    public async Task HealthUsesActualAgentResponse(string responseStatus, string expected)
    {
        await using var db = new ApplicationDbContext(new DbContextOptionsBuilder<ApplicationDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        var controller = new AdminDashboardController(db, new Clock(), new HttpFactory(responseStatus), Options.Create(new AgentServiceOptions()));
        var result = await controller.Health(CancellationToken.None);
        var health = Assert.IsType<AdminHealth>(Assert.IsType<OkObjectResult>(result.Result).Value);
        Assert.Equal(Now, health.CheckedAt); Assert.Equal(expected, health.Services.Single(item => item.Name == "AI agent").Status);
    }

    private sealed class HttpFactory(string status) : IHttpClientFactory
    {
        public HttpClient CreateClient(string name) => new(new Handler(status));
    }
    private sealed class Handler(string status) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(new { status }) });
    }
    private static HttpClient Client(AuthApiFactory factory, Guid id, UserRole role)
    {
        factory.EnsureActiveUser(id, role); var client = factory.CreateHttpsClient();
        var token = new JwtSecurityToken(issuer: "RentFlow.Api.Tests", audience: "RentFlow.TestClients",
            claims: [new Claim(JwtRegisteredClaimNames.Sub, id.ToString()), new Claim("role", role.ToString()), new Claim("token_version", "0")],
            expires: DateTime.UtcNow.AddMinutes(10), signingCredentials: new SigningCredentials(new SymmetricSecurityKey(Encoding.UTF8.GetBytes("test-only-signing-key-that-is-at-least-32-bytes-long")), SecurityAlgorithms.HmacSha256));
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", new JwtSecurityTokenHandler().WriteToken(token)); return client;
    }
}
