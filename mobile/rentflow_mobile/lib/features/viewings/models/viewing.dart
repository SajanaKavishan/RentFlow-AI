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

class ViewingTenantSummary {
  const ViewingTenantSummary({this.displayName = 'Tenant', this.phoneNumber});

  final String displayName;
  final String? phoneNumber;

  factory ViewingTenantSummary.fromJson(Object? value) {
    if (value == null) return const ViewingTenantSummary();
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid viewing tenant summary.');
    }
    final name = value['displayName'];
    final phone = value['phoneNumber'];
    if ((name != null && name is! String) ||
        (phone != null && phone is! String)) {
      throw const FormatException('Invalid viewing tenant summary.');
    }
    final displayName = (name as String?)?.trim();
    return ViewingTenantSummary(
      displayName: displayName == null || displayName.isEmpty
          ? 'Tenant'
          : displayName,
      phoneNumber: usablePhone(phone as String?),
    );
  }

  static String? usablePhone(String? value) {
    final phone = value?.trim();
    if (phone == null ||
        !RegExp(r'^[+0-9][0-9\s().-]{6,31}$').hasMatch(phone)) {
      return null;
    }
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length >= 7 && digits.length <= 15 ? phone : null;
  }

  Uri? get dialerUri {
    final phone = usablePhone(phoneNumber);
    if (phone == null) return null;
    return Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[\s().-]'), ''));
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
    this.propertyTitle,
    this.durationMinutes,
    this.timeZoneId,
    this.requestedLocalDate,
    this.requestedDisplayTime,
    this.tenant = const ViewingTenantSummary(),
    this.canCancel = false,
    this.cancellationDeadline,
    this.canMarkCompleted = false,
    this.completionEligibleAt,
  });

  final String id;
  final String tenantId;
  final ViewingTenantSummary tenant;
  final String propertyId;
  final String? propertyTitle;
  final int? durationMinutes;
  final DateTime requestedDateTime;
  final ViewingStatus status;
  final String? tenantMessage;
  final String? landlordResponse;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? timeZoneId;
  final String? requestedLocalDate;
  final String? requestedDisplayTime;

  /// Server eligibility; missing eligibility fails closed on older responses.
  final bool canCancel;
  final DateTime? cancellationDeadline;

  /// Server completion permission; device time never grants this action.
  final bool canMarkCompleted;
  final DateTime? completionEligibleAt;

  factory Viewing.fromJson(Map<String, dynamic> json) {
    return Viewing(
      id: _requiredString(json, 'id'),
      tenantId: _requiredString(json, 'tenantId'),
      tenant: ViewingTenantSummary.fromJson(json['tenant']),
      propertyId: _requiredString(json, 'propertyId'),
      propertyTitle: _nullableString(json, 'propertyTitle'),
      durationMinutes: _nullableInt(json, 'durationMinutes'),
      requestedDateTime: _requiredDateTime(json, 'requestedDateTime'),
      status: ViewingStatus.fromJson(json['status']),
      canCancel: _canCancel(json),
      cancellationDeadline: _nullableDateTime(json, 'cancellationDeadline'),
      canMarkCompleted: _optionalBool(json, 'canMarkCompleted'),
      completionEligibleAt: _nullableDateTime(json, 'completionEligibleAt'),
      tenantMessage: _nullableString(json, 'tenantMessage'),
      landlordResponse: _nullableString(json, 'landlordResponse'),
      createdAt: _requiredDateTime(json, 'createdAt'),
      updatedAt: _nullableDateTime(json, 'updatedAt'),
      timeZoneId: _nullableString(json, 'timeZoneId'),
      requestedLocalDate: _nullableString(json, 'requestedLocalDate'),
      requestedDisplayTime: _nullableString(json, 'requestedDisplayTime'),
    );
  }

  static bool _canCancel(Map<String, dynamic> json) {
    return _optionalBool(json, 'canCancel');
  }

  static int? _nullableInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null || value is int) return value as int?;
    throw FormatException('Invalid "$key".');
  }

  static bool _optionalBool(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return false;
    if (value is bool) return value;
    throw FormatException('Invalid "$key".');
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
