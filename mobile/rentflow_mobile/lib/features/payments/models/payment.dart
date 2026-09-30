enum PaymentStatus {
  pending,
  completed,
  failed;

  static PaymentStatus fromJson(Object? value) {
    if (value is! int) {
      throw FormatException('Invalid payment status value: $value');
    }
    return switch (value) {
      0 => PaymentStatus.pending,
      1 => PaymentStatus.completed,
      2 => PaymentStatus.failed,
      _ => throw FormatException('Invalid payment status value: $value'),
    };
  }
}

class Payment {
  const Payment({
    required this.id,
    required this.rentScheduleItemId,
    required this.tenantId,
    required this.amount,
    required this.paymentMethod,
    required this.transactionReference,
    required this.status,
    required this.paidAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String rentScheduleItemId;
  final String tenantId;
  final double amount;
  final String paymentMethod;
  final String? transactionReference;
  final PaymentStatus status;
  final DateTime? paidAt;
  final DateTime createdAt;
  final DateTime? updatedAt;

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
    id: _requiredString(json, 'id'),
    rentScheduleItemId: _requiredString(json, 'rentScheduleItemId'),
    tenantId: _requiredString(json, 'tenantId'),
    amount: _requiredDouble(json, 'amount'),
    paymentMethod: _requiredString(json, 'paymentMethod'),
    transactionReference: _nullableString(json, 'transactionReference'),
    status: PaymentStatus.fromJson(json['status']),
    paidAt: _nullableTimestamp(json, 'paidAt'),
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
    if (value is num && value.isFinite) return value.toDouble();
    throw FormatException('Missing or invalid "$key".');
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
