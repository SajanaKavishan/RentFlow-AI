using System.Net;
using System.Text;
using Microsoft.Extensions.Options;
using RentFlow.Api.Configuration;
using RentFlow.Api.DTOs.ApplicationValidation;
using RentFlow.Api.Services;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public class ApplicationValidationAgentClientTests
{
    [Fact]
    public async Task AnalyzeAsync_DeserializesAndValidatesSuccessfulStructuredResponse()
    {
        var request = CreateRequest();
        var handler = new StubHttpMessageHandler((message, _) => Task.FromResult(
            JsonResponse(CreateSuccessJson(request.WorkflowId, request.ApplicationId))));
        var client = CreateClient(handler);

        var result = await client.AnalyzeAsync(request);

        Assert.Equal("Ready for landlord review", result.Recommendation);
        Assert.True(result.RequiresHumanApproval);
        Assert.Equal("python-test", result.AgentVersion);
        Assert.Equal(
            "/internal/application-validation/analyze",
            handler.LastRequest!.RequestUri!.AbsolutePath);
    }

    [Fact]
    public async Task AnalyzeAsync_RequestNeverContainsStorageKeysOrUrls()
    {
        var request = CreateRequest();
        string? requestBody = null;
        var handler = new StubHttpMessageHandler(async (message, cancellationToken) =>
        {
            requestBody = await message.Content!.ReadAsStringAsync(cancellationToken);
            return JsonResponse(CreateSuccessJson(request.WorkflowId, request.ApplicationId));
        });
        var client = CreateClient(handler);

        await client.AnalyzeAsync(request);

        Assert.NotNull(requestBody);
        Assert.DoesNotContain("storageKey", requestBody, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("fileBytes", requestBody, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("signedUrl", requestBody, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("publicUrl", requestBody, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("documentMetadata", requestBody, StringComparison.Ordinal);
        Assert.Contains("deterministicFindings", requestBody, StringComparison.Ordinal);
        Assert.Contains("supportingDocuments", requestBody, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AnalyzeAsync_AcceptsSafePhaseBStructuredDocumentResult()
    {
        var documentId = Guid.NewGuid();
        var request = CreateRequest(documentId);
        var handler = new StubHttpMessageHandler((_, _) => Task.FromResult(
            JsonResponse(CreateSuccessJson(
                request.WorkflowId,
                request.ApplicationId,
                documentId))));
        var client = CreateClient(handler);

        var result = await client.AnalyzeAsync(request);

        var verification = Assert.Single(result.SupportingDocumentVerification);
        Assert.Equal("PdfText", verification.ExtractionMethod);
        Assert.Equal("High", verification.ConfidenceLabel);
        Assert.False(verification.RequiresManualReview);
        Assert.Equal("Ada Lovelace", verification.ExtractedFacts.ApplicantName);
        Assert.Equal(5000m, verification.ExtractedFacts.IncomeAmount);
        Assert.Equal("monthly", verification.ExtractedFacts.PayPeriod);
        Assert.Equal("ACME", verification.ExtractedFacts.EmployerName);
        Assert.Equal(new DateOnly(2026, 8, 1), verification.ExtractedFacts.DocumentDate);
        Assert.Contains(result.CrossDocumentConsistency.MatchedFacts,
            finding => finding.Comparison == "monthly_income_vs_income_amount");
        Assert.True(result.RequiresHumanApproval);
    }

    [Fact]
    public async Task AnalyzeAsync_TimeoutIsMappedSafely()
    {
        var handler = new StubHttpMessageHandler(async (_, cancellationToken) =>
        {
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            throw new InvalidOperationException("Unreachable");
        });
        var client = CreateClient(handler, timeoutSeconds: 1);

        var exception = await Assert.ThrowsAsync<ApplicationValidationAgentClientException>(() =>
            client.AnalyzeAsync(CreateRequest()));

        Assert.Equal(ApplicationValidationAgentClientError.Timeout, exception.Error);
        Assert.DoesNotContain("upstream", exception.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task AnalyzeAsync_NonSuccessDoesNotExposeRawUpstreamBody()
    {
        const string sensitiveBody = "provider-secret-and-stack-trace";
        var handler = new StubHttpMessageHandler((_, _) => Task.FromResult(
            new HttpResponseMessage(HttpStatusCode.BadGateway)
            {
                Content = new StringContent(sensitiveBody)
            }));
        var client = CreateClient(handler);

        var exception = await Assert.ThrowsAsync<ApplicationValidationAgentClientException>(() =>
            client.AnalyzeAsync(CreateRequest()));

        Assert.Equal(ApplicationValidationAgentClientError.UpstreamFailure, exception.Error);
        Assert.DoesNotContain(sensitiveBody, exception.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AnalyzeAsync_MalformedResponseIsRejectedSafely()
    {
        var handler = new StubHttpMessageHandler((_, _) => Task.FromResult(
            JsonResponse("{\"workflowId\":\"not-valid\"}")));
        var client = CreateClient(handler);

        var exception = await Assert.ThrowsAsync<ApplicationValidationAgentClientException>(() =>
            client.AnalyzeAsync(CreateRequest()));

        Assert.Equal(ApplicationValidationAgentClientError.MalformedResponse, exception.Error);
        Assert.DoesNotContain("workflowId", exception.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task AnalyzeAsync_ResponseWithoutHumanApprovalIsRejected()
    {
        var request = CreateRequest();
        var body = CreateSuccessJson(request.WorkflowId, request.ApplicationId)
            .Replace("\"requiresHumanApproval\": true", "\"requiresHumanApproval\": false");
        var handler = new StubHttpMessageHandler((_, _) => Task.FromResult(JsonResponse(body)));
        var client = CreateClient(handler);

        var exception = await Assert.ThrowsAsync<ApplicationValidationAgentClientException>(() =>
            client.AnalyzeAsync(request));

        Assert.Equal(ApplicationValidationAgentClientError.MalformedResponse, exception.Error);
    }

    private static ApplicationValidationAgentClient CreateClient(
        StubHttpMessageHandler handler,
        int timeoutSeconds = 5)
    {
        var options = Options.Create(new AgentServiceOptions
        {
            BaseUrl = "http://agent.internal:8001",
            TimeoutSeconds = timeoutSeconds
        });
        return new ApplicationValidationAgentClient(new HttpClient(handler), options);
    }

    private static ApplicationValidationAgentRequest CreateRequest(Guid? documentId = null)
    {
        return new ApplicationValidationAgentRequest
        {
            WorkflowId = Guid.NewGuid(),
            ApplicationId = Guid.NewGuid(),
            Objective = "Summarize for landlord review.",
            ApplicationData = new ApplicationValidationAgentApplicationData
            {
                MoveInDate = new DateOnly(2026, 10, 1),
                MonthlyIncome = 5000,
                Occupation = "Engineer",
                NumberOfOccupants = 2
            },
            DocumentMetadata =
            [
                new ApplicationValidationAgentDocumentMetadata
                {
                    DocumentId = Guid.NewGuid(),
                    DocumentType = "IncomeProof",
                    FileName = "income.pdf",
                    IsRequired = true
                }
            ],
            DeterministicFindings =
            [
                new ApplicationValidationAgentDeterministicFinding
                {
                    Code = "rule.passed",
                    Severity = "info",
                    Message = "Deterministic checks completed."
                }
            ],
            SupportingDocuments = documentId is null
                ? []
                :
                [
                    new SupportingDocumentAnalysisInput
                    {
                        DocumentId = documentId.Value,
                        DocumentType = RentFlow.Api.Models.ApplicationDocumentType.IncomeProof,
                        OriginalFileName = "income.pdf",
                        ContentType = "application/pdf",
                        SizeBytes = 4,
                        ContentBase64 = "JVBERg=="
                    }
                ]
        };
    }

    private static string CreateSuccessJson(
        Guid workflowId,
        Guid applicationId,
        Guid? documentId = null)
    {
        var verification = documentId is null
            ? "[]"
            : $$"""
                [{
                  "documentId": "{{documentId}}",
                  "documentType": "IncomeProof",
                  "readable": true,
                  "detectedDocumentCategory": "IncomeProof",
                  "extractedFacts": {
                    "applicantName": "Ada Lovelace",
                    "incomeAmount": 5000,
                    "payPeriod": "monthly",
                    "employerName": "ACME",
                    "jobTitle": null,
                    "documentDate": "2026-08-01"
                  },
                  "warnings": [],
                  "confidenceLabel": "High",
                  "extractionMethod": "PdfText",
                  "requiresManualReview": false
                }]
                """;
        return $$"""
            {
              "workflowId": "{{workflowId}}",
              "applicationId": "{{applicationId}}",
              "result": {
                "recommendation": "Ready for landlord review",
                "summary": "Ready for manual review.",
                "keyFindings": ["No blocking deterministic findings."],
                "warnings": [],
                "requiresHumanApproval": true,
                "agentVersion": "python-test",
                "supportingDocumentVerification": {{verification}},
                "crossDocumentConsistency": {
                  "matchedFacts": [{
                    "comparison": "monthly_income_vs_income_amount",
                    "message": "Monthly income matched within configured tolerance."
                  }],
                  "mismatches": [],
                  "warnings": [],
                  "requiresManualReview": false
                }
              },
              "executionMetadata": {
                "executedSteps": [
                  "plan",
                  "analyze_application_data",
                  "analyze_document_metadata",
                  "verify_supporting_documents",
                  "analyze_cross_document_consistency",
                  "analyze_consistency",
                  "summarize_findings"
                ]
              }
            }
            """;
    }

    private static HttpResponseMessage JsonResponse(string json)
    {
        return new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json")
        };
    }

    private sealed class StubHttpMessageHandler(
        Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> sendAsync)
        : HttpMessageHandler
    {
        public HttpRequestMessage? LastRequest { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            LastRequest = request;
            return sendAsync(request, cancellationToken);
        }
    }
}
