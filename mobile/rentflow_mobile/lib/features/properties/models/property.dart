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
    );
  }

  static String _requiredString(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = json[key];

    if (value is String && value.isNotEmpty) {
      return value;
    }

    throw FormatException('Missing or invalid "$key".');
  }

  static double _requiredDouble(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = json[key];

    if (value is num) {
      return value.toDouble();
    }

    throw FormatException('Missing or invalid "$key".');
  }

  static int _requiredInt(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = json[key];

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    throw FormatException('Missing or invalid "$key".');
  }

  static bool _requiredBool(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = json[key];

    if (value is bool) {
      return value;
    }

    throw FormatException('Missing or invalid "$key".');
  }

  static DateTime _requiredDateTime(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = _requiredString(json, key);

    return DateTime.tryParse(value) ??
        (throw FormatException('Invalid "$key" date.'));
  }

  static DateTime? _nullableDateTime(
    Map<String, dynamic> json,
    String key,
  ) {
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

  static List<String> _stringList(
    Map<String, dynamic> json,
    String key,
  ) {
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