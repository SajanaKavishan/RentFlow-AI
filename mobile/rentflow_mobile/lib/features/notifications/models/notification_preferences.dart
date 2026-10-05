class NotificationPreferences {
  const NotificationPreferences._({
    required this.viewingUpdatesEnabled,
    required this.rentalApplicationUpdatesEnabled,
  });

  final bool viewingUpdatesEnabled;
  final bool rentalApplicationUpdatesEnabled;
  bool get accountSecurityUpdatesEnabled => true;

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    final viewing = json['viewingUpdatesEnabled'];
    final applications = json['rentalApplicationUpdatesEnabled'];
    if (viewing is! bool ||
        applications is! bool ||
        json['accountSecurityUpdatesEnabled'] != true) {
      throw const FormatException('Invalid notification preferences.');
    }
    return NotificationPreferences._(
      viewingUpdatesEnabled: viewing,
      rentalApplicationUpdatesEnabled: applications,
    );
  }

  NotificationPreferences copyWith({
    bool? viewingUpdatesEnabled,
    bool? rentalApplicationUpdatesEnabled,
  }) => NotificationPreferences._(
    viewingUpdatesEnabled: viewingUpdatesEnabled ?? this.viewingUpdatesEnabled,
    rentalApplicationUpdatesEnabled:
        rentalApplicationUpdatesEnabled ?? this.rentalApplicationUpdatesEnabled,
  );
}
