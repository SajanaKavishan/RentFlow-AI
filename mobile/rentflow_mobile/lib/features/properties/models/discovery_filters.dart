import 'property.dart';
import 'property_preferences.dart';

class DiscoveryFilters {
  const DiscoveryFilters({
    this.availableOnly = false,
    this.bedrooms,
    this.bathrooms,
    this.city = '',
    this.minRent,
    this.maxRent,
    this.amenities = const {},
  });
  final bool availableOnly;
  final int? bedrooms;
  final int? bathrooms;
  final String city;
  final double? minRent;
  final double? maxRent;
  final Set<String> amenities;

  bool get isEmpty =>
      !availableOnly &&
      bedrooms == null &&
      bathrooms == null &&
      city.isEmpty &&
      minRent == null &&
      maxRent == null &&
      amenities.isEmpty;

  DiscoveryFilters withQuickFilters({
    required bool availableOnly,
    required int? bedrooms,
  }) => DiscoveryFilters(
    availableOnly: availableOnly,
    bedrooms: bedrooms,
    bathrooms: bathrooms,
    city: city,
    minRent: minRent,
    maxRent: maxRent,
    amenities: amenities,
  );

  bool includes(Property property, String search) {
    final query = search.trim().toLowerCase();
    return (!availableOnly || property.isAvailable) &&
        (bedrooms == null || property.bedrooms >= bedrooms!) &&
        (bathrooms == null || property.bathrooms >= bathrooms!) &&
        (city.isEmpty ||
            property.city.toLowerCase() == city.trim().toLowerCase()) &&
        (minRent == null || property.monthlyRent >= minRent!) &&
        (maxRent == null || property.monthlyRent <= maxRent!) &&
        amenities.every(
          (selected) =>
              _propertyAmenities(property).contains(amenityIdentity(selected)),
        ) &&
        (query.isEmpty ||
            [
              property.city,
              property.address,
              property.title,
            ].any((value) => value.toLowerCase().contains(query)));
  }
}

String amenityIdentity(String value) =>
    preferenceAmenityKey(value.trim()) ?? value.trim().toLowerCase();

Set<String> _propertyAmenities(Property property) => {
  ...property.amenities.map(amenityIdentity),
  for (final detail in property.amenityDetails ?? <PropertyAmenityDetail>[])
    amenityIdentity(detail.canonicalKey ?? detail.name),
};
