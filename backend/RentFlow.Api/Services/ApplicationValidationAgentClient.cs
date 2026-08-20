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
        "verify_supporting_documents",
        "analyze_cross_document_consistency",
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

    private static readonly HashSet<string> AllowedDocumentTypes =
        ["IncomeProof", "EmploymentLetter", "IdentityDocument"];

    private static readonly HashSet<string> AllowedDocumentCategories =
        ["IncomeProof", "EmploymentLetter", "IdentityDocument", "Unknown"];

    private static readonly HashSet<string> AllowedConfidenceLabels =
        ["Low", "Medium", "High", "Unknown"];

    private static readonly HashSet<string> AllowedExtractionMethods =
        ["PdfText", "VisionOcr", "None"];

    private static readonly HashSet<string> AllowedConsistencyComparisons =
    [
        "occupation_vs_job_title",
        "monthly_income_vs_income_amount",
        "applicant_name_consistency",
        "employer_name_consistency",
        "document_category_vs_uploaded_type"
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
            || response.Result.SupportingDocumentVerification is null
            || !HasSafeDocumentVerification(request, response.Result)
            || !HasSafeConsistencyResult(response.Result.CrossDocumentConsistency)
            || !AllowedRecommendations.Contains(response.Result.Recommendation)
            || response.ExecutionMetadata is null
            || response.ExecutionMetadata.ExecutedSteps is null
            || !response.ExecutionMetadata.ExecutedSteps.SequenceEqual(ExpectedExecutionSteps))
        {
            throw MalformedResponse();
        }
    }

    private static bool HasSafeDocumentVerification(
        ApplicationValidationAgentRequest request,
        AgenticApplicationReviewResult result)
    {
        var inputs = request.SupportingDocuments.ToDictionary(document => document.DocumentId);
        if (result.SupportingDocumentVerification.Count != inputs.Count)
        {
            return false;
        }
        foreach (var verification in result.SupportingDocumentVerification)
        {
            if (!inputs.TryGetValue(verification.DocumentId, out var input)
                || !string.Equals(
                    verification.DocumentType,
                    input.DocumentType.ToString(),
                    StringComparison.Ordinal)
                || verification.ExtractedFacts is null
                || verification.Warnings is null
                || !AllowedDocumentTypes.Contains(verification.DocumentType)
                || !AllowedDocumentCategories.Contains(verification.DetectedDocumentCategory)
                || !AllowedConfidenceLabels.Contains(verification.ConfidenceLabel)
                || !AllowedExtractionMethods.Contains(verification.ExtractionMethod)
                || (!verification.Readable && !verification.RequiresManualReview)
                || (verification.ConfidenceLabel is "Low" or "Unknown"
                    && !verification.RequiresManualReview))
            {
                return false;
            }

            var facts = verification.ExtractedFacts;
            if (!verification.Readable
                && (facts.ApplicantName is not null
                    || facts.IncomeAmount is not null
                    || facts.PayPeriod is not null
                    || facts.EmployerName is not null
                    || facts.JobTitle is not null
                    || facts.DocumentDate is not null))
            {
                return false;
            }

            if (input.DocumentType == RentFlow.Api.Models.ApplicationDocumentType.IdentityDocument
                && (facts.IncomeAmount is not null
                    || facts.PayPeriod is not null
                    || facts.EmployerName is not null
                    || facts.JobTitle is not null
                    || facts.DocumentDate is not null))
            {
                return false;
            }

            if (input.DocumentType == RentFlow.Api.Models.ApplicationDocumentType.IncomeProof
                && facts.JobTitle is not null)
            {
                return false;
            }

            if (input.DocumentType == RentFlow.Api.Models.ApplicationDocumentType.EmploymentLetter
                && (facts.IncomeAmount is not null || facts.PayPeriod is not null))
            {
                return false;
            }
        }

        return true;
    }

    private static bool HasSafeConsistencyResult(CrossDocumentConsistencyResult result)
    {
        if (result is null
            || result.MatchedFacts is null
            || result.Mismatches is null
            || result.Warnings is null)
        {
            return false;
        }

        return result.MatchedFacts.Concat(result.Mismatches).All(finding =>
            finding is not null
            && AllowedConsistencyComparisons.Contains(finding.Comparison)
            && !string.IsNullOrWhiteSpace(finding.Message));
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
