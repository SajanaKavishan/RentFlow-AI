using System.Text.Json.Serialization;

namespace RentFlow.Api.Models;

[JsonConverter(typeof(PreferredAccessWindowJsonConverter))]
public enum PreferredAccessWindow
{
    Morning,
    Afternoon,
    Evening
}

public sealed class PreferredAccessWindowJsonConverter()
    : JsonStringEnumConverter<PreferredAccessWindow>(namingPolicy: null, allowIntegerValues: false);
