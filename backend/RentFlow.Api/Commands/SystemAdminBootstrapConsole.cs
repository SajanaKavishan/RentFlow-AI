using System.Text;

namespace RentFlow.Api.Commands;

public sealed class SystemAdminBootstrapConsole : IAdminBootstrapConsole
{
    public bool IsInputInteractive => !Console.IsInputRedirected;

    public string? ReadLine() => Console.ReadLine();

    public string ReadSecret()
    {
        var password = new StringBuilder();

        while (true)
        {
            var key = Console.ReadKey(intercept: true);
            if (key.Key == ConsoleKey.Enter)
            {
                Console.WriteLine();
                return password.ToString();
            }

            if (key.Key == ConsoleKey.Backspace)
            {
                if (password.Length > 0)
                {
                    password.Length--;
                }

                continue;
            }

            if (!char.IsControl(key.KeyChar))
            {
                password.Append(key.KeyChar);
            }
        }
    }

    public void Write(string value) => Console.Write(value);

    public void WriteLine(string value) => Console.WriteLine(value);
}
