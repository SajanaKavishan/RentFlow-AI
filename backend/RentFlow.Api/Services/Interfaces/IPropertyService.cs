using RentFlow.Api.DTOs;

namespace RentFlow.Api.Services.Interfaces;

public interface IPropertyService
{
    Task<IEnumerable<PropertyResponseDto>> GetAllAsync();

    Task<PropertyResponseDto?> GetByIdAsync(Guid id);

    Task<PropertyResponseDto> CreateAsync(
        Guid landlordId,
        CreatePropertyDto dto);

    Task<PropertyResponseDto?> UpdateAsync(
        Guid id,
        Guid landlordId,
        UpdatePropertyDto dto);

    Task<PropertyResponseDto?> UpdateListingAsync(
        Guid id,
        Guid landlordId,
        UpdatePropertyListingDto dto);

    Task<bool> DeleteAsync(
        Guid id,
        Guid landlordId);
}
