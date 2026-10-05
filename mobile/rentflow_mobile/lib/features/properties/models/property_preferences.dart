import 'property_matching.dart';

/// The same tenant-owned record returned to the web application.
class PropertyPreferences extends PropertyMatchingRequest {
  const PropertyPreferences({
    required this.isConfigured,
    super.preferredCity,
    super.maximumMonthlyRent,
    super.minimumBedrooms,
    super.minimumBathrooms,
    super.preferredAmenities,
  });

  final bool isConfigured;

  factory PropertyPreferences.fromJson(Map<String, dynamic> json) {
    if (json['isConfigured'] is! bool) throw const FormatException();
    final amenities = json['preferredAmenities'] ?? <String>[];
    if (amenities is! List || amenities.any((item) => item is! String)) {
      throw const FormatException();
    }
    final city = json['preferredCity'];
    final rent = json['maximumMonthlyRent'];
    final beds = json['minimumBedrooms'];
    final baths = json['minimumBathrooms'];
    if ((city != null && city is! String) ||
        (rent != null && rent is! num) ||
        (beds != null && beds is! int) ||
        (baths != null && baths is! int)) {
      throw const FormatException();
    }
    return PropertyPreferences(
      isConfigured: json['isConfigured'] as bool,
      preferredCity: city as String?,
      maximumMonthlyRent: (rent as num?)?.toDouble(),
      minimumBedrooms: beds as int?,
      minimumBathrooms: baths as int?,
      preferredAmenities: List<String>.from(amenities),
    );
  }
}

/// Keys and labels mirror web propertyListingCatalog.js and the backend
/// PropertyListingCatalog. The preference API normalizes keys to these labels.
const propertyAmenityCatalog = <String, String>{
  'wifi': 'Wi-Fi',
  'parking': 'Parking',
  'air-conditioning': 'Air conditioning',
  'washer-dryer': 'Washer / dryer',
  'gym': 'Gym',
  'swimming-pool': 'Swimming pool',
  'balcony': 'Balcony',
  'elevator': 'Elevator',
  'furnished': 'Furnished',
  'garden': 'Garden',
  'security': 'Security',
  'rooftop': 'Rooftop',
};

String? preferenceAmenityKey(String value) {
  for (final entry in propertyAmenityCatalog.entries) {
    if (entry.key.toLowerCase() == value.toLowerCase() ||
        entry.value.toLowerCase() == value.toLowerCase()) {
      return entry.key;
    }
  }
  return null;
}
