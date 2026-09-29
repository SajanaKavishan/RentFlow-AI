enum RentalOfferStatus {
  pending(0),
  accepted(1),
  rejected(2),
  withdrawn(3),
  expired(4);

  const RentalOfferStatus(this.value);

  final int value;

  static RentalOfferStatus fromJson(Object? value) {
    if (value is! int) {
      throw FormatException('Invalid rental offer status value: $value');
    }
    return switch (value) {
      0 => RentalOfferStatus.pending,
      1 => RentalOfferStatus.accepted,
      2 => RentalOfferStatus.rejected,
      3 => RentalOfferStatus.withdrawn,
      4 => RentalOfferStatus.expired,
      _ => throw FormatException('Invalid rental offer status value: $value'),
    };
  }
}

class RentalOffer {
  const RentalOffer({
    required this.id,
    required this.rentalApplicationId,
    required this.tenantId,
    required this.propertyId,
    required this.monthlyRent,
    required this.securityDeposit,
    required this.proposedStartDate,
    required this.proposedEndDate,
    required this.expiresAt,
    required this.status,
    required this.landlordNote,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String rentalApplicationId;
  final String tenantId;
  final String propertyId;
  final double monthlyRent;
  final double securityDeposit;
  final DateTime proposedStartDate;
  final DateTime proposedEndDate;
  final DateTime expiresAt;
  final RentalOfferStatus status;
  final String? landlordNote;
  final DateTime createdAt;
  final DateTime? updatedAt;

  factory RentalOffer.fromJson(Map<String, dynamic> json) => RentalOffer(
    id: _requiredString(json, 'id'),
    rentalApplicationId: _requiredString(json, 'rentalApplicationId'),
    tenantId: _requiredString(json, 'tenantId'),
    propertyId: _requiredString(json, 'propertyId'),
    monthlyRent: _requiredDouble(json, 'monthlyRent'),
    securityDeposit: _requiredDouble(json, 'securityDeposit'),
    proposedStartDate: _requiredDateOnly(json, 'proposedStartDate'),
    proposedEndDate: _requiredDateOnly(json, 'proposedEndDate'),
    expiresAt: _requiredTimestamp(json, 'expiresAt'),
    status: RentalOfferStatus.fromJson(json['status']),
    landlordNote: _nullableString(json, 'landlordNote'),
    createdAt: _requiredTimestamp(json, 'createdAt'),
    updatedAt: _nullableTimestamp(json, 'updatedAt'),
  );

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.trim().isNotEmpty) return value;
    throw FormatException('Missing or invalid "$key".');
  }

  static String? _nullableString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null || value is String) return value as String?;
    throw FormatException('Invalid "$key".');
  }

  static double _requiredDouble(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is num) return value.toDouble();
    throw FormatException('Missing or invalid "$key".');
  }

  static DateTime _requiredDateOnly(Map<String, dynamic> json, String key) {
    final value = _requiredString(json, key);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw FormatException('Invalid "$key" date.');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null ||
        '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}' !=
            value) {
      throw FormatException('Invalid "$key" date.');
    }
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  static DateTime _requiredTimestamp(Map<String, dynamic> json, String key) {
    final value = _requiredString(json, key);
    final parsed = DateTime.tryParse(value);
    if (parsed == null || !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
      throw FormatException('Invalid "$key" timestamp.');
    }
    return parsed.toUtc();
  }

  static DateTime? _nullableTimestamp(Map<String, dynamic> json, String key) {
    if (json[key] == null) return null;
    return _requiredTimestamp(json, key);
  }
}
