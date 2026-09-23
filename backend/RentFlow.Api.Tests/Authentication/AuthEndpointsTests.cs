using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using Xunit;

namespace RentFlow.Api.Tests.Authentication;

public sealed class AuthEndpointsTests
{
    private const string ValidPassword = "Secure1!Password";

    [Theory]
    [InlineData("Tenant")]
    [InlineData("Landlord")]
    public async Task Register_AllowsPublicEndUserRoles(string role)
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();

        var response = await RegisterAsync(client, "user@example.com", role);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var body = await ParseAsync(response);
        Assert.Equal(role, body.RootElement.GetProperty("user").GetProperty("role").GetString());
        Assert.False(string.IsNullOrWhiteSpace(body.RootElement.GetProperty("accessToken").GetString()));
    }

    [Fact]
    public async Task Register_RejectsDuplicateNormalizedEmail()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        await RegisterAsync(client, "person@example.com", "Tenant");

        var response = await RegisterAsync(client, "  PERSON@example.com  ", "Landlord");

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
    }

    [Theory]
    [InlineData("Admin")]
    [InlineData("MaintenanceTechnician")]
    public async Task Register_RejectsPrivilegedSelfRegistration(string role)
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();

        var response = await RegisterAsync(client, "privileged@example.com", role);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Register_StoresHashAndNeverReturnsPasswordMaterialOrSigningKey()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();

        var response = await RegisterAsync(client, "safe@example.com", "Tenant");
        var responseText = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.DoesNotContain("password", responseText, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("hash", responseText, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("signing", responseText, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("test-only-signing-key", responseText, StringComparison.OrdinalIgnoreCase);

        using var scope = factory.Services.CreateScope();
        var user = await scope.ServiceProvider
            .GetRequiredService<ApplicationDbContext>()
            .Users.SingleAsync();
        Assert.NotEqual(ValidPassword, user.PasswordHash);
        Assert.DoesNotContain(ValidPassword, user.PasswordHash, StringComparison.Ordinal);
        var hasher = scope.ServiceProvider.GetRequiredService<IPasswordHasher<ApplicationUser>>();
        Assert.NotEqual(
            PasswordVerificationResult.Failed,
            hasher.VerifyHashedPassword(user, user.PasswordHash!, ValidPassword));
    }

    [Fact]
    public async Task Register_RejectsPasswordOutsidePolicy()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();

        var response = await RegisterAsync(
            client,
            "weak@example.com",
            "Tenant",
            password: "alllowercase");

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Login_WithCorrectCredentials_ReturnsJwtWithUserIdAndRole()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        var registration = await RegisterAsync(client, "login@example.com", "Landlord");
        var registrationBody = await ParseAsync(registration);
        var userId = registrationBody.RootElement.GetProperty("user").GetProperty("id").GetGuid();

        var response = await LoginAsync(client, "LOGIN@example.com", ValidPassword);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await ParseAsync(response);
        var token = new JwtSecurityTokenHandler().ReadJwtToken(
            body.RootElement.GetProperty("accessToken").GetString());
        Assert.Equal(userId.ToString(), token.Claims.Single(claim => claim.Type == "sub").Value);
        Assert.Equal("Landlord", token.Claims.Single(claim => claim.Type == "role").Value);
        Assert.Equal("login@example.com", token.Claims.Single(claim => claim.Type == "email").Value);
    }

    [Fact]
    public async Task Login_WrongAndUnknownEmail_ReturnSameSafeError()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        await RegisterAsync(client, "known@example.com", "Tenant");

        var wrongPassword = await LoginAsync(client, "known@example.com", "Wrong1!Password");
        var unknownEmail = await LoginAsync(client, "unknown@example.com", "Wrong1!Password");

        Assert.Equal(HttpStatusCode.Unauthorized, wrongPassword.StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, unknownEmail.StatusCode);
        Assert.Equal(
            (await ParseAsync(wrongPassword)).RootElement.GetProperty("detail").GetString(),
            (await ParseAsync(unknownEmail)).RootElement.GetProperty("detail").GetString());
        Assert.Equal(
            "Invalid email or password.",
            (await ParseAsync(unknownEmail)).RootElement.GetProperty("detail").GetString());
    }

    [Fact]
    public async Task Login_RejectsInactiveUserWithGenericError()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        await SeedUserAsync(factory, "inactive@example.com", isActive: false);

        var response = await LoginAsync(client, "inactive@example.com", ValidPassword);

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Equal(
            "Invalid email or password.",
            (await ParseAsync(response)).RootElement.GetProperty("detail").GetString());
    }

    [Fact]
    public async Task Me_WithoutToken_ReturnsUnauthorized()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();

        var response = await client.GetAsync("/api/auth/me");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Me_WithValidToken_ReturnsCurrentUser()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        var registration = await RegisterAsync(client, "me@example.com", "Tenant");
        var registrationBody = await ParseAsync(registration);
        var token = registrationBody.RootElement.GetProperty("accessToken").GetString();
        var expectedId = registrationBody.RootElement.GetProperty("user").GetProperty("id").GetGuid();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

        var response = await client.GetAsync("/api/auth/me");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await ParseAsync(response);
        Assert.Equal(expectedId, body.RootElement.GetProperty("id").GetGuid());
        Assert.Equal("me@example.com", body.RootElement.GetProperty("email").GetString());
        Assert.Equal("Tenant", body.RootElement.GetProperty("role").GetString());
    }

    [Theory]
    [InlineData("not-a-jwt")]
    [InlineData("eyJhbGciOiJub25lIn0.eyJzdWIiOiIxIn0.")]
    public async Task Me_WithMalformedOrInvalidToken_ReturnsUnauthorized(string token)
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

        var response = await client.GetAsync("/api/auth/me");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Theory]
    [InlineData("Owner")]
    [InlineData(1)]
    public async Task Register_RejectsRolesOutsideStringAllowList(object role)
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();

        var response = await client.PostAsJsonAsync("/api/auth/register", new
        {
            fullName = "Invalid Role",
            email = "role@example.com",
            phoneNumber = "+94770000000",
            password = ValidPassword,
            role
        });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    private static Task<HttpResponseMessage> RegisterAsync(
        HttpClient client,
        string email,
        string role,
        string password = ValidPassword)
    {
        return client.PostAsJsonAsync("/api/auth/register", new
        {
            fullName = "Test User",
            email,
            phoneNumber = "+94770000000",
            password,
            role
        });
    }

    private static Task<HttpResponseMessage> LoginAsync(
        HttpClient client,
        string email,
        string password)
    {
        return client.PostAsJsonAsync("/api/auth/login", new { email, password });
    }

    private static async Task<JsonDocument> ParseAsync(HttpResponseMessage response)
    {
        return JsonDocument.Parse(await response.Content.ReadAsStringAsync());
    }

    private static async Task SeedUserAsync(
        AuthApiFactory factory,
        string email,
        bool isActive)
    {
        using var scope = factory.Services.CreateScope();
        var services = scope.ServiceProvider;
        var context = services.GetRequiredService<ApplicationDbContext>();
        var user = new ApplicationUser
        {
            Id = Guid.NewGuid(),
            FullName = "Inactive User",
            Email = email,
            NormalizedEmail = AuthService.NormalizeEmail(email),
            PhoneNumber = "+94770000000",
            Role = UserRole.Tenant,
            IsActive = isActive,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        var hasher = services.GetRequiredService<IPasswordHasher<ApplicationUser>>();
        user.PasswordHash = hasher.HashPassword(user, ValidPassword);
        context.Users.Add(user);
        await context.SaveChangesAsync();
    }
}
