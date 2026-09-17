using System.ComponentModel.DataAnnotations;

namespace RentFlow.Api.DTOs.LeaseAgreements;

public class CreateLeaseAgreementDto
{
    [Required]
    public Guid RentalOfferId { get; set; }
}