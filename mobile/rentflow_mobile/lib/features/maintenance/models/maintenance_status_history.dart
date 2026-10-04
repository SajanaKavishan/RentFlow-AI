import 'maintenance_request.dart';

class MaintenanceStatusHistory {
  const MaintenanceStatusHistory({
    required this.id,
    required this.fromStatus,
    required this.toStatus,
    required this.changedAt,
    required this.notes,
  });

  final String id;
  final MaintenanceRequestStatus? fromStatus;
  final MaintenanceRequestStatus toStatus;
  final DateTime changedAt;
  final String? notes;

  factory MaintenanceStatusHistory.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('Missing or invalid "id".');
    }

    final changedAt = json['changedAt'];
    if (changedAt is! String) {
      throw const FormatException('Missing or invalid "changedAt".');
    }
    final parsedChangedAt = DateTime.tryParse(changedAt);
    if (parsedChangedAt == null) {
      throw const FormatException('Invalid "changedAt" date.');
    }

    return MaintenanceStatusHistory(
      id: id,
      fromStatus: json['fromStatus'] == null
          ? null
          : MaintenanceRequestStatus.fromJson(json['fromStatus']),
      toStatus: MaintenanceRequestStatus.fromJson(json['toStatus']),
      changedAt: parsedChangedAt,
      notes: _nullableString(json['notes'], 'notes'),
    );
  }

  static String? _nullableString(Object? value, String key) {
    if (value == null || value is String) return value as String?;
    throw FormatException('Invalid "$key".');
  }
}
