enum RepairEstimateStatus {
  draft(0),
  submitted(1),
  revisionRequested(2),
  approved(3),
  rejected(4),
  superseded(5);

  const RepairEstimateStatus(this.value);

  final int value;

  static RepairEstimateStatus fromJson(Object? value) {
    if (value is! int) {
      throw FormatException('Invalid repair estimate status value: $value');
    }

    return switch (value) {
      0 => RepairEstimateStatus.draft,
      1 => RepairEstimateStatus.submitted,
      2 => RepairEstimateStatus.revisionRequested,
      3 => RepairEstimateStatus.approved,
      4 => RepairEstimateStatus.rejected,
      5 => RepairEstimateStatus.superseded,
      _ => throw FormatException(
        'Invalid repair estimate status value: $value',
      ),
    };
  }
}

class RepairEstimate {
  const RepairEstimate({
    required this.id,
    required this.maintenanceRequestId,
    required this.technicianId,
    required this.versionNumber,
    required this.laborCost,
    required this.partsCost,
    required this.additionalCost,
    required this.totalCost,
    required this.notes,
    required this.status,
    required this.createdAt,
    required this.submittedAt,
    required this.reviewedAt,
    required this.reviewNotes,
  });

  final String id;
  final String maintenanceRequestId;
  final String technicianId;
  final int versionNumber;
  final double laborCost;
  final double partsCost;
  final double additionalCost;
  final double totalCost;
  final String? notes;
  final RepairEstimateStatus status;
  final DateTime createdAt;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final String? reviewNotes;

  factory RepairEstimate.fromJson(Map<String, dynamic> json) {
    return RepairEstimate(
      id: _requiredString(json, 'id'),
      maintenanceRequestId: _requiredString(json, 'maintenanceRequestId'),
      technicianId: _requiredString(json, 'technicianId'),
      versionNumber: _requiredInt(json, 'versionNumber'),
      laborCost: _requiredDouble(json, 'laborCost'),
      partsCost: _requiredDouble(json, 'partsCost'),
      additionalCost: _requiredDouble(json, 'additionalCost'),
      totalCost: _requiredDouble(json, 'totalCost'),
      notes: _nullableString(json, 'notes'),
      status: RepairEstimateStatus.fromJson(json['status']),
      createdAt: _requiredDateTime(json, 'createdAt'),
      submittedAt: _nullableDateTime(json, 'submittedAt'),
      reviewedAt: _nullableDateTime(json, 'reviewedAt'),
      reviewNotes: _nullableString(json, 'reviewNotes'),
    );
  }

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

  static int _requiredInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) return value;
    throw FormatException('Missing or invalid "$key".');
  }

  static double _requiredDouble(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is num) return value.toDouble();
    throw FormatException('Missing or invalid "$key".');
  }

  static DateTime _requiredDateTime(Map<String, dynamic> json, String key) {
    final value = _requiredString(json, key);
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw FormatException('Invalid "$key" date.');
    return parsed;
  }

  static DateTime? _nullableDateTime(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String) throw FormatException('Invalid "$key".');
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw FormatException('Invalid "$key" date.');
    return parsed;
  }
}
