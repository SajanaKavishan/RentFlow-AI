using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.Options;
using RentFlow.Api.Configuration;
using RentFlow.Api.DTOs.PropertyMatching;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

public sealed class PropertyMatchingAgentClient(
    HttpClient httpClient,
    IOptions<AgentServiceOptions> options)
    : IPropertyMatchingAgentClient
{
    private static readonly string[] ExpectedSteps =
        ["plan", "analyze_matches", "summarize"];

    private static readonly JsonSerializerOptions JsonOptions =
        new(JsonSerializerDefaults.Web);

    public async Task<PropertyMatchingAgentResponse> AnalyzeAsync(
        PropertyMatchingAgentRequest request,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);

        var serviceOptions = options.Value;

        if (!Uri.TryCreate(
                serviceOptions.BaseUrl,
                UriKind.Absolute,
                out var baseUri)
            || serviceOptions.TimeoutSeconds is < 1 or > 300)
        {
            throw new InvalidOperationException(
                "The property matching agent client is not configured correctly.");
        }

        var endpoint = new Uri(
            baseUri,
            "/internal/property-matching/analyze");

        using var timeoutSource =
            CancellationTokenSource.CreateLinkedTokenSource(
                cancellationToken);

        timeoutSource.CancelAfter(
            TimeSpan.FromSeconds(serviceOptions.TimeoutSeconds));

        HttpResponseMessage response;

        try
        {
            response = await AgentServiceRequest.PostAsync(httpClient,
                endpoint,
                request,
                JsonOptions,
                serviceOptions.ServiceApiKey, timeoutSource.Token);
        }
        catch (OperationCanceledException)
            when (!cancellationToken.IsCancellationRequested)
        {
            throw new InvalidOperationException(
                "The property matching agent timed out.");
        }
        catch (HttpRequestException exception)
        {
            throw new InvalidOperationException(
                "The property matching agent is unavailable.",
                exception);
        }

        using (response)
        {
            if (!response.IsSuccessStatusCode)
            {
                throw new InvalidOperationException(
                    "The property matching agent returned an unsuccessful response.");
            }

            PropertyMatchingAgentResponse? result;

            try
            {
                result = await response.Content
                    .ReadFromJsonAsync<PropertyMatchingAgentResponse>(
                        JsonOptions,
                        timeoutSource.Token);
            }
            catch (JsonException exception)
            {
                throw new InvalidOperationException(
                    "The property matching agent returned invalid JSON.",
                    exception);
            }

            ValidateResponse(request, result);

            return result!;
        }
    }

    private static void ValidateResponse(
        PropertyMatchingAgentRequest request,
        PropertyMatchingAgentResponse? response)
    {
        if (response is null
            || response.Result is null
            || response.Result.Matches is null
            || string.IsNullOrWhiteSpace(response.Result.Summary)
            || string.IsNullOrWhiteSpace(response.Result.AgentVersion)
            || response.ExecutionMetadata is null
            || response.ExecutionMetadata.ExecutedSteps is null
            || !response.ExecutionMetadata.ExecutedSteps.SequenceEqual(
                ExpectedSteps))
        {
            throw new InvalidOperationException(
                "The property matching agent returned an invalid structured response.");
        }

        var candidates = request.Candidates.ToDictionary(
            candidate => candidate.PropertyId);

        foreach (var match in response.Result.Matches)
        {
            if (!candidates.TryGetValue(
                    match.PropertyId,
                    out var candidate))
            {
                throw new InvalidOperationException(
                    "The property matching agent returned an unknown property.");
            }

            if (match.MatchScore != candidate.MatchScore)
            {
                throw new InvalidOperationException(
                    "The property matching agent changed a deterministic match score.");
            }
        }
    }
}