enum RentalApplicationStatus {
  draft(0),
  submitted(1),
  underReview(2),
  changesRequested(3),
  approved(4),
  rejected(5),
  withdrawn(6);

  const RentalApplicationStatus(this.value);

  final int value;

  static RentalApplicationStatus fromJson(Object? value) {
    if (value is! int) {
      throw FormatException('Invalid rental application status value: $value');
    }

    return switch (value) {
      0 => RentalApplicationStatus.draft,
      1 => RentalApplicationStatus.submitted,
      2 => RentalApplicationStatus.underReview,
      3 => RentalApplicationStatus.changesRequested,
      4 => RentalApplicationStatus.approved,
      5 => RentalApplicationStatus.rejected,
      6 => RentalApplicationStatus.withdrawn,
      _ => throw FormatException(
        'Invalid rental application status value: $value',
      ),
    };
  }
}

class RentalApplication {
  const RentalApplication({
    required this.id,
    required this.tenantId,
    required this.propertyId,
    required this.moveInDate,
    required this.monthlyIncome,
    required this.occupation,
    required this.numberOfOccupants,
    required this.tenantNote,
    required this.status,
    required this.landlordResponse,
    required this.createdAt,
    required this.submittedAt,
    required this.updatedAt,
  });

  final String id;
  final String tenantId;
  final String propertyId;
  final DateTime moveInDate;
  final double monthlyIncome;
  final String occupation;
  final int numberOfOccupants;
  final String? tenantNote;
  final RentalApplicationStatus status;
  final String? landlordResponse;
  final DateTime createdAt;
  final DateTime? submittedAt;
  final DateTime? updatedAt;

  factory RentalApplication.fromJson(Map<String, dynamic> json) {
    return RentalApplication(
      id: _requiredString(json, 'id'),
      tenantId: _requiredString(json, 'tenantId'),
      propertyId: _requiredString(json, 'propertyId'),
      moveInDate: _requiredDateOnly(json, 'moveInDate'),
      monthlyIncome: _requiredDouble(json, 'monthlyIncome'),
      occupation: _requiredString(json, 'occupation'),
      numberOfOccupants: _requiredInt(json, 'numberOfOccupants'),
      tenantNote: _nullableString(json, 'tenantNote'),
      status: RentalApplicationStatus.fromJson(json['status']),
      landlordResponse: _nullableString(json, 'landlordResponse'),
      createdAt: _requiredTimestamp(json, 'createdAt'),
      submittedAt: _nullableTimestamp(json, 'submittedAt'),
      updatedAt: _nullableTimestamp(json, 'updatedAt'),
    );
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
    throw FormatException('Missing or invalid "$key".');
  }

  static String? _nullableString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null || value is String) {
      return value as String?;
    }
    throw FormatException('Invalid "$key".');
  }

  static double _requiredDouble(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is num) return value.toDouble();
    throw FormatException('Missing or invalid "$key".');
  }

  static int _requiredInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) return value;
    throw FormatException('Missing or invalid "$key".');
  }

  static DateTime _requiredDateOnly(Map<String, dynamic> json, String key) {
    final value = _requiredString(json, key);
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw FormatException('Invalid "$key" date.');
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  static DateTime _requiredTimestamp(Map<String, dynamic> json, String key) {
    final value = _requiredString(json, key);
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw FormatException('Invalid "$key" date.');
    return parsed.toUtc();
  }

  static DateTime? _nullableTimestamp(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String) throw FormatException('Invalid "$key".');
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw FormatException('Invalid "$key" date.');
    return parsed.toUtc();
  }
}
