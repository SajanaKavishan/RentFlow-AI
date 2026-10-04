enum SupportCategory {
  technicalIssue('TechnicalIssue', 'Technical issue'),
  accountLogin('AccountLogin', 'Account & login'),
  propertyApplication('PropertyApplication', 'Property & application'),
  payment('Payment', 'Payment'),
  other('Other', 'Other');

  const SupportCategory(this.value, this.label);
  final String value;
  final String label;
  static SupportCategory parse(Object? value) => values.firstWhere(
    (category) => category.value == value,
    orElse: () => throw const FormatException('Invalid support category.'),
  );
}

enum SupportStatus {
  open('Open', 'Open'),
  inProgress('InProgress', 'In progress'),
  resolved('Resolved', 'Resolved');

  const SupportStatus(this.value, this.label);
  final String value;
  final String label;
  static SupportStatus parse(Object? value) => values.firstWhere(
    (status) => status.value == value,
    orElse: () => throw const FormatException('Invalid support status.'),
  );
}

class SupportTicket {
  const SupportTicket._({
    required this.id,
    required this.category,
    required this.subject,
    required this.message,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id;
  final SupportCategory category;
  final String subject;
  final String message;
  final SupportStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory SupportTicket.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final subject = json['subject'];
    final message = json['message'];
    final created = json['createdAt'];
    final updated = json['updatedAt'];
    final createdAt = created is String ? DateTime.tryParse(created) : null;
    final updatedAt = updated is String ? DateTime.tryParse(updated) : null;
    if (id is! String ||
        id.trim().isEmpty ||
        subject is! String ||
        subject.trim().isEmpty ||
        message is! String ||
        message.trim().isEmpty ||
        createdAt == null ||
        updatedAt == null) {
      throw const FormatException('Invalid support ticket.');
    }
    return SupportTicket._(
      id: id,
      category: SupportCategory.parse(json['category']),
      subject: subject,
      message: message,
      status: SupportStatus.parse(json['status']),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

class CreateSupportTicketRequest {
  const CreateSupportTicketRequest({
    required this.category,
    required this.subject,
    required this.message,
  });
  final SupportCategory category;
  final String subject;
  final String message;

  static String? validateSubject(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Enter a subject.';
    return text.length > 200 ? 'Use no more than 200 characters.' : null;
  }

  static String? validateMessage(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Enter a message.';
    return text.length > 4000 ? 'Use no more than 4,000 characters.' : null;
  }

  String? validate() => validateSubject(subject) ?? validateMessage(message);
  Map<String, dynamic> toJson() => {
    'category': category.value,
    'subject': subject.trim(),
    'message': message.trim(),
  };
}
