enum ViewingStatus {
  pending(0),
  approved(1),
  rejected(2),
  cancelled(3),
  completed(4);

  const ViewingStatus(this.value);

  final int value;

  static ViewingStatus fromJson(Object? value) {
    return switch (value) {
      0 => ViewingStatus.pending,
      1 => ViewingStatus.approved,
      2 => ViewingStatus.rejected,
      3 => ViewingStatus.cancelled,
      4 => ViewingStatus.completed,
      _ => throw FormatException('Invalid viewing status value: $value'),
    };
  }
}

class Viewing {
  const Viewing({
    required this.id,
    required this.tenantId,
    required this.propertyId,
    required this.requestedDateTime,
    required this.status,
    required this.tenantMessage,
    required this.landlordResponse,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String tenantId;
  final String propertyId;
  final DateTime requestedDateTime;
  final ViewingStatus status;
  final String? tenantMessage;
  final String? landlordResponse;
  final DateTime createdAt;
  final DateTime? updatedAt;

  factory Viewing.fromJson(Map<String, dynamic> json) {
    return Viewing(
      id: _requiredString(json, 'id'),
      tenantId: _requiredString(json, 'tenantId'),
      propertyId: _requiredString(json, 'propertyId'),
      requestedDateTime: _requiredDateTime(json, 'requestedDateTime'),
      status: ViewingStatus.fromJson(json['status']),
      tenantMessage: _nullableString(json, 'tenantMessage'),
      landlordResponse: _nullableString(json, 'landlordResponse'),
      createdAt: _requiredDateTime(json, 'createdAt'),
      updatedAt: _nullableDateTime(json, 'updatedAt'),
    );
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) {
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
}
