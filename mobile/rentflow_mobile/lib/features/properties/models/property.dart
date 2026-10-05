class Property {
  const Property({
    required this.id,
    required this.landlordId,
    required this.title,
    required this.description,
    required this.address,
    required this.city,
    required this.monthlyRent,
    required this.bedrooms,
    required this.bathrooms,
    required this.isAvailable,
    required this.createdAt,
    required this.updatedAt,
    required this.amenities,
    this.latitude,
    this.longitude,
    this.googlePlaceId,
    this.area,
    this.areaUnit,
    this.areaType,
    this.availableFrom,
    this.advertisedSecurityDeposit,
    this.preferredLeaseTermMonths,
    this.petPolicy,
    this.petPolicyNotes,
    this.includedUtilities,
    this.amenityDetails,
  });

  final String id;
  final String landlordId;
  final String title;
  final String description;
  final String address;
  final String city;
  final double monthlyRent;
  final int bedrooms;
  final int bathrooms;
  final bool isAvailable;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<String> amenities;
  final double? latitude;
  final double? longitude;
  final String? googlePlaceId;
  final double? area;
  final String? areaUnit;
  final String? areaType;
  final DateTime? availableFrom;
  final double? advertisedSecurityDeposit;
  final int? preferredLeaseTermMonths;
  final String? petPolicy;
  final String? petPolicyNotes;
  final List<String>? includedUtilities;
  final List<PropertyAmenityDetail>? amenityDetails;

  factory Property.fromJson(Map<String, dynamic> json) {
    return Property(
      id: _requiredString(json, 'id'),
      landlordId: _requiredString(json, 'landlordId'),
      title: _requiredString(json, 'title'),
      description: _requiredString(json, 'description'),
      address: _requiredString(json, 'address'),
      city: _requiredString(json, 'city'),
      monthlyRent: _requiredDouble(json, 'monthlyRent'),
      bedrooms: _requiredInt(json, 'bedrooms'),
      bathrooms: _requiredInt(json, 'bathrooms'),
      isAvailable: _requiredBool(json, 'isAvailable'),
      createdAt: _requiredDateTime(json, 'createdAt'),
      updatedAt: _nullableDateTime(json, 'updatedAt'),
      amenities: _stringList(json, 'amenities'),
      latitude: _nullableDouble(json['latitude']),
      longitude: _nullableDouble(json['longitude']),
      googlePlaceId: _nullableString(json['googlePlaceId']),
      area: _nullableDouble(json['area']),
      areaUnit: _nullableString(json['areaUnit']),
      areaType: _nullableString(json['areaType']),
      availableFrom: _nullableDateTime(json, 'availableFrom'),
      advertisedSecurityDeposit: _nullableDouble(
        json['advertisedSecurityDeposit'],
      ),
      preferredLeaseTermMonths: _nullableInt(json['preferredLeaseTermMonths']),
      petPolicy: _nullableString(json['petPolicy']),
      petPolicyNotes: _nullableString(json['petPolicyNotes']),
      includedUtilities: json['includedUtilities'] == null
          ? null
          : _stringList(json, 'includedUtilities'),
      amenityDetails: json['amenityDetails'] is List
          ? (json['amenityDetails'] as List)
                .map((item) {
                  if (item is! Map<String, dynamic>) {
                    throw const FormatException('Invalid amenity detail.');
                  }
                  return PropertyAmenityDetail.fromJson(item);
                })
                .toList(growable: false)
          : null,
    );
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];

    if (value is String && value.isNotEmpty) {
      return value;
    }

    throw FormatException('Missing or invalid "$key".');
  }

  static String? _nullableString(dynamic value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  static double? _nullableDouble(dynamic value) =>
      value is num ? value.toDouble() : null;

  static int? _nullableInt(dynamic value) => value is int ? value : null;

  static double _requiredDouble(Map<String, dynamic> json, String key) {
    final value = json[key];

    if (value is num) {
      return value.toDouble();
    }

    throw FormatException('Missing or invalid "$key".');
  }

  static int _requiredInt(Map<String, dynamic> json, String key) {
    final value = json[key];

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    throw FormatException('Missing or invalid "$key".');
  }

  static bool _requiredBool(Map<String, dynamic> json, String key) {
    final value = json[key];

    if (value is bool) {
      return value;
    }

    throw FormatException('Missing or invalid "$key".');
  }

  static DateTime _requiredDateTime(Map<String, dynamic> json, String key) {
    final value = _requiredString(json, key);

    return DateTime.tryParse(value) ??
        (throw FormatException('Invalid "$key" date.'));
  }

  static DateTime? _nullableDateTime(Map<String, dynamic> json, String key) {
    final value = json[key];

    if (value == null) {
      return null;
    }

    if (value is String) {
      return DateTime.tryParse(value) ??
          (throw FormatException('Invalid "$key" date.'));
    }

    throw FormatException('Invalid "$key".');
  }

  static List<String> _stringList(Map<String, dynamic> json, String key) {
    final value = json[key];

    if (value == null) {
      return const [];
    }

    if (value is List) {
      return value.map((item) {
        if (item is! String) {
          throw FormatException('Invalid item in "$key".');
        }

        return item;
      }).toList();
    }

    throw FormatException('Invalid "$key".');
  }
}

class PropertyAmenityDetail {
  const PropertyAmenityDetail({required this.name, this.canonicalKey});

  final String name;
  final String? canonicalKey;

  factory PropertyAmenityDetail.fromJson(Map<String, dynamic> json) =>
      PropertyAmenityDetail(
        name: json['name'] is String ? json['name'] as String : '',
        canonicalKey: Property._nullableString(json['canonicalKey']),
      );
}
