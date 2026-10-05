using System.Text.RegularExpressions;
using RentFlow.Api.DTOs.Maintenance;
using RentFlow.Api.Models;

namespace RentFlow.Api.Services;

/// <summary>One bounded, minimum-data projection for both maintenance analysis paths.</summary>
public static partial class MaintenanceCoordinationRequestMapper
{
    public static MaintenanceCoordinationAgentRequest Map(
        MaintenanceRequest request, RepairEstimate? estimate, IEnumerable<MaintenanceAttachment> attachments)
    {
        return new MaintenanceCoordinationAgentRequest
        {
            MaintenanceRequestId = request.Id,
            Title = Redact(request.Title, 200),
            Description = Redact(request.Description, 4000),
            Category = Canonical(request.Category),
            Priority = Canonical(request.Priority),
            CurrentStatus = Canonical(request.Status),
            PreferredAccessWindow = request.PreferredAccessWindow is { } access ? Canonical(access) : null,
            HasAssignedTechnician = request.TechnicianId.HasValue,
            RepairEstimate = estimate is null ? null : new MaintenanceCoordinationEstimate
            {
                VersionNumber = estimate.VersionNumber,
                LaborCost = estimate.LaborCost,
                PartsCost = estimate.PartsCost,
                AdditionalCost = estimate.AdditionalCost,
                TotalCost = estimate.TotalCost,
                Notes = estimate.Notes is null ? null : Redact(estimate.Notes, 4000),
                Status = Canonical(estimate.Status)
            },
            Attachments = attachments.OrderBy(item => item.Id).Take(5).Select(item => new MaintenanceCoordinationAttachment
            {
                AttachmentId = item.Id,
                ContentType = item.ContentType.Trim().ToLowerInvariant(),
                FileSize = item.FileSize
            }).ToArray()
        };
    }

    private static string Canonical<T>(T value) where T : struct, Enum =>
        Enum.IsDefined(value) ? value.ToString() :
            throw MaintenanceRequestServiceException.Validation("Maintenance analysis input contains an invalid domain value.");

    // Best-effort redaction of recognizable contacts/URLs. This is not complete PII detection.
    private static string Redact(string value, int limit)
    {
        var bounded = value.Trim();
        if (bounded.Length > limit) bounded = bounded[..limit];
        bounded = EmailPattern().Replace(bounded, "[redacted]");
        bounded = UrlPattern().Replace(bounded, "[redacted]");
        bounded = PhonePattern().Replace(bounded, "[redacted]");
        return bounded.Length <= limit ? bounded : bounded[..limit];
    }

    [GeneratedRegex(@"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", RegexOptions.IgnoreCase)]
    private static partial Regex EmailPattern();
    [GeneratedRegex(@"(?:https?://|www\.)[^\s<>]+", RegexOptions.IgnoreCase)]
    private static partial Regex UrlPattern();
    [GeneratedRegex(@"(?<!\w)\+?\d[\d ()-]{5,}\d(?!\w)")]
    private static partial Regex PhonePattern();
}
