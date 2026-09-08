using System.Text.Json;
using System.Text.Json.Serialization;

namespace RentFlow.Api.Models;

[JsonConverter(typeof(UserRoleJsonConverter))]
public enum UserRole
{
    Tenant = 1,
    Landlord = 2,
    MaintenanceTechnician = 3,
    Admin = 4
}

public sealed class UserRoleJsonConverter : JsonConverter<UserRole>
{
    public override UserRole Read(
        ref Utf8JsonReader reader,
        Type typeToConvert,
        JsonSerializerOptions options)
    {
        if (reader.TokenType != JsonTokenType.String
            || !Enum.TryParse<UserRole>(reader.GetString(), ignoreCase: false, out var role)
            || !Enum.IsDefined(role))
        {
            throw new JsonException("Role must be a supported string value.");
        }

        return role;
    }

    public override void Write(
        Utf8JsonWriter writer,
        UserRole value,
        JsonSerializerOptions options)
    {
        if (!Enum.IsDefined(value))
        {
            throw new JsonException("Role is not supported.");
        }

        writer.WriteStringValue(value.ToString());
    }
}
