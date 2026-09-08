using System.ComponentModel.DataAnnotations;

namespace RentFlow.Api.DTOs.Maintenance;

public class UploadMaintenanceAttachmentDto
{
    [Required]
    public IFormFile File { get; set; } = null!;

    [StringLength(100)]
    public string? AttachmentType { get; set; }
}
