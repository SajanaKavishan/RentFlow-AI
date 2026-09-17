namespace RentFlow.Api.Models;
///Represents a rental property listed by a landord
public class Property
{
    public Guid Id{ get; set;}=Guid.NewGuid();
    public Guid LandlordId { get; set; }

    public ApplicationUser Landlord { get; set; } = null!;

    public string Title{get; set;}=string.Empty;
    public string Description{get; set;}=string.Empty;
    public string Address { get; set; } = string.Empty;

    public string City { get; set; } = string.Empty;

    public decimal MonthlyRent { get; set; }

    public int Bedrooms { get; set; }

    public int Bathrooms { get; set; }

    public bool IsAvailable { get; set; } = true;

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset? UpdatedAt { get; set; }
}
