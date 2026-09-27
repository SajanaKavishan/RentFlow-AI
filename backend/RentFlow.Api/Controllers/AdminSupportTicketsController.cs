using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Authorization;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.SupportTickets;
using RentFlow.Api.Models;

namespace RentFlow.Api.Controllers;

[ApiController]
[Route("api/admin/support-tickets")]
[Authorize(Policy = AuthorizationPolicies.ActiveAdmin)]
public sealed class AdminSupportTicketsController(
    ApplicationDbContext dbContext,
    TimeProvider timeProvider) : ControllerBase
{
    private const int DefaultPageSize = 20;
    private const int MaximumPageSize = 100;
    private const int MaximumSearchLength = 320;

    [HttpGet]
    public async Task<ActionResult<AdminSupportTicketPageDto>> GetPage(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = DefaultPageSize,
        [FromQuery] string? status = null,
        [FromQuery] string? category = null,
        [FromQuery] string? search = null,
        CancellationToken cancellationToken = default)
    {
        if (page < 1 || pageSize is < 1 or > MaximumPageSize)
        {
            return InvalidQuery(
                $"Page must be at least 1 and pageSize must be between 1 and {MaximumPageSize}.");
        }

        if (!TryParseOptionalEnum(status, out SupportTicketStatus? statusFilter))
        {
            return InvalidQuery(
                $"Status must be one of: {string.Join(", ", Enum.GetNames<SupportTicketStatus>())}.");
        }

        if (!TryParseOptionalEnum(category, out SupportTicketCategory? categoryFilter))
        {
            return InvalidQuery(
                $"Category must be one of: {string.Join(", ", Enum.GetNames<SupportTicketCategory>())}.");
        }

        var trimmedSearch = search?.Trim();
        if (trimmedSearch?.Length > MaximumSearchLength)
        {
            return InvalidQuery($"Search must not exceed {MaximumSearchLength} characters.");
        }

        var query =
            from ticket in dbContext.SupportTickets.AsNoTracking()
            join user in dbContext.Users.AsNoTracking() on ticket.UserId equals user.Id
            select new
            {
                Ticket = ticket,
                RequesterFullName = user.FullName,
                RequesterEmail = user.Email,
                user.NormalizedEmail
            };

        if (statusFilter is not null)
        {
            query = query.Where(item => item.Ticket.Status == statusFilter.Value);
        }

        if (categoryFilter is not null)
        {
            query = query.Where(item => item.Ticket.Category == categoryFilter.Value);
        }

        if (!string.IsNullOrEmpty(trimmedSearch))
        {
            var normalizedSearch = trimmedSearch.ToUpperInvariant();
            query = query.Where(item =>
                item.Ticket.Subject.ToUpper().Contains(normalizedSearch)
                || item.RequesterFullName.ToUpper().Contains(normalizedSearch)
                || item.NormalizedEmail.Contains(normalizedSearch));
        }

        var totalCount = await query.CountAsync(cancellationToken);
        var totalPages = totalCount == 0
            ? 0
            : (int)Math.Ceiling(totalCount / (double)pageSize);
        var skip = ((long)page - 1) * pageSize;

        IReadOnlyList<AdminSupportTicketListItemDto> items;
        if (skip >= totalCount)
        {
            items = [];
        }
        else
        {
            var records = await query
                .OrderByDescending(item => item.Ticket.CreatedAt)
                .ThenByDescending(item => item.Ticket.Id)
                .Skip((int)skip)
                .Take(pageSize)
                .ToListAsync(cancellationToken);

            items = records.Select(item => new AdminSupportTicketListItemDto(
                item.Ticket.Id,
                item.Ticket.Category.ToString(),
                item.Ticket.Subject,
                item.Ticket.Status.ToString(),
                item.Ticket.CreatedAt,
                item.RequesterFullName,
                item.RequesterEmail)).ToList();
        }

        return Ok(new AdminSupportTicketPageDto
        {
            Items = items,
            Pagination = new AdminSupportTicketPaginationDto
            {
                Page = page,
                PageSize = pageSize,
                TotalCount = totalCount,
                TotalPages = totalPages,
                HasNextPage = page < totalPages,
                HasPreviousPage = page > 1 && totalPages > 0
            }
        });
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<AdminSupportTicketDetailDto>> GetById(
        Guid id,
        CancellationToken cancellationToken)
    {
        var record = await (
            from ticket in dbContext.SupportTickets.AsNoTracking()
            join user in dbContext.Users.AsNoTracking() on ticket.UserId equals user.Id
            where ticket.Id == id
            select new
            {
                Ticket = ticket,
                RequesterFullName = user.FullName,
                RequesterEmail = user.Email
            }).SingleOrDefaultAsync(cancellationToken);

        return record is null
            ? NotFound(new { message = "Support ticket was not found." })
            : Ok(ToDetail(record.Ticket, record.RequesterFullName, record.RequesterEmail));
    }

    [HttpPatch("{id:guid}/status")]
    public async Task<ActionResult<AdminSupportTicketStatusResponseDto>> UpdateStatus(
        Guid id,
        UpdateSupportTicketStatusRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!TryParseExactEnum(request.Status, out SupportTicketStatus requestedStatus))
        {
            return InvalidStatus(
                $"Status must be one of: {string.Join(", ", Enum.GetNames<SupportTicketStatus>())}.");
        }

        var ticket = await dbContext.SupportTickets
            .SingleOrDefaultAsync(item => item.Id == id, cancellationToken);
        if (ticket is null)
        {
            return NotFound(new { message = "Support ticket was not found." });
        }

        if (!IsAllowedTransition(ticket.Status, requestedStatus))
        {
            return Conflict(new ProblemDetails
            {
                Status = StatusCodes.Status409Conflict,
                Title = "Invalid support ticket status transition.",
                Detail = $"A support ticket cannot transition from {ticket.Status} to {requestedStatus}."
            });
        }

        ticket.Status = requestedStatus;
        ticket.UpdatedAt = timeProvider.GetUtcNow();
        await dbContext.SaveChangesAsync(cancellationToken);

        return Ok(new AdminSupportTicketStatusResponseDto(
            ticket.Id,
            ticket.Status.ToString(),
            ticket.UpdatedAt));
    }

    private static bool IsAllowedTransition(
        SupportTicketStatus current,
        SupportTicketStatus requested) =>
        current == SupportTicketStatus.Open
            && requested is SupportTicketStatus.InProgress or SupportTicketStatus.Resolved
        || current == SupportTicketStatus.InProgress
            && requested == SupportTicketStatus.Resolved;

    private static bool TryParseOptionalEnum<TEnum>(string? value, out TEnum? parsed)
        where TEnum : struct, Enum
    {
        var trimmed = value?.Trim();
        if (string.IsNullOrEmpty(trimmed))
        {
            parsed = null;
            return true;
        }

        if (TryParseExactEnum(trimmed, out TEnum result))
        {
            parsed = result;
            return true;
        }

        parsed = null;
        return false;
    }

    private static bool TryParseExactEnum<TEnum>(string value, out TEnum parsed)
        where TEnum : struct, Enum =>
        Enum.TryParse(value, ignoreCase: false, out parsed)
        && Enum.IsDefined(parsed)
        && value == parsed.ToString();

    private BadRequestObjectResult InvalidQuery(string detail) => BadRequest(new ProblemDetails
    {
        Status = StatusCodes.Status400BadRequest,
        Title = "Invalid support ticket query.",
        Detail = detail
    });

    private BadRequestObjectResult InvalidStatus(string detail) => BadRequest(new ProblemDetails
    {
        Status = StatusCodes.Status400BadRequest,
        Title = "Invalid support ticket status.",
        Detail = detail
    });

    private static AdminSupportTicketDetailDto ToDetail(
        SupportTicket ticket,
        string requesterFullName,
        string requesterEmail) => new(
        ticket.Id,
        ticket.Category.ToString(),
        ticket.Subject,
        ticket.Message,
        ticket.Status.ToString(),
        ticket.CreatedAt,
        ticket.UpdatedAt,
        requesterFullName,
        requesterEmail);
}
