enum ApplicationDocumentType {
  identityDocument(0, 'Identity Document'),
  incomeProof(1, 'Income Proof'),
  employmentLetter(2, 'Employment Letter'),
  other(3, 'Other');

  const ApplicationDocumentType(this.value, this.label);

  final int value;
  final String label;

  static ApplicationDocumentType fromJson(Object? value) {
    if (value is! int) {
      throw FormatException('Invalid application document type: $value');
    }

    return switch (value) {
      0 => ApplicationDocumentType.identityDocument,
      1 => ApplicationDocumentType.incomeProof,
      2 => ApplicationDocumentType.employmentLetter,
      3 => ApplicationDocumentType.other,
      _ => throw FormatException('Invalid application document type: $value'),
    };
  }
}

class ApplicationDocument {
  const ApplicationDocument({
    required this.id,
    required this.applicationId,
    required this.documentType,
    required this.originalFileName,
    required this.contentType,
    required this.fileSizeBytes,
    required this.uploadedAt,
  });

  final String id;
  final String applicationId;
  final ApplicationDocumentType documentType;
  final String originalFileName;
  final String contentType;
  final int fileSizeBytes;
  final DateTime uploadedAt;

  factory ApplicationDocument.fromJson(Map<String, dynamic> json) {
    return ApplicationDocument(
      id: _requiredString(json, 'id'),
      applicationId: _requiredString(json, 'applicationId'),
      documentType: ApplicationDocumentType.fromJson(json['documentType']),
      originalFileName: _requiredString(json, 'originalFileName'),
      contentType: _requiredString(json, 'contentType'),
      fileSizeBytes: _requiredInt(json, 'fileSizeBytes'),
      uploadedAt: _requiredTimestamp(json, 'uploadedAt'),
    );
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.trim().isNotEmpty) return value;
    throw FormatException('Missing or invalid "$key".');
  }

  static int _requiredInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) return value;
    throw FormatException('Missing or invalid "$key".');
  }

  static DateTime _requiredTimestamp(Map<String, dynamic> json, String key) {
    final parsed = DateTime.tryParse(_requiredString(json, key));
    if (parsed == null) throw FormatException('Invalid "$key" date.');
    return parsed.toUtc();
  }
}
