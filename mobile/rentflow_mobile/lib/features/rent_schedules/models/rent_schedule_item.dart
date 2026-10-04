enum RentScheduleStatus {
  pending,
  paid,
  overdue;

  static RentScheduleStatus fromJson(Object? value) {
    if (value is! int) {
      throw FormatException('Invalid rent schedule status value: $value');
    }
    return switch (value) {
      0 => RentScheduleStatus.pending,
      1 => RentScheduleStatus.paid,
      2 => RentScheduleStatus.overdue,
      _ => throw FormatException('Invalid rent schedule status value: $value'),
    };
  }
}

class RentScheduleItem {
  const RentScheduleItem({
    required this.id,
    required this.leaseAgreementId,
    required this.dueDate,
    required this.amount,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String leaseAgreementId;
  final DateTime dueDate;
  final double amount;
  final RentScheduleStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;

  factory RentScheduleItem.fromJson(Map<String, dynamic> json) =>
      RentScheduleItem(
        id: _requiredString(json, 'id'),
        leaseAgreementId: _requiredString(json, 'leaseAgreementId'),
        dueDate: _requiredDateOnly(json, 'dueDate'),
        amount: _requiredDouble(json, 'amount'),
        status: RentScheduleStatus.fromJson(json['status']),
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
    if (value is num && value.isFinite) return value.toDouble();
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
