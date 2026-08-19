using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Configuration;
using RentFlow.Api.Data;
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

builder.Services.AddScoped<IViewingService, ViewingService>();
builder.Services.AddScoped<IRentalApplicationService, RentalApplicationService>();
builder.Services.AddScoped<IApplicationDocumentService, ApplicationDocumentService>();
builder.Services.AddScoped<IApplicationDataValidationTool, ApplicationDataValidationTool>();
builder.Services.AddScoped<IDocumentValidationTool, DocumentValidationTool>();
builder.Services.AddScoped<IDeterministicApplicationRuleTool, DeterministicApplicationRuleTool>();
builder.Services.AddScoped<IApplicationValidationOrchestrator, ApplicationValidationOrchestrator>();
builder.Services.AddScoped<IApplicationValidationQueryService, ApplicationValidationQueryService>();
builder.Services.AddSingleton<IFileStorageService, CloudflareR2StorageService>();
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

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

app.MapControllers();

app.Run();
