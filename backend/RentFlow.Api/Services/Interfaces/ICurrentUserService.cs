using RentFlow.Api.Models;

namespace RentFlow.Api.Services.Interfaces;

public interface ICurrentUserService
{
    bool IsAuthenticated { get; }

    Guid? UserId { get; }

    UserRole? Role { get; }
}
