using System.ComponentModel.DataAnnotations;
using RentFlow.Api.Models;

namespace RentFlow.Api.DTOs.ApplicationDocuments;

/// <summary>
/// Represents a multipart rental application document upload.
/// </summary>
public class UploadApplicationDocumentDto
{
    [Required]
    public IFormFile File { get; set; } = null!;

    [Required]
    public ApplicationDocumentType? DocumentType { get; set; }
}
