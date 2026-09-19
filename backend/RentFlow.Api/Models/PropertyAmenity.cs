namespace RentFlow.Api.Models;

public class PropertyAmenity
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public Guid PropertyId { get; set; }

    public string Name { get; set; } = string.Empty;

    public Property Property { get; set; } = null!;
}