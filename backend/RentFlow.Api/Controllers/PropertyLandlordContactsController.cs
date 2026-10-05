using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs;
using RentFlow.Api.Models;
using RentFlow.Api.Services;

namespace RentFlow.Api.Controllers;

[ApiController]
[Authorize(Roles = nameof(UserRole.Tenant))]
[Route("api/properties/{propertyId:guid}/landlord-contact")]
public sealed class PropertyLandlordContactsController(ApplicationDbContext dbContext) : ControllerBase
{
    [HttpGet]
    [ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
    public async Task<ActionResult<LandlordContactDto>> Get(Guid propertyId, CancellationToken cancellationToken)
    {
        var contact = await dbContext.Properties.AsNoTracking()
            .Where(property => property.Id == propertyId
                && property.Landlord.IsActive
                && property.Landlord.Role == UserRole.Landlord)
            .Select(property => new
            {
                property.Landlord.FullName,
                property.Landlord.PublicContactEnabled,
                property.Landlord.PublicContactPhone
            }).SingleOrDefaultAsync(cancellationToken);
        if (contact is null) return NotFound();
        var phone = contact.PublicContactEnabled
            ? PhoneNumberValidation.UsablePhoneNumber(contact.PublicContactPhone) : null;
        return phone is null ? NoContent() : Ok(new LandlordContactDto(contact.FullName, phone));
    }
}
