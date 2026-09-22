using System.Text;
using System.Security.Claims;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using RentFlow.Api.Configuration;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;

var builder = WebApplication.CreateBuilder(args);
const string DevelopmentCorsPolicy = "DevelopmentCors";

// Add services to the container.
// Learn more about configuring Swagger/OpenAPI at https://aka.ms/aspnetcore/swashbuckle
var connectionString = builder.Configuration.GetConnectionString("DefaultConnection")
    ?? throw new InvalidOperationException("Connection string 'DefaultConnection' was not found.");

builder.Services.AddDbContext<ApplicationDbContext>(options =>
    options.UseNpgsql(connectionString));

builder.Services.AddOptions<CloudflareR2Options>()
    .Bind(builder.Configuration.GetSection(CloudflareR2Options.SectionName))
    .ValidateDataAnnotations()
    .ValidateOnStart();

builder.Services.AddOptions<AgentServiceOptions>()
    .Bind(builder.Configuration.GetSection(AgentServiceOptions.SectionName));

builder.Services.AddOptions<DocumentAnalysisOptions>()
    .Bind(builder.Configuration.GetSection(DocumentAnalysisOptions.SectionName))
    .ValidateDataAnnotations()
    .Validate(options => options.AllowedContentTypes.All(contentType =>
        contentType is "application/pdf" or "image/jpeg" or "image/png"),
        "DocumentAnalysis contains an unsupported content type.")
    .ValidateOnStart();

builder.Services.AddOptions<JwtOptions>()
    .Bind(builder.Configuration.GetSection(JwtOptions.SectionName))
    .ValidateDataAnnotations()
    .Validate(
        options => Encoding.UTF8.GetByteCount(options.SigningKey) >= 32,
        "Jwt:SigningKey must be at least 32 bytes. Configure it with user-secrets or an environment variable.")
    .ValidateOnStart();

var jwtSection = builder.Configuration.GetSection(JwtOptions.SectionName);
builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        var jwtOptions = jwtSection.Get<JwtOptions>() ?? new JwtOptions();
        options.MapInboundClaims = false;
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = jwtOptions.Issuer,
            ValidateAudience = true,
            ValidAudience = jwtOptions.Audience,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(
                Encoding.UTF8.GetBytes(jwtOptions.SigningKey)),
            ValidateLifetime = true,
            ClockSkew = TimeSpan.FromMinutes(1),
            NameClaimType = "sub",
            RoleClaimType = "role"
        };
        options.Events = new JwtBearerEvents
        {
            OnTokenValidated = context =>
            {
                var subject = context.Principal?.FindFirstValue("sub");
                var roleValue = context.Principal?.FindFirstValue("role");
                if (!Guid.TryParse(subject, out var userId)
                    || userId == Guid.Empty
                    || !Enum.TryParse<UserRole>(roleValue, ignoreCase: false, out var role)
                    || !Enum.IsDefined(role))
                {
                    context.Fail("The token identity claims are invalid.");
                }

                return Task.CompletedTask;
            }
        };
    });
builder.Services.AddAuthorization();

builder.Services.AddScoped<IViewingService, ViewingService>();
builder.Services.AddScoped<IAuthService, AuthService>();
builder.Services.AddScoped<IJwtTokenService, JwtTokenService>();
builder.Services.AddScoped<ICurrentUserService, CurrentUserService>();
builder.Services.AddScoped<IPasswordHasher<ApplicationUser>, PasswordHasher<ApplicationUser>>();
builder.Services.AddHttpContextAccessor();
builder.Services.AddScoped<IRentalApplicationService, RentalApplicationService>();
builder.Services.AddScoped<IMaintenanceRequestService, MaintenanceRequestService>();
builder.Services.AddScoped<IMaintenanceAttachmentService, MaintenanceAttachmentService>();
builder.Services.AddScoped<IApplicationDocumentService, ApplicationDocumentService>();
builder.Services.AddScoped<IApplicationDocumentContentService, ApplicationDocumentContentService>();
builder.Services.AddScoped<IApplicationDataValidationTool, ApplicationDataValidationTool>();
builder.Services.AddScoped<IDocumentValidationTool, DocumentValidationTool>();
builder.Services.AddScoped<IDeterministicApplicationRuleTool, DeterministicApplicationRuleTool>();
builder.Services.AddScoped<IMaintenanceRequestDataValidationTool, MaintenanceRequestDataValidationTool>();
builder.Services.AddScoped<IMaintenanceCoordinationRuleTool, MaintenanceCoordinationRuleTool>();
builder.Services.AddScoped<IMaintenanceCoordinationOrchestrator, MaintenanceCoordinationOrchestrator>();
builder.Services.AddScoped<IApplicationValidationOrchestrator, ApplicationValidationOrchestrator>();
builder.Services.AddScoped<IApplicationValidationQueryService, ApplicationValidationQueryService>();
builder.Services.AddHttpClient<IApplicationValidationAgentClient, ApplicationValidationAgentClient>(client =>
    client.Timeout = Timeout.InfiniteTimeSpan);
builder.Services.AddScoped<IMaintenanceCoordinationService, MaintenanceCoordinationService>();
builder.Services.AddHttpClient<IMaintenanceCoordinationAgentClient, MaintenanceCoordinationAgentClient>(client =>
    client.Timeout = Timeout.InfiniteTimeSpan);
builder.Services.AddSingleton<IFileStorageService, CloudflareR2StorageService>();
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Name = "Authorization",
        Type = SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT",
        In = ParameterLocation.Header
    });
    options.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        [new OpenApiSecurityScheme
        {
            Reference = new OpenApiReference
            {
                Type = ReferenceType.SecurityScheme,
                Id = "Bearer"
            }
        }] = Array.Empty<string>()
    });
});

if (builder.Environment.IsDevelopment())
{
    builder.Services.AddCors(options =>
    {
        options.AddPolicy(DevelopmentCorsPolicy, policy =>
        {
            policy
                .WithOrigins("http://localhost:5173")
                .AllowAnyHeader()
                .AllowAnyMethod();
        });
    });
}

var app = builder.Build();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
    app.UseCors(DevelopmentCorsPolicy);
}

app.UseHttpsRedirection();

app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();

app.Run();

public partial class Program;
