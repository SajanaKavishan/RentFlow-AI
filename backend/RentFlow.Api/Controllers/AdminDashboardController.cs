using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using RentFlow.Api.Authorization;
using RentFlow.Api.Configuration;
using RentFlow.Api.Data;
using RentFlow.Api.Models;

namespace RentFlow.Api.Controllers;

[ApiController]
[Route("api/admin/dashboard")]
[Authorize(Policy = AuthorizationPolicies.ActiveAdmin)]
public sealed class AdminDashboardController(ApplicationDbContext db, TimeProvider clock,
    IHttpClientFactory http, IOptions<AgentServiceOptions> agentOptions) : ControllerBase
{
    [HttpGet("summary")]
    public async Task<ActionResult<AdminDashboardSummary>> Summary(CancellationToken ct)
    {
        var local = clock.GetUtcNow().ToOffset(TimeSpan.FromHours(5.5));
        var start = new DateTimeOffset(local.Year, local.Month, 1, 0, 0, 0, local.Offset).ToUniversalTime();
        var end = start.ToOffset(local.Offset).AddMonths(1).ToUniversalTime();
        var properties = await db.Properties.CountAsync(ct);
        var active = await db.RentalApplications.CountAsync(a => a.Status == RentalApplicationStatus.Submitted ||
            a.Status == RentalApplicationStatus.UnderReview || a.Status == RentalApplicationStatus.ChangesRequested, ct);
        var volume = await db.Payments.Where(p => p.Status == PaymentStatus.Completed && p.PaidAt >= start && p.PaidAt < end)
            .SumAsync(p => (decimal?)p.Amount, ct) ?? 0;
        return Ok(new AdminDashboardSummary(properties, active, volume, local.ToString("yyyy-MM")));
    }

    [HttpGet("activity")]
    public async Task<ActionResult<IReadOnlyList<AdminActivity>>> Activity(CancellationToken ct, [FromQuery] int page = 1, [FromQuery] int pageSize = 10)
    {
        if (page < 1 || page > 10000 || pageSize < 1 || pageSize > 50) return BadRequest();
        var properties = db.Properties.AsNoTracking().Select(p => new { p.Id, Kind = "Property listed", Description = p.Title, OccurredAt = p.CreatedAt });
        var applications = db.RentalApplications.AsNoTracking().Select(a => new { a.Id, Kind = "Application created", Description = "Rental application received", OccurredAt = a.CreatedAt });
        var maintenance = db.MaintenanceRequests.AsNoTracking().Select(r => new { r.Id, Kind = "Maintenance requested", Description = r.Title, OccurredAt = r.CreatedAt });
        var payments = db.Payments.AsNoTracking().Where(p => p.Status == PaymentStatus.Completed && p.PaidAt != null)
            .Select(p => new { p.Id, Kind = "Payment completed", Description = "Rent payment recorded", OccurredAt = p.PaidAt!.Value });
        var items = await properties.Concat(applications).Concat(maintenance).Concat(payments)
            .OrderByDescending(item => item.OccurredAt).ThenByDescending(item => item.Id).ThenBy(item => item.Kind)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(item => new AdminActivity(item.Kind, item.Description, item.OccurredAt)).ToListAsync(ct);
        return Ok(items);
    }

    [HttpGet("workflows")]
    public async Task<ActionResult<IReadOnlyList<AdminWorkflowTotals>>> Workflows(CancellationToken ct)
    {
        var validation = await WorkflowTotals("Application validation", db.ApplicationValidationWorkflows.Select(w => (int)w.Status), 3, 4, 2, ct);
        var pricing = await WorkflowTotals("Pricing analysis", db.PricingAnalysisWorkflows.Select(w => (int)w.Status), 2, 3, null, ct);
        var maintenance = await WorkflowTotals("Maintenance coordination", db.MaintenanceCoordinationWorkflows.Select(w => (int)w.Status), 3, 4, 2, ct);
        return Ok(new[] { validation, pricing, maintenance });
    }

    private static async Task<AdminWorkflowTotals> WorkflowTotals(string name, IQueryable<int> statuses, int completed, int failed, int? review, CancellationToken ct)
    {
        var counts = await statuses.GroupBy(status => status).Select(group => new { Status = group.Key, Count = group.Count() })
            .ToDictionaryAsync(group => group.Status, group => group.Count, ct);
        return new(name, counts.Values.Sum(), counts.GetValueOrDefault(0), counts.GetValueOrDefault(1),
            review.HasValue ? counts.GetValueOrDefault(review.Value) : 0, counts.GetValueOrDefault(completed), counts.GetValueOrDefault(failed));
    }

    [HttpGet("health")]
    public async Task<ActionResult<AdminHealth>> Health(CancellationToken ct)
    {
        var services = new List<AdminServiceHealth> { new("RentFlow API", "available", "Responding to this health request") };
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TimeSpan.FromSeconds(5));
        try
        {
            var connected = await db.Database.CanConnectAsync(timeout.Token);
            services.Add(new("Database", connected ? "available" : "unavailable", "Database connectivity check"));
        }
        catch (Exception) when (!ct.IsCancellationRequested) { services.Add(new("Database", "unavailable", "Database connectivity check failed")); }
        using var agentTimeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        agentTimeout.CancelAfter(TimeSpan.FromSeconds(5));
        try
        {
            using var client = http.CreateClient();
            var url = new Uri(new Uri(agentOptions.Value.BaseUrl.TrimEnd('/') + "/"), "health");
            using var response = await client.GetAsync(url, agentTimeout.Token);
            var result = response.IsSuccessStatusCode ? await response.Content.ReadFromJsonAsync<Dictionary<string, string>>(agentTimeout.Token) : null;
            var healthy = result?.GetValueOrDefault("status") == "healthy";
            services.Add(new("AI agent", healthy ? "available" : "unavailable", "Service reachability only; model readiness is not checked"));
        }
        catch (Exception) when (!ct.IsCancellationRequested) { services.Add(new("AI agent", "unavailable", "Agent health endpoint could not be reached")); }
        return Ok(new AdminHealth(clock.GetUtcNow(), services));
    }
}

public sealed record AdminDashboardSummary(int PropertyCount, int ActiveApplicationCount, decimal MonthlyVolume, string Month);
public sealed record AdminActivity(string Kind, string Description, DateTimeOffset OccurredAt);
public sealed record AdminWorkflowTotals(string Name, int Total, int Pending, int Running, int AwaitingReview, int Completed, int Failed);
public sealed record AdminServiceHealth(string Name, string Status, string Detail);
public sealed record AdminHealth(DateTimeOffset CheckedAt, IReadOnlyList<AdminServiceHealth> Services);
