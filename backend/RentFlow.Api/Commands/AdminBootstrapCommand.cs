using RentFlow.Api.Services;

namespace RentFlow.Api.Commands;

public sealed class AdminBootstrapCommand(
    IHostEnvironment environment,
    IAdminBootstrapConsole console,
    AdminBootstrapService bootstrapService)
{
    public const string Option = "--bootstrap-admin";

    public static bool IsRequested(IEnumerable<string> args) =>
        args.Contains(Option, StringComparer.Ordinal);

    public async Task<int> ExecuteAsync(
        IReadOnlyList<string> args,
        CancellationToken cancellationToken = default)
    {
        if (args.Count != 1 || !string.Equals(args[0], Option, StringComparison.Ordinal))
        {
            console.WriteLine(
                $"Error: {Option} must be the only application argument; credentials are accepted only through interactive prompts.");
            return 2;
        }

        if (!environment.IsDevelopment())
        {
            console.WriteLine("Error: initial Admin provisioning is available only in Development.");
            return 1;
        }

        if (!console.IsInputInteractive)
        {
            console.WriteLine("Error: initial Admin provisioning requires an interactive terminal.");
            return 1;
        }

        console.Write("Full name: ");
        var fullName = console.ReadLine();
        console.Write("Email: ");
        var email = console.ReadLine();
        console.Write("Phone number: ");
        var phoneNumber = console.ReadLine();
        console.Write("Password: ");
        var password = console.ReadSecret();
        console.Write("Confirm password: ");
        var passwordConfirmation = console.ReadSecret();

        if (fullName is null || email is null || phoneNumber is null)
        {
            console.WriteLine("Error: input was cancelled; no Admin account was created.");
            return 1;
        }

        if (!string.Equals(password, passwordConfirmation, StringComparison.Ordinal))
        {
            console.WriteLine("Error: password confirmation does not match; no Admin account was created.");
            return 1;
        }

        try
        {
            await bootstrapService.BootstrapAsync(
                fullName,
                email,
                phoneNumber,
                password,
                cancellationToken);
            console.WriteLine("Initial Admin account created successfully.");
            return 0;
        }
        catch (AdminBootstrapException exception)
        {
            console.WriteLine($"Error: {exception.Message}");
            return 1;
        }
        catch (Exception) when (!cancellationToken.IsCancellationRequested)
        {
            console.WriteLine(
                "Error: initial Admin provisioning failed. Verify the development database configuration and migrations.");
            return 1;
        }
    }
}
