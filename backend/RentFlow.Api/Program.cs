using System.Text;
using System.Security.Claims;
using System.Threading.RateLimiting;

using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;

using RentFlow.Api.Configuration;
using RentFlow.Api.Commands;
using RentFlow.Api.Authorization;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;

var builder = WebApplication.CreateBuilder(args);

const string DevelopmentCorsPolicy = "DevelopmentCors";

// =========================================================
// DATABASE
// =========================================================

var connectionString =
    builder.Configuration.GetConnectionString("DefaultConnection")
    ?? throw new InvalidOperationException(
        "Connection string 'DefaultConnection' was not found.");

builder.Services.AddDbContext<ApplicationDbContext>(options =>
    options.UseNpgsql(connectionString));

// =========================================================
// CONFIGURATION OPTIONS
// =========================================================

builder.Services.AddOptions<CloudflareR2Options>()
    .Bind(builder.Configuration.GetSection(
        CloudflareR2Options.SectionName))
    .ValidateDataAnnotations()
    .ValidateOnStart();

builder.Services.AddOptions<AgentServiceOptions>()
    .Bind(builder.Configuration.GetSection(
        AgentServiceOptions.SectionName));

builder.Services.AddOptions<DocumentAnalysisOptions>()
    .Bind(builder.Configuration.GetSection(
        DocumentAnalysisOptions.SectionName))
    .ValidateDataAnnotations()
    .Validate(
        options => options.AllowedContentTypes.All(contentType =>
            contentType is "application/pdf"
                or "image/jpeg"
                or "image/png"),
        "DocumentAnalysis contains an unsupported content type.")
    .ValidateOnStart();

builder.Services.AddOptions<JwtOptions>()
    .Bind(builder.Configuration.GetSection(
        JwtOptions.SectionName))
    .ValidateDataAnnotations()
    .Validate(
        options =>
            Encoding.UTF8.GetByteCount(options.SigningKey) >= 32,
        "Jwt:SigningKey must be at least 32 bytes. " +
        "Configure it with user-secrets or an environment variable.")
    .ValidateOnStart();

builder.Services.AddOptions<StaffProvisioningOptions>()
    .Bind(builder.Configuration.GetSection(
        StaffProvisioningOptions.SectionName))
    .ValidateDataAnnotations()
    .ValidateOnStart();

// =========================================================
// JWT AUTHENTICATION
// =========================================================

var jwtSection =
    builder.Configuration.GetSection(JwtOptions.SectionName);

builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        var jwtOptions =
            jwtSection.Get<JwtOptions>() ?? new JwtOptions();

        options.MapInboundClaims = false;

        options.TokenValidationParameters =
            new TokenValidationParameters
            {
                ValidateIssuer = true,
                ValidIssuer = jwtOptions.Issuer,

                ValidateAudience = true,
                ValidAudience = jwtOptions.Audience,

                ValidateIssuerSigningKey = true,
                IssuerSigningKey =
                    new SymmetricSecurityKey(
                        Encoding.UTF8.GetBytes(
                            jwtOptions.SigningKey)),

                ValidateLifetime = true,
                ClockSkew = TimeSpan.FromMinutes(1),

                NameClaimType = "sub",
                RoleClaimType = "role"
            };

        options.Events = new JwtBearerEvents
        {
            OnTokenValidated = context =>
            {
                var subject =
                    context.Principal?
                        .FindFirstValue("sub");

                var roleValue =
                    context.Principal?
                        .FindFirstValue("role");

                if (!Guid.TryParse(
                        subject,
                        out var userId)
                    || userId == Guid.Empty
                    || !Enum.TryParse<UserRole>(
                        roleValue,
                        ignoreCase: false,
                        out var role)
                    || !Enum.IsDefined(role))
                {
                    context.Fail(
                        "The token identity claims are invalid.");
                }

                return Task.CompletedTask;
            }
        };
    });

