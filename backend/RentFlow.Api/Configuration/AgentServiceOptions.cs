using System.ComponentModel.DataAnnotations;

namespace RentFlow.Api.Configuration;

public class AgentServiceOptions
{
    public const string SectionName = "AgentService";

    [Required]
    [Url]
    public string BaseUrl { get; set; } = "http://localhost:8001";

    [Range(1, 300)]
    public int TimeoutSeconds { get; set; } = 30;
}
