using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.Options;
using RentFlow.Api.Configuration;
using RentFlow.Api.DTOs.ApplicationValidation;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

public class ApplicationValidationAgentClient(
    HttpClient httpClient,
    IOptions<AgentServiceOptions> options) : IApplicationValidationAgentClient
{
    private static readonly string[] ExpectedExecutionSteps =
    [
        "plan",
        "analyze_application_data",
        "analyze_document_metadata",
        "analyze_consistency",
        "summarize_findings"
    ];

    private static readonly HashSet<string> AllowedRecommendations =
    [
        "Ready for landlord review",
        "Request missing information",
        "Request missing documents",
        "Manual review required"
    ];

    public async Task<AgenticApplicationReviewResult> AnalyzeAsync(
        ApplicationValidationAgentRequest request,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);
        var serviceOptions = options.Value;
        if (!Uri.TryCreate(serviceOptions.BaseUrl, UriKind.Absolute, out var baseUri)
            || serviceOptions.TimeoutSeconds is < 1 or > 300)
        {
            throw new ApplicationValidationAgentClientException(
                ApplicationValidationAgentClientError.Configuration,
                "The application validation agent client is not configured correctly.");
        }

        var endpoint = new Uri(baseUri, "/internal/application-validation/analyze");
        using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeoutSource.CancelAfter(TimeSpan.FromSeconds(serviceOptions.TimeoutSeconds));

        HttpResponseMessage response;
        try
        {
            response = await httpClient.PostAsJsonAsync(
                endpoint,
                request,
                ApplicationValidationResponseMapper.JsonOptions,
                timeoutSource.Token);
        }
        catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
        {
            throw new ApplicationValidationAgentClientException(
                ApplicationValidationAgentClientError.Timeout,
                "The application validation agent timed out.",
                exception);
        }
        catch (HttpRequestException exception)
        {
            throw new ApplicationValidationAgentClientException(
                ApplicationValidationAgentClientError.ServiceUnavailable,
                "The application validation agent is unavailable.",
                exception);
        }

        using (response)
        {
            if (!response.IsSuccessStatusCode)
            {
                throw new ApplicationValidationAgentClientException(
                    ApplicationValidationAgentClientError.UpstreamFailure,
                    "The application validation agent returned an unsuccessful response.");
            }

            ApplicationValidationAgentResponse? agentResponse;
            try
            {
                agentResponse = await response.Content.ReadFromJsonAsync<ApplicationValidationAgentResponse>(
                    ApplicationValidationResponseMapper.JsonOptions,
                    timeoutSource.Token);
            }
            catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
            {
                throw new ApplicationValidationAgentClientException(
                    ApplicationValidationAgentClientError.Timeout,
                    "The application validation agent timed out.",
                    exception);
            }
            catch (JsonException exception)
            {
                throw MalformedResponse(exception);
            }
            catch (NotSupportedException exception)
            {
                throw MalformedResponse(exception);
            }

            ValidateResponse(request, agentResponse);
            return agentResponse!.Result;
        }
    }

    private static void ValidateResponse(
        ApplicationValidationAgentRequest request,
        ApplicationValidationAgentResponse? response)
    {
        if (response is null
            || response.WorkflowId != request.WorkflowId
            || response.ApplicationId != request.ApplicationId
            || response.Result is null
            || !response.Result.RequiresHumanApproval
            || string.IsNullOrWhiteSpace(response.Result.Summary)
            || string.IsNullOrWhiteSpace(response.Result.AgentVersion)
            || response.Result.KeyFindings is null
            || response.Result.Warnings is null
            || !AllowedRecommendations.Contains(response.Result.Recommendation)
            || response.ExecutionMetadata is null
            || response.ExecutionMetadata.ExecutedSteps is null
            || !response.ExecutionMetadata.ExecutedSteps.SequenceEqual(ExpectedExecutionSteps))
        {
            throw MalformedResponse();
        }
    }

    private static ApplicationValidationAgentClientException MalformedResponse(
        Exception? innerException = null)
    {
        return new ApplicationValidationAgentClientException(
            ApplicationValidationAgentClientError.MalformedResponse,
            "The application validation agent returned an invalid structured response.",
            innerException);
    }
}