builder.Services.AddAuthorization(options =>
{
    options.AddPolicy(
        AuthorizationPolicies.ActiveAdmin,
        policy =>
        {
            policy.RequireAuthenticatedUser();
            policy.RequireRole(nameof(UserRole.Admin));
            policy.AddRequirements(
                new ActiveAdminRequirement());
        });
});

builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode =
        StatusCodes.Status429TooManyRequests;

    options.AddPolicy(
        "technician-activation",
        context => RateLimitPartition.GetFixedWindowLimiter(
            context.Connection.RemoteIpAddress?.ToString()
                ?? "unknown",
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 5,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0,
                AutoReplenishment = true
            }));
});

// =========================================================
// CORE SERVICES
// =========================================================

builder.Services.AddScoped<
    IViewingService,
    ViewingService>();

builder.Services.AddScoped<
    IAuthService,
    AuthService>();

builder.Services.AddScoped<
    IJwtTokenService,
    JwtTokenService>();

builder.Services.AddScoped<
    ICurrentUserService,
    CurrentUserService>();

builder.Services.AddScoped<
    INotificationService,
    NotificationService>();

builder.Services.AddScoped<
    IPasswordHasher<ApplicationUser>,
    PasswordHasher<ApplicationUser>>();

builder.Services.AddScoped<AdminBootstrapService>();
builder.Services.AddScoped<AdminBootstrapCommand>();

builder.Services.AddSingleton<
    IAdminBootstrapConsole,
    SystemAdminBootstrapConsole>();

builder.Services.AddScoped<TechnicianProvisioningService>();

builder.Services.AddScoped<
    IAuthorizationHandler,
    ActiveAdminAuthorizationHandler>();

builder.Services.AddHttpContextAccessor();

// =========================================================
// PROPERTY MANAGEMENT / PROPERTY MATCHING AI
// =========================================================

builder.Services.AddScoped<
    IPropertyService,
    PropertyService>();

builder.Services.AddScoped<
    IPropertyAccessGuard,
    PropertyAccessGuard>();

builder.Services.AddScoped<
    IPropertyImageService,
    PropertyImageService>();

builder.Services.AddScoped<
    IPropertyMatchingRuleTool,
    PropertyMatchingRuleTool>();

builder.Services.AddScoped<
    IPropertyMatchingOrchestrator,
    PropertyMatchingOrchestrator>();

builder.Services.AddHttpClient<
    IPropertyMatchingAgentClient,
    PropertyMatchingAgentClient>(
        client =>
        {
            client.Timeout = Timeout.InfiniteTimeSpan;
        });

// =========================================================
// RENTAL APPLICATION SERVICES
// =========================================================

builder.Services.AddScoped<
    IRentalApplicationService,
    RentalApplicationService>();

builder.Services.AddScoped<
    IApplicationDocumentService,
    ApplicationDocumentService>();

builder.Services.AddScoped<
    IApplicationDocumentContentService,
    ApplicationDocumentContentService>();

// =========================================================
// RENTAL PRICING / LEASE / PAYMENT SERVICES
// =========================================================

builder.Services.AddScoped<
    IRentalOfferService,
    RentalOfferService>();

builder.Services.AddScoped<
    ILeaseAgreementService,
    LeaseAgreementService>();

builder.Services.AddScoped<
    IRentScheduleService,
    RentScheduleService>();

builder.Services.AddScoped<
    IPaymentService,
    PaymentService>();

// =========================================================
// MAINTENANCE SERVICES
// =========================================================

builder.Services.AddScoped<
    IMaintenanceRequestService,
    MaintenanceRequestService>();

builder.Services.AddScoped<
    IMaintenanceAttachmentService,
    MaintenanceAttachmentService>();

builder.Services.AddScoped<
    IMaintenanceRequestDataValidationTool,
    MaintenanceRequestDataValidationTool>();

builder.Services.AddScoped<
    IMaintenanceCoordinationRuleTool,
    MaintenanceCoordinationRuleTool>();

builder.Services.AddScoped<
    IMaintenanceCoordinationOrchestrator,
    MaintenanceCoordinationOrchestrator>();

builder.Services.AddScoped<
    IMaintenanceCoordinationService,
    MaintenanceCoordinationService>();

builder.Services.AddHttpClient<
    IMaintenanceCoordinationAgentClient,
    MaintenanceCoordinationAgentClient>(
        client =>
        {
            client.Timeout = Timeout.InfiniteTimeSpan;
        });

// =========================================================
// APPLICATION VALIDATION / AI
// =========================================================

builder.Services.AddScoped<
    IApplicationDataValidationTool,
    ApplicationDataValidationTool>();

builder.Services.AddScoped<
    IDocumentValidationTool,
    DocumentValidationTool>();

builder.Services.AddScoped<
    IDeterministicApplicationRuleTool,
    DeterministicApplicationRuleTool>();

builder.Services.AddScoped<
    IApplicationValidationOrchestrator,
    ApplicationValidationOrchestrator>();

builder.Services.AddScoped<
    IApplicationValidationQueryService,
    ApplicationValidationQueryService>();

builder.Services.AddHttpClient<
    IApplicationValidationAgentClient,
    ApplicationValidationAgentClient>(
        client =>
        {
            client.Timeout = Timeout.InfiniteTimeSpan;
        });

// =========================================================
// CORE SERVICES
// =========================================================

builder.Services.AddScoped<
    IViewingService,
    ViewingService>();

builder.Services.AddScoped<
    IAuthService,
    AuthService>();

builder.Services.AddScoped<
    IJwtTokenService,
    JwtTokenService>();

builder.Services.AddScoped<
    ICurrentUserService,
    CurrentUserService>();

builder.Services.AddScoped<
    INotificationService,
    NotificationService>();

builder.Services.AddScoped<
    IPasswordHasher<ApplicationUser>,
    PasswordHasher<ApplicationUser>>();

builder.Services.AddSingleton<
    IFileStorageService,
    CloudflareR2StorageService>();

builder.Services.AddSingleton(TimeProvider.System);

builder.Services.AddControllers();

builder.Services.AddEndpointsApiExplorer();

builder.Services.AddSwaggerGen(options =>
{
    options.AddSecurityDefinition(
        "Bearer",
        new OpenApiSecurityScheme
        {
            Name = "Authorization",
            Type = SecuritySchemeType.Http,
            Scheme = "bearer",
            BearerFormat = "JWT",
            In = ParameterLocation.Header
        });

    options.AddSecurityRequirement(
        new OpenApiSecurityRequirement
        {
            [
                new OpenApiSecurityScheme
                {
                    Reference =
                        new OpenApiReference
                        {
                            Type =
                                ReferenceType.SecurityScheme,
                            Id = "Bearer"
                        }
                }
            ] = Array.Empty<string>()
        });
});

// =========================================================
// DEVELOPMENT CORS
// =========================================================

if (builder.Environment.IsDevelopment())
{
    builder.Services.AddCors(options =>
    {
        options.AddPolicy(
            DevelopmentCorsPolicy,
            policy =>
            {
                policy
                    .SetIsOriginAllowed(origin =>
                    {
                        if (!Uri.TryCreate(
                                origin,
                                UriKind.Absolute,
                                out var uri))
                        {
                            return false;
                        }

                        return
                            (uri.Host == "localhost"
                                || uri.Host == "127.0.0.1")
                            && (uri.Scheme == "http"
                                || uri.Scheme == "https");
                    })
                    .AllowAnyHeader()
                    .AllowAnyMethod();
            });
    });
}

// =========================================================
// APP
// =========================================================

var app = builder.Build();

if (AdminBootstrapCommand.IsRequested(args))
{
    await using var scope =
        app.Services.CreateAsyncScope();

    var command =
        scope.ServiceProvider
            .GetRequiredService<AdminBootstrapCommand>();

    Environment.ExitCode =
        await command.ExecuteAsync(args);

    return;
}

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();

    app.UseSwaggerUI();

    app.UseCors(
        DevelopmentCorsPolicy);
}

app.UseHttpsRedirection();

app.UseAuthentication();

app.UseAuthorization();

app.UseRateLimiter();

app.MapControllers();

app.Run();

public partial class Program;