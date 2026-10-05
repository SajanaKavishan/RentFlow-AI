using System.Net.Http.Json;
using System.Text.Json;

namespace RentFlow.Api.Services;

/// <summary>Service credentials belong only to backend-to-agent requests, never user JWTs.</summary>
internal static class AgentServiceRequest
{
    public const string CredentialHeader = "X-RentFlow-Service-Key";
    public const string BudgetHeader = "X-RentFlow-Analysis-Budget-Seconds";

    public static Task<HttpResponseMessage> PostAsync<T>(
        HttpClient client, Uri endpoint, T payload, JsonSerializerOptions jsonOptions,
        string serviceApiKey, CancellationToken cancellationToken, double? budgetSeconds = null)
    {
        return SendAsync(client, endpoint, payload, jsonOptions, serviceApiKey, cancellationToken, budgetSeconds);
    }

    private static async Task<HttpResponseMessage> SendAsync<T>(
        HttpClient client, Uri endpoint, T payload, JsonSerializerOptions jsonOptions,
        string serviceApiKey, CancellationToken cancellationToken, double? budgetSeconds)
    {
        using var message = new HttpRequestMessage(HttpMethod.Post, endpoint)
        {
            Content = JsonContent.Create(payload, options: jsonOptions)
        };
        if (!string.IsNullOrWhiteSpace(serviceApiKey))
            message.Headers.Add(CredentialHeader, serviceApiKey.Trim());
        if (budgetSeconds.HasValue)
            message.Headers.Add(BudgetHeader, budgetSeconds.Value.ToString(System.Globalization.CultureInfo.InvariantCulture));
        return await client.SendAsync(message, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
    }
}
