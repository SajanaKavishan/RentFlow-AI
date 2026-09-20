enum ApplicationValidationStatus {
  pending(0, 'Pending'),
  running(1, 'In progress'),
  awaitingHumanReview(2, 'Awaiting Human Review'),
  completed(3, 'Completed'),
  failed(4, 'Failed');

  const ApplicationValidationStatus(this.value, this.label);

  final int value;
  final String label;

  static ApplicationValidationStatus fromJson(Object? value) {
    if (value is! int) throw const FormatException('Invalid validation status.');
    return ApplicationValidationStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => throw const FormatException('Invalid validation status.'),
    );
  }
}

class ApplicationValidationRun {
  const ApplicationValidationRun({
    required this.status,
    required this.requiresHumanApproval,
    required this.createdAt,
    required this.updatedAt,
    required this.summary,
  });

  final ApplicationValidationStatus status;
  final bool requiresHumanApproval;
  final DateTime createdAt;
  final DateTime updatedAt;
  final ApplicationValidationSummary? summary;

  factory ApplicationValidationRun.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'];
    return ApplicationValidationRun(
      status: ApplicationValidationStatus.fromJson(json['status']),
      requiresHumanApproval: _requiredBool(
        json,
        'requiresHumanApproval',
      ),
      createdAt: _requiredTimestamp(json, 'createdAt'),
      updatedAt: _requiredTimestamp(json, 'updatedAt'),
      summary: summary == null
          ? null
          : summary is Map<String, dynamic>
          ? ApplicationValidationSummary.fromJson(summary)
          : throw const FormatException('Invalid validation summary.'),
    );
  }
}

class ApplicationValidationSummary {
  const ApplicationValidationSummary({
    required this.applicationData,
    required this.documents,
    required this.deterministicChecks,
  });

  final ApplicationDataFindings applicationData;
  final DocumentFindings documents;
  final DeterministicCheckFindings deterministicChecks;

  factory ApplicationValidationSummary.fromJson(Map<String, dynamic> json) {
    return ApplicationValidationSummary(
      applicationData: ApplicationDataFindings.fromJson(
        _requiredMap(json, 'applicationData'),
      ),
      documents: DocumentFindings.fromJson(_requiredMap(json, 'documents')),
      deterministicChecks: DeterministicCheckFindings.fromJson(
        _requiredMap(json, 'deterministicRules'),
      ),
    );
  }
}

class ApplicationDataFindings {
  const ApplicationDataFindings({
    required this.isValid,
    required this.missingFields,
    required this.warnings,
  });

  final bool isValid;
  final List<String> missingFields;
  final List<String> warnings;

  factory ApplicationDataFindings.fromJson(Map<String, dynamic> json) {
    return ApplicationDataFindings(
      isValid: _requiredBool(json, 'isValid'),
      missingFields: _stringList(json, 'missingFields'),
      warnings: _stringList(json, 'warnings'),
    );
  }
}

class DocumentFindings {
  const DocumentFindings({
    required this.isValid,
    required this.presentDocumentTypes,
    required this.missingDocumentTypes,
    required this.warnings,
  });

  final bool isValid;
  final List<String> presentDocumentTypes;
  final List<String> missingDocumentTypes;
  final List<String> warnings;

  factory DocumentFindings.fromJson(Map<String, dynamic> json) {
    return DocumentFindings(
      isValid: _requiredBool(json, 'isValid'),
      presentDocumentTypes: _stringList(json, 'presentDocumentTypes'),
      missingDocumentTypes: _stringList(json, 'missingDocumentTypes'),
      warnings: _stringList(json, 'warnings'),
    );
  }
}

class DeterministicCheckFindings {
  const DeterministicCheckFindings({
    required this.passed,
    required this.passedRules,
    required this.failedRules,
    required this.warnings,
  });

  final bool passed;
  final List<String> passedRules;
  final List<String> failedRules;
  final List<String> warnings;

  factory DeterministicCheckFindings.fromJson(Map<String, dynamic> json) {
    return DeterministicCheckFindings(
      passed: _requiredBool(json, 'passed'),
      passedRules: _stringList(json, 'passedRules'),
      failedRules: _stringList(json, 'failedRules'),
      warnings: _stringList(json, 'warnings'),
    );
  }
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is Map<String, dynamic>) return value;
  throw FormatException('Missing or invalid "$key".');
}

bool _requiredBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw FormatException('Missing or invalid "$key".');
}

List<String> _stringList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List<dynamic>) throw FormatException('Invalid "$key".');
  return value.map((item) {
    if (item is String && item.trim().isNotEmpty) return item.trim();
    throw FormatException('Invalid "$key" item.');
  }).toList(growable: false);
}

DateTime _requiredTimestamp(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('Missing or invalid "$key".');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('Invalid "$key" timestamp.');
  return parsed.toUtc();
}
