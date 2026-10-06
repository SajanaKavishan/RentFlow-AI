using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Npgsql;
using RentFlow.Api.Data;
using RentFlow.DevTools;

if (args.Contains("--help") || args.Length == 0)
{
    Console.WriteLine("RentFlow deployment and local maintenance commands. Run from repository root:");
    Console.WriteLine("dotnet run --project backend/RentFlow.DevTools -- --migrate");
    Console.WriteLine("dotnet run --project backend/RentFlow.DevTools -- --development --landlord-email YOUR_EMAIL [--dry-run]");
    return 0;
}
try
{
    if (args.Contains("--migrate"))
    {
        var migrationApiDirectory = Path.GetFullPath(Path.Combine(Directory.GetCurrentDirectory(), "backend", "RentFlow.Api"));
        if (!File.Exists(Path.Combine(migrationApiDirectory, "RentFlow.Api.csproj")))
            throw new MaintenanceDemoSetupException("Run this command from the RentFlow-AI repository root.");

        var migrationConfiguration = new ConfigurationBuilder().SetBasePath(migrationApiDirectory)
            .AddJsonFile("appsettings.json", optional: false)
            .AddJsonFile("appsettings.Development.json", optional: true)
            .AddUserSecrets(typeof(ApplicationDbContext).Assembly, optional: true)
            .AddEnvironmentVariables().Build();
        var migrationConnection = migrationConfiguration.GetConnectionString("DefaultConnection")
            ?? throw new MaintenanceDemoSetupException("The database connection string is not configured.");
        var migrationBuilder = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseNpgsql(migrationConnection);
        await using var migrationDb = new ApplicationDbContext(migrationBuilder.Options);
        await migrationDb.Database.MigrateAsync();
        Console.WriteLine("Database migrations applied successfully.");
        return 0;
    }

    if (!args.Contains("--development")) throw new MaintenanceDemoSetupException("Explicit --development is required.");
    var emailIndex = Array.IndexOf(args, "--landlord-email");
    if (emailIndex < 0 || emailIndex + 1 >= args.Length) throw new MaintenanceDemoSetupException("Provide --landlord-email.");
    var landlordEmail = args[emailIndex + 1];
    var apiDirectory = Path.GetFullPath(Path.Combine(Directory.GetCurrentDirectory(), "backend", "RentFlow.Api"));
    if (!File.Exists(Path.Combine(apiDirectory, "RentFlow.Api.csproj")))
        throw new MaintenanceDemoSetupException("Run this command from the RentFlow-AI repository root.");
    var configuration = new ConfigurationBuilder().SetBasePath(apiDirectory)
        .AddJsonFile("appsettings.json", optional: false)
        .AddJsonFile("appsettings.Development.json", optional: true)
        .AddUserSecrets(typeof(ApplicationDbContext).Assembly, optional: true)
        .AddEnvironmentVariables().Build();
    var connectionString = configuration.GetConnectionString("DefaultConnection")
        ?? throw new MaintenanceDemoSetupException("The backend development connection string is not configured.");
    MaintenanceDemoSeeder.ValidateLocalDevelopment(connectionString,
        Environment.GetEnvironmentVariable("DOTNET_ENVIRONMENT"));
    MaintenanceDemoSeeder.ValidateLocalDevelopment(connectionString, Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT"));
    var connection = new NpgsqlConnectionStringBuilder(connectionString) { Timeout = 10, CommandTimeout = 20 };
    await using var db = new ApplicationDbContext(new DbContextOptionsBuilder<ApplicationDbContext>()
        .UseNpgsql(connection.ConnectionString).Options);
    if (args.Contains("--inspect"))
    {
        var fixture = await MaintenanceDemoSeeder.CreateAsync(db, landlordEmail, DateTimeOffset.UtcNow, true);
        Console.WriteLine($"Backend service key configured: {!string.IsNullOrWhiteSpace(configuration["AgentService:ServiceApiKey"])}");
        Console.WriteLine($"Backend analysis timeout seconds: {configuration["AgentService:TimeoutSeconds"] ?? "30"}");
        var agentBase = configuration["AgentService:BaseUrl"] ?? "http://localhost:8001";
        if (Uri.TryCreate(agentBase, UriKind.Absolute, out var agentUri) && agentUri.IsLoopback
            && !string.IsNullOrWhiteSpace(configuration["AgentService:ServiceApiKey"]))
        {
            using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
            using var probe = new HttpRequestMessage(HttpMethod.Post, new Uri(agentUri, "/internal/maintenance-coordination/analyze"))
                { Content = new StringContent("{}", System.Text.Encoding.UTF8, "application/json") };
            probe.Headers.Add("X-RentFlow-Service-Key", configuration["AgentService:ServiceApiKey"]!.Trim());
            using var response = await client.SendAsync(probe);
            Console.WriteLine($"Backend-configured key agent auth probe: {(int)response.StatusCode} (422 = auth passed; no model calls).");
        }
        var workflows = await db.MaintenanceCoordinationWorkflows.AsNoTracking().Include(item => item.Steps)
            .Where(item => fixture.RequestIds.Contains(item.MaintenanceRequestId))
            .OrderByDescending(item => item.CreatedAt).Take(3).ToListAsync();
        foreach (var workflow in workflows)
        {
            Console.WriteLine($"Workflow {workflow.Id}: {workflow.Status}; error: {workflow.ErrorMessage ?? "none"}");
            foreach (var step in workflow.Steps.OrderBy(item => item.StepOrder))
                Console.WriteLine($"Step {step.StepOrder}: {step.Status}; error: {step.ErrorMessage ?? "none"}");
        }
        if (workflows.Count == 0) Console.WriteLine("No test-property analysis workflows found.");
        return 0;
    }
    var dryRun = args.Contains("--dry-run");
    Console.WriteLine($"Local development database: {connection.Database}; dry run: {dryRun}.");
    using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(30));
    var token = timeout.Token;
    var credentialsDirectory = Path.GetFullPath(Path.Combine(Directory.GetCurrentDirectory(), ".tmp"));
    if (!dryRun) Directory.CreateDirectory(credentialsDirectory);
    await using var transaction = await db.Database.BeginTransactionAsync(token);
    var result = await MaintenanceDemoSeeder.CreateAsync(db, landlordEmail, DateTimeOffset.UtcNow, dryRun, token);
    if (dryRun)
    {
        Console.WriteLine(result.PropertyId == Guid.Empty
            ? "Ready to add one synthetic Tenant/property/application/offer/active lease, two requests and their creation histories. Existing accounts/data will not be modified."
            : $"Existing test property: {result.PropertyId}; no changes will be made.");
        await transaction.RollbackAsync(token);
        return 0;
    }
    var credentialsFile = Path.Combine(credentialsDirectory, $"maintenance-demo-{result.PropertyId:N}.txt");
    if (result.NewTenantPassword is { } password)
    {
        // Save the test login privately in an ignored local file, never to console/provider logs.
        await File.WriteAllTextAsync(credentialsFile,
            $"Development test Tenant only\nEmail: {result.TenantEmail}\nPassword: {password}\nProperty: {result.PropertyId}\n", token);
    }
    await transaction.CommitAsync(token);
    Console.WriteLine(result.Created ? "Maintenance test fixtures created." : "Existing maintenance test fixtures reused; no passwords/state reset.");
    Console.WriteLine($"Property: {result.PropertyId}; maintenance requests: {result.RequestIds.Count}.");
    Console.WriteLine($"Landlord UI path: /modules/maintenance/landlord?propertyId={result.PropertyId}");
    Console.WriteLine($"Test Tenant email: {result.TenantEmail}");
    if (File.Exists(credentialsFile)) Console.WriteLine($"Test Tenant credentials: {credentialsFile}");
    Console.WriteLine("Start the backend and Python agent, log in as your Landlord, choose the test property and click Analyze request for real AI. Upload test photos using the Tenant's normal maintenance flow.");
    return 0;
}
catch (Exception exception)
{
    // Never disclose connection credentials, SQL payloads, passwords, or provider secrets.
    Console.Error.WriteLine(exception is MaintenanceDemoSetupException ? exception.Message
        : $"Local fixture setup failed ({exception.GetType().Name}). Check local PostgreSQL availability and existing migrations. No migration was run.");
    return 1;
}
