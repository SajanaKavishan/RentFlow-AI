using System.ComponentModel.DataAnnotations;

namespace RentFlow.Api.DTOs.Payments;

public class CreatePaymentDto
{
    [Required]
    public Guid RentScheduleItemId { get; set; }

    [Required]
    [MaxLength(100)]
    public string PaymentMethod { get; set; } = string.Empty;

    [MaxLength(200)]
    public string? TransactionReference { get; set; }
}