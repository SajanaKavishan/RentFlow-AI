using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RentFlow.Api.DTOs.Auth;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

[ApiController]
[Route("api/auth")]
public sealed class AuthController(
    IAuthService authService,
    ICurrentUserService currentUserService) : ControllerBase
{
    private const long MaximumProfileImageRequestBytes = 5 * 1024 * 1024 + 64 * 1024;
    [AllowAnonymous]
    [HttpPost("register")]
    [ProducesResponseType<AuthResponseDto>(StatusCodes.Status201Created)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public async Task<ActionResult<AuthResponseDto>> Register(
        [FromBody] RegisterRequestDto request,
        CancellationToken cancellationToken)
    {
        try
        {
            var response = await authService.RegisterAsync(request, cancellationToken);
            return StatusCode(StatusCodes.Status201Created, response);
        }
        catch (AuthServiceException exception)
        {
            return MapException(exception);
        }
    }

    [AllowAnonymous]
    [HttpPost("login")]
    [ProducesResponseType<AuthResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status401Unauthorized)]
    public async Task<ActionResult<AuthResponseDto>> Login(
        [FromBody] LoginRequestDto request,
        CancellationToken cancellationToken)
    {
        try
        {
            return Ok(await authService.LoginAsync(request, cancellationToken));
        }
        catch (AuthServiceException exception)
        {
            return MapException(exception);
        }
    }

    [Authorize]
    [HttpGet("me")]
    [ProducesResponseType<UserProfileDto>(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<ActionResult<UserProfileDto>> Me(CancellationToken cancellationToken)
    {
        if (currentUserService.UserId is not { } userId)
        {
            return Unauthorized();
        }

        var user = await authService.GetUserAsync(userId, cancellationToken);
        return user is null ? Unauthorized() : Ok(user);
    }

    [Authorize]
    [HttpPut("profile")]
    [ProducesResponseType<UserProfileDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<ActionResult<UserProfileDto>> UpdateProfile(
        [FromBody] UpdateProfileRequestDto request,
        CancellationToken cancellationToken)
    {
        if (currentUserService.UserId is not { } userId) return Unauthorized();
        try
        {
            var profile = await authService.UpdateProfileAsync(userId, request, cancellationToken);
            return profile is null ? Unauthorized() : Ok(profile);
        }
        catch (AuthServiceException exception)
        {
            return MapException(exception);
        }
    }

    [Authorize]
    [HttpPost("profile-image")]
    [RequestSizeLimit(MaximumProfileImageRequestBytes)]
    [RequestFormLimits(MultipartBodyLengthLimit = MaximumProfileImageRequestBytes)]
    [ProducesResponseType<UserProfileDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<ActionResult<UserProfileDto>> UploadProfileImage(
        [FromForm] UploadProfileImageRequestDto request,
        CancellationToken cancellationToken)
    {
        if (currentUserService.UserId is not { } userId) return Unauthorized();
        try
        {
            await using var stream = new MemoryStream();
            await request.File.CopyToAsync(stream, cancellationToken);
            var profile = await authService.UploadProfileImageAsync(
                userId,
                stream.ToArray(),
                request.File.ContentType,
                cancellationToken);
            return profile is null ? Unauthorized() : Ok(profile);
        }
        catch (AuthServiceException exception)
        {
            return MapException(exception);
        }
    }

    [Authorize]
    [HttpGet("profile-image")]
    [Produces("image/jpeg", "image/png", "image/webp")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetProfileImage(CancellationToken cancellationToken)
    {
        if (currentUserService.UserId is not { } userId) return Unauthorized();
        var image = await authService.GetProfileImageAsync(userId, cancellationToken);
        if (image is null) return NotFound();
        Response.Headers.CacheControl = "private, no-store";
        return File(image.Content, image.ContentType);
    }

    private ActionResult MapException(AuthServiceException exception)
    {
        var (statusCode, title) = exception.Error switch
        {
            AuthServiceError.Validation =>
                (StatusCodes.Status400BadRequest, "Invalid registration request."),
            AuthServiceError.DuplicateEmail =>
                (StatusCodes.Status409Conflict, "Registration conflict."),
            AuthServiceError.InvalidCredentials =>
                (StatusCodes.Status401Unauthorized, "Authentication failed."),
            _ =>
                (StatusCodes.Status500InternalServerError, "An unexpected error occurred.")
        };

        return StatusCode(statusCode, new ProblemDetails
        {
            Status = statusCode,
            Title = title,
            Detail = statusCode == StatusCodes.Status500InternalServerError
                ? "The request could not be completed."
                : exception.Message
        });
    }
}
