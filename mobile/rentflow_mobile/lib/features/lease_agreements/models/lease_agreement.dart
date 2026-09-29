enum LeaseAgreementStatus {
  pending(0),
  active(1),
  terminated(2),
  completed(3);

  const LeaseAgreementStatus(this.value);

  final int value;

  static LeaseAgreementStatus fromJson(Object? value) {
    if (value is! int) {
      throw FormatException('Invalid lease agreement status value: $value');
    }
    return switch (value) {
      0 => LeaseAgreementStatus.pending,
      1 => LeaseAgreementStatus.active,
      2 => LeaseAgreementStatus.terminated,
      3 => LeaseAgreementStatus.completed,
      _ => throw FormatException(
        'Invalid lease agreement status value: $value',
      ),
    };
  }
}

class LeaseAgreement {
  const LeaseAgreement({
    required this.id,
    required this.rentalOfferId,
    required this.tenantId,
    required this.propertyId,
    required this.monthlyRent,
    required this.securityDeposit,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String rentalOfferId;
  final String tenantId;
  final String propertyId;
  final double monthlyRent;
  final double securityDeposit;
  final DateTime startDate;
  final DateTime endDate;
  final LeaseAgreementStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;

  factory LeaseAgreement.fromJson(Map<String, dynamic> json) => LeaseAgreement(
    id: _requiredString(json, 'id'),
    rentalOfferId: _requiredString(json, 'rentalOfferId'),
    tenantId: _requiredString(json, 'tenantId'),
    propertyId: _requiredString(json, 'propertyId'),
    monthlyRent: _requiredDouble(json, 'monthlyRent'),
    securityDeposit: _requiredDouble(json, 'securityDeposit'),
    startDate: _requiredDateOnly(json, 'startDate'),
    endDate: _requiredDateOnly(json, 'endDate'),
    status: LeaseAgreementStatus.fromJson(json['status']),
    createdAt: _requiredTimestamp(json, 'createdAt'),
    updatedAt: _nullableTimestamp(json, 'updatedAt'),
  );

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.trim().isNotEmpty) return value;
    throw FormatException('Missing or invalid "$key".');
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
