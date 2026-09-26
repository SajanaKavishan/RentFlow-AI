namespace RentFlow.Api.Commands;

public interface IAdminBootstrapConsole
{
    bool IsInputInteractive { get; }

    string? ReadLine();

    string ReadSecret();

    void Write(string value);

    void WriteLine(string value);
}
