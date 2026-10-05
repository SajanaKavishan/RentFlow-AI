using System.Security.Cryptography;
using System.Text;

namespace RentFlow.Api.Models;

/// <summary>A display checksum, not an authorization token. PostgreSQL persists the same value.</summary>
public static class MaintenanceReferenceCode
{
    public static string FromId(Guid id) =>
        "MR-" + Convert.ToHexString(MD5.HashData(Encoding.UTF8.GetBytes(id.ToString("D"))))[..16];
}
