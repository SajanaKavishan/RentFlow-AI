using System.ComponentModel.DataAnnotations;

namespace RentFlow.Api.DTOs;

public sealed class ReorderPropertyImagesDto
{
    [Required]
    [MinLength(1)]
    public List<Guid> ImageIds { get; set; } = [];
}
