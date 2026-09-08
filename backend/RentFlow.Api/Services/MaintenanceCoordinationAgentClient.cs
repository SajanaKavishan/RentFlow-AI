using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.Options;
using RentFlow.Api.Configuration;
using RentFlow.Api.DTOs.Maintenance;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

public sealed class MaintenanceCoordinationAgentClient(
    HttpClient httpClient,
    IOptions<AgentServiceOptions> options) : IMaintenanceCoordinationAgentClient
{
    private static readonly string[] ExpectedSteps =
    ["plan", "classify_assess_issue", "assess_urgency", "review_maintenance_information", "produce_coordination_recommendation", "summarize"];

    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public async Task<MaintenanceCoordinationAgentResponse> AnalyzeAsync(
        MaintenanceCoordinationAgentRequest request,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);
        var serviceOptions = options.Value;
        if (!Uri.TryCreate(serviceOptions.BaseUrl, UriKind.Absolute, out var baseUri)
            || serviceOptions.TimeoutSeconds is < 1 or > 300)
        {
            throw new MaintenanceCoordinationAgentClientException(
                MaintenanceCoordinationAgentClientError.Configuration,
                "The maintenance coordination agent client is not configured correctly.");
        }

        var endpoint = new Uri(baseUri, "/internal/maintenance-coordination/analyze");
        using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeoutSource.CancelAfter(TimeSpan.FromSeconds(serviceOptions.TimeoutSeconds));
        HttpResponseMessage response;
        try
        {
            response = await httpClient.PostAsJsonAsync(endpoint, request, JsonOptions, timeoutSource.Token);
        }
        catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
        {
            throw new MaintenanceCoordinationAgentClientException(MaintenanceCoordinationAgentClientError.Timeout, "The maintenance coordination agent timed out.", exception);
        }
        catch (HttpRequestException exception)
        {
            throw new MaintenanceCoordinationAgentClientException(MaintenanceCoordinationAgentClientError.ServiceUnavailable, "The maintenance coordination agent is unavailable.", exception);
        }

        using (response)
        {
            if (!response.IsSuccessStatusCode)
            {
                throw new MaintenanceCoordinationAgentClientException(MaintenanceCoordinationAgentClientError.UpstreamFailure, "The maintenance coordination agent returned an unsuccessful response.");
            }

            MaintenanceCoordinationAgentResponse? result;
            try
            {
                result = await response.Content.ReadFromJsonAsync<MaintenanceCoordinationAgentResponse>(JsonOptions, timeoutSource.Token);
            }
            catch (JsonException exception) { throw MalformedResponse(exception); }
            catch (NotSupportedException exception) { throw MalformedResponse(exception); }
            catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
            {
                throw new MaintenanceCoordinationAgentClientException(MaintenanceCoordinationAgentClientError.Timeout, "The maintenance coordination agent timed out.", exception);
            }

            ValidateResponse(request, result);
            return result!;
        }
    }

    private static void ValidateResponse(MaintenanceCoordinationAgentRequest request, MaintenanceCoordinationAgentResponse? response)
    {
        if (response is null || response.MaintenanceRequestId != request.MaintenanceRequestId || response.Result is null
            || string.IsNullOrWhiteSpace(response.Result.RecommendedCategory)
            || string.IsNullOrWhiteSpace(response.Result.RecommendedPriority)
            || string.IsNullOrWhiteSpace(response.Result.NextAction)
            || string.IsNullOrWhiteSpace(response.Result.Reasoning)
            || response.Result.Warnings is null
            || string.IsNullOrWhiteSpace(response.Result.AgentVersion)
            || response.ExecutionMetadata is null
            || response.ExecutionMetadata.ExecutedSteps is null
            || !response.ExecutionMetadata.ExecutedSteps.SequenceEqual(ExpectedSteps))
        {
            throw MalformedResponse();
        }
    }

    private static MaintenanceCoordinationAgentClientException MalformedResponse(Exception? innerException = null) =>
        new(MaintenanceCoordinationAgentClientError.MalformedResponse, "The maintenance coordination agent returned an invalid structured response.", innerException);
}