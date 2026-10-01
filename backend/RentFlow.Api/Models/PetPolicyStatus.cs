using System.Text.Json.Serialization;

namespace RentFlow.Api.Models;

[JsonConverter(typeof(JsonStringEnumConverter<PetPolicyStatus>))]
public enum PetPolicyStatus
{
    Allowed,
    NotAllowed,
    Conditional
}
