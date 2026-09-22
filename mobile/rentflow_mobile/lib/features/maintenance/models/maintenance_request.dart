enum MaintenanceRequestStatus {
  submitted(0),
  triaged(1),
  assigned(2),
  estimatePending(3),
  estimateSubmitted(4),
  awaitingLandlordApproval(5),
  approved(6),
  rejected(7),
  inProgress(8),
  completed(9),
  cancelled(10);

  const MaintenanceRequestStatus(this.value);

  final int value;

  static MaintenanceRequestStatus fromJson(Object? value) {
    if (value is! int) {
      throw FormatException('Invalid maintenance request status value: $value');
    }

    return switch (value) {
      0 => MaintenanceRequestStatus.submitted,
      1 => MaintenanceRequestStatus.triaged,
      2 => MaintenanceRequestStatus.assigned,
      3 => MaintenanceRequestStatus.estimatePending,
      4 => MaintenanceRequestStatus.estimateSubmitted,
      5 => MaintenanceRequestStatus.awaitingLandlordApproval,
      6 => MaintenanceRequestStatus.approved,
      7 => MaintenanceRequestStatus.rejected,
      8 => MaintenanceRequestStatus.inProgress,
      9 => MaintenanceRequestStatus.completed,
      10 => MaintenanceRequestStatus.cancelled,
      _ => throw FormatException(
        'Invalid maintenance request status value: $value',
      ),
    };
  }
}

enum MaintenanceCategory {
  plumbing(0),
  electrical(1),
  appliance(2),
  structural(3),
  security(4),
  pest(5),
  other(6);

  const MaintenanceCategory(this.value);

  final int value;

  static MaintenanceCategory fromJson(Object? value) {
    if (value is! int) {
      throw FormatException('Invalid maintenance category value: $value');
    }

    return switch (value) {
      0 => MaintenanceCategory.plumbing,
      1 => MaintenanceCategory.electrical,
      2 => MaintenanceCategory.appliance,
      3 => MaintenanceCategory.structural,
      4 => MaintenanceCategory.security,
      5 => MaintenanceCategory.pest,
      6 => MaintenanceCategory.other,
      _ => throw FormatException(
        'Invalid maintenance category value: $value',
      ),
    };
  }
}

enum MaintenancePriority {
  low(0),
  normal(1),
  high(2),
  emergency(3);

  const MaintenancePriority(this.value);

  final int value;

  static MaintenancePriority fromJson(Object? value) {
    if (value is! int) {
      throw FormatException('Invalid maintenance priority value: $value');
    }

    return switch (value) {
      0 => MaintenancePriority.low,
      1 => MaintenancePriority.normal,
      2 => MaintenancePriority.high,
      3 => MaintenancePriority.emergency,
      _ => throw FormatException(
        'Invalid maintenance priority value: $value',
      ),
    };
  }
}

class MaintenanceRequest {
  const MaintenanceRequest({
    required this.id,
    required this.propertyId,
    required this.tenantId,
    required this.technicianId,
    required this.title,
    required this.description,
    required this.category,
    required this.priority,
    required this.status,
    required this.tenantAccessNotes,
    required this.triageNotes,
    required this.assignmentNotes,
    required this.cancellationReason,
    required this.completedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String propertyId;
  final String tenantId;
  final String? technicianId;
  final String title;
  final String description;
  final MaintenanceCategory category;
  final MaintenancePriority priority;
  final MaintenanceRequestStatus status;
  final String? tenantAccessNotes;
  final String? triageNotes;
  final String? assignmentNotes;
  final String? cancellationReason;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;

  factory MaintenanceRequest.fromJson(Map<String, dynamic> json) {
    return MaintenanceRequest(
      id: _requiredString(json, 'id'),
      propertyId: _requiredString(json, 'propertyId'),
      tenantId: _requiredString(json, 'tenantId'),
      technicianId: _nullableString(json, 'technicianId'),
      title: _requiredString(json, 'title'),
      description: _requiredString(json, 'description'),
      category: MaintenanceCategory.fromJson(json['category']),
      priority: MaintenancePriority.fromJson(json['priority']),
      status: MaintenanceRequestStatus.fromJson(json['status']),
      tenantAccessNotes: _nullableString(json, 'tenantAccessNotes'),
      triageNotes: _nullableString(json, 'triageNotes'),
      assignmentNotes: _nullableString(json, 'assignmentNotes'),
      cancellationReason: _nullableString(json, 'cancellationReason'),
      completedAt: _nullableDateTime(json, 'completedAt'),
      createdAt: _requiredDateTime(json, 'createdAt'),
      updatedAt: _nullableDateTime(json, 'updatedAt'),
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

  static DateTime _requiredDateTime(Map<String, dynamic> json, String key) {
    final value = _requiredString(json, key);
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw FormatException('Invalid "$key" date.');
    }
    return parsed;
  }

  static DateTime? _nullableDateTime(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw FormatException('Invalid "$key".');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw FormatException('Invalid "$key" date.');
    }
    return parsed;
  }
}
