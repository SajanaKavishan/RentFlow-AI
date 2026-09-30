namespace RentFlow.Api.Models;

/// <summary>
/// Represents a rental property listed by a landlord.
/// </summary>
public class Property
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public Guid LandlordId { get; set; }

    public ApplicationUser Landlord { get; set; } = null!;

    public string Title { get; set; } = string.Empty;

    public string Description { get; set; } = string.Empty;

    public string Address { get; set; } = string.Empty;

    public string City { get; set; } = string.Empty;

    public double? Latitude { get; set; }

    public double? Longitude { get; set; }

    public string? GooglePlaceId { get; set; }

    public decimal MonthlyRent { get; set; }

    /// <summary>
    /// Public, non-binding deposit advertised before an application is made.
    /// Rental offers and leases remain authoritative for their own deposits.
    /// </summary>
    public decimal? AdvertisedSecurityDeposit { get; set; }

    public int? PreferredLeaseTermMonths { get; set; }

    public PetPolicyStatus? PetPolicy { get; set; }

    public string? PetPolicyNotes { get; set; }

    /// <summary>
    /// Canonical utilities included in advertised monthly rent. Null means the
    /// landlord did not provide utility information; an empty array means none.
    /// </summary>
    public string[]? IncludedUtilities { get; set; }

    public int Bedrooms { get; set; }

    public int Bathrooms { get; set; }

    public decimal? Area { get; set; }

    public string? AreaUnit { get; set; }

    public string? AreaType { get; set; }

    public DateOnly? AvailableFrom { get; set; }

    public bool IsAvailable { get; set; } = true;

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset? UpdatedAt { get; set; }

    public ICollection<PropertyAmenity> Amenities { get; set; }
        = new List<PropertyAmenity>();
    public ICollection<PropertyImage> Images { get; set; }
    = new List<PropertyImage>();  
}
