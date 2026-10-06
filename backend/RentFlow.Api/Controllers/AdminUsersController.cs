using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Authorization;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Auth;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

[ApiController]
[Route("api/admin/users")]
[Authorize(Policy = AuthorizationPolicies.ActiveAdmin)]
public sealed class AdminUsersController(ApplicationDbContext dbContext, ICurrentUserService currentUser, TimeProvider clock) : ControllerBase
{
    private const int DefaultPageSize = 20;
    private const int MaximumPageSize = 100;
    private const int MaximumSearchLength = 320;

    [HttpGet]
    [ProducesResponseType<AdminUserDirectoryPageDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<AdminUserDirectoryPageDto>> GetPage(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = DefaultPageSize,
        [FromQuery] string? search = null,
        [FromQuery] string? role = null,
        [FromQuery] bool? isActive = null,
        CancellationToken cancellationToken = default)
    {
        if (page < 1 || pageSize is < 1 or > MaximumPageSize)
        {
            return InvalidQuery(
                $"Page must be at least 1 and pageSize must be between 1 and {MaximumPageSize}.");
        }

        var trimmedSearch = search?.Trim();
        if (trimmedSearch?.Length > MaximumSearchLength)
        {
            return InvalidQuery(
                $"Search must not exceed {MaximumSearchLength} characters.");
        }

        UserRole? roleFilter = null;
        var trimmedRole = role?.Trim();
        if (!string.IsNullOrEmpty(trimmedRole))
        {
            if (!Enum.GetNames<UserRole>().Contains(trimmedRole, StringComparer.Ordinal))
            {
                return InvalidQuery(
                    $"Role must be one of: {string.Join(", ", Enum.GetNames<UserRole>())}.");
            }

            roleFilter = Enum.Parse<UserRole>(trimmedRole);
        }

        var query = dbContext.Users.AsNoTracking().AsQueryable();

        if (!string.IsNullOrEmpty(trimmedSearch))
        {
            var normalizedSearch = trimmedSearch.ToUpperInvariant();
            query = query.Where(user =>
                user.NormalizedEmail.Contains(normalizedSearch)
                || user.FullName.ToUpper().Contains(normalizedSearch));
        }

        if (roleFilter is not null)
        {
            query = query.Where(user => user.Role == roleFilter.Value);
        }

        if (isActive is not null)
        {
            query = query.Where(user => user.IsActive == isActive.Value);
        }

        var totalCount = await query.CountAsync(cancellationToken);
        var totalPages = totalCount == 0
            ? 0
            : (int)Math.Ceiling(totalCount / (double)pageSize);
        var skip = ((long)page - 1) * pageSize;

        IReadOnlyList<AdminUserDirectoryItemDto> items = skip >= totalCount
            ? []
            : await query
                .OrderByDescending(user => user.CreatedAt)
                .ThenByDescending(user => user.Id)
                .Skip((int)skip)
                .Take(pageSize)
                .Select(user => new AdminUserDirectoryItemDto(
                    user.Id,
                    user.FullName,
                    user.Email,
                    user.Role,
                    user.IsActive,
                    user.CreatedAt))
                .ToListAsync(cancellationToken);

        return Ok(new AdminUserDirectoryPageDto
        {
            Items = items,
            Pagination = new AdminUserDirectoryPaginationDto
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
    public async Task<ActionResult<AdminUserDetailsDto>> GetUser(Guid id, CancellationToken ct)
    {
        var user = await dbContext.Users.AsNoTracking().SingleOrDefaultAsync(user => user.Id == id, ct);
        return user is null ? NotFound() : Ok(Details(user));
    }

    [HttpPatch("{id:guid}/deactivate")]
    public async Task<ActionResult<AdminUserDetailsDto>> Deactivate(Guid id, CancellationToken ct)
    {
        if (currentUser.UserId is not Guid actor) return Unauthorized();
        if (actor == id) return Conflict(new ProblemDetails { Status = 409, Detail = "You cannot deactivate your own Admin account." });
        await using var transaction = dbContext.Database.IsRelational() ? await dbContext.Database.BeginTransactionAsync(ct) : null;
        if (transaction is not null)
            await dbContext.Database.ExecuteSqlInterpolatedAsync($"SELECT 1 FROM \"Users\" WHERE \"Id\" = {actor} OR \"Id\" = {id} ORDER BY \"Id\" FOR UPDATE", ct);
        if (!await dbContext.Users.AsNoTracking().AnyAsync(user => user.Id == actor && user.IsActive && user.Role == UserRole.Admin, ct)) return Unauthorized();
        var target = await dbContext.Users.SingleOrDefaultAsync(user => user.Id == id, ct);
        if (target is null) return NotFound();
        if (target.IsActive)
        {
            var now = clock.GetUtcNow();
            target.IsActive = false;
            target.TokenVersion = checked(target.TokenVersion + 1);
            target.UpdatedAt = now;
            foreach (var token in await dbContext.TechnicianPasswordSetupTokens.Where(token => token.UserId == id && token.ConsumedAt == null).ToListAsync(ct)) token.ConsumedAt = now;
            foreach (var token in await dbContext.PasswordResetTokens.Where(token => token.UserId == id && token.ConsumedAt == null).ToListAsync(ct)) token.ConsumedAt = now;
            await dbContext.SaveChangesAsync(ct);
        }
        if (transaction is not null) await transaction.CommitAsync(ct);
        return Ok(Details(target));
    }

    private static AdminUserDetailsDto Details(ApplicationUser user) => new(user.Id, user.FullName, user.Email,
        user.PhoneNumber, user.Role, user.IsActive, user.CreatedAt);

    private BadRequestObjectResult InvalidQuery(string detail) => BadRequest(new ProblemDetails
    {
        Status = StatusCodes.Status400BadRequest,
        Title = "Invalid user directory query.",
        Detail = detail
    });
}
