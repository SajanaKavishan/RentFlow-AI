using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.Options;
using RentFlow.Api.Configuration;
using RentFlow.Api.DTOs.PricingAnalysis;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

public sealed class PricingAnalysisAgentClient(
    HttpClient httpClient,
    IOptions<AgentServiceOptions> options) : IPricingAnalysisAgentClient
{
    public async Task<PricingAnalysisAgentResponse> AnalyzeAsync(
        PricingAnalysisAgentRequest request,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);
        var serviceOptions = options.Value;
        if (!Uri.TryCreate(serviceOptions.BaseUrl, UriKind.Absolute, out var baseUri)
            || (baseUri.Scheme != Uri.UriSchemeHttp && baseUri.Scheme != Uri.UriSchemeHttps)
            || serviceOptions.TimeoutSeconds is < 1 or > 300)
        {
            throw new PricingAnalysisAgentClientException(
                PricingAnalysisAgentClientError.Configuration,
                "The pricing analysis agent client is not configured correctly.");
        }

        if (!PricingAnalysisResponseMapper.IsValidRequest(request))
        {
            throw new PricingAnalysisAgentClientException(
                PricingAnalysisAgentClientError.Configuration,
                "The pricing analysis request is not valid for the configured agent contract.");
        }

        var endpoint = new Uri(baseUri, "/internal/pricing-analysis/analyze");
        using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeoutSource.CancelAfter(TimeSpan.FromSeconds(serviceOptions.TimeoutSeconds));

        HttpResponseMessage response;
        try
        {
            response = await AgentServiceRequest.PostAsync(httpClient,
                endpoint,
                request,
                PricingAnalysisResponseMapper.JsonOptions,
                serviceOptions.ServiceApiKey, timeoutSource.Token);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw TimeoutException();
        }
        catch (HttpRequestException)
        {
            throw new PricingAnalysisAgentClientException(
                PricingAnalysisAgentClientError.ServiceUnavailable,
                "The pricing analysis agent is unavailable.");
        }

        using (response)
        {
            if (!response.IsSuccessStatusCode)
            {
                throw new PricingAnalysisAgentClientException(
                    PricingAnalysisAgentClientError.UpstreamFailure,
                    "The pricing analysis agent returned an unsuccessful response.");
            }

            PricingAnalysisAgentResponse? agentResponse;
            try
            {
                agentResponse = await response.Content.ReadFromJsonAsync<PricingAnalysisAgentResponse>(
                    PricingAnalysisResponseMapper.JsonOptions,
                    timeoutSource.Token);
            }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
            {
                throw TimeoutException();
            }
            catch (JsonException)
            {
                throw PricingAnalysisResponseMapper.MalformedResponse();
            }
            catch (NotSupportedException)
            {
                throw PricingAnalysisResponseMapper.MalformedResponse();
            }
            catch (HttpRequestException)
            {
                throw new PricingAnalysisAgentClientException(
                    PricingAnalysisAgentClientError.ServiceUnavailable,
                    "The pricing analysis agent is unavailable.");
            }

            PricingAnalysisResponseMapper.ValidateResponse(request, agentResponse);
            return agentResponse!;
        }
    }

    private static PricingAnalysisAgentClientException TimeoutException() => new(
        PricingAnalysisAgentClientError.Timeout,
        "The pricing analysis agent timed out.");
}
