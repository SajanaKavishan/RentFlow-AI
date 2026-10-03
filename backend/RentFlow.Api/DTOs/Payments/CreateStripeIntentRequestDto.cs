using System.Text.Json.Serialization;

namespace RentFlow.Api.DTOs.Payments;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed class CreateStripeIntentRequestDto
{
    public Guid RentScheduleItemId { get; set; }
}
