using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.Models;

namespace RentFlow.Api.Authorization;

public sealed class ActiveAdminAuthorizationHandler(
    ApplicationDbContext dbContext)
    : AuthorizationHandler<ActiveAdminRequirement>
{
    protected override async Task HandleRequirementAsync(
        AuthorizationHandlerContext context,
        ActiveAdminRequirement requirement)
    {
        var subject = context.User.FindFirstValue(JwtRegisteredClaimNames.Sub)
            ?? context.User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (!Guid.TryParse(subject, out var userId))
        {
            return;
        }

        var isActiveAdmin = await dbContext.Users
            .AsNoTracking()
            .AnyAsync(user =>
                user.Id == userId
                && user.IsActive
                && user.Role == UserRole.Admin);
        if (isActiveAdmin)
        {
            context.Succeed(requirement);
        }
    }
}
