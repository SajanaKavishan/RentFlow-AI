class MaintenanceAttachment {
  const MaintenanceAttachment({
    required this.id,
    required this.maintenanceRequestId,
    required this.fileName,
    required this.contentType,
    required this.fileSize,
    required this.attachmentType,
    required this.uploadedByUserId,
    required this.createdAt,
  });

  final String id;
  final String maintenanceRequestId;
  final String fileName;
  final String contentType;
  final int fileSize;
  final String? attachmentType;
  final String uploadedByUserId;
  final DateTime createdAt;

  factory MaintenanceAttachment.fromJson(Map<String, dynamic> json) {
    return MaintenanceAttachment(
      id: _requiredString(json, 'id'),
      maintenanceRequestId: _requiredString(json, 'maintenanceRequestId'),
      fileName: _requiredString(json, 'fileName'),
      contentType: _requiredString(json, 'contentType'),
      fileSize: _requiredInt(json, 'fileSize'),
      attachmentType: _nullableString(json, 'attachmentType'),
      uploadedByUserId: _requiredString(json, 'uploadedByUserId'),
      createdAt: _requiredDateTime(json, 'createdAt'),
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
    if (value is int && value >= 0) return value;
    throw FormatException('Missing or invalid "$key".');
  }

  static DateTime _requiredDateTime(Map<String, dynamic> json, String key) {
    final value = _requiredString(json, key);
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw FormatException('Invalid "$key" date.');
    return parsed;
  }
}
