using RentFlow.Api.Models;

namespace RentFlow.Api.Services.Interfaces;

public interface IJwtTokenService
{
    JwtToken CreateToken(ApplicationUser user);
}

public sealed record JwtToken(string Value, DateTimeOffset ExpiresAt);
