import 'rental_application.dart';

class ApplicationEligibility {
  const ApplicationEligibility({
    required this.canApply,
    required this.hasCompletedViewing,
    this.reason,
    this.existingApplicationId,
    this.existingApplicationStatus,
  });
  final bool canApply;
  final bool hasCompletedViewing;
  final String? reason;
  final String? existingApplicationId;
  final RentalApplicationStatus? existingApplicationStatus;
  bool get hasExistingApplication => existingApplicationId != null;
  bool get canContinue =>
      existingApplicationStatus == RentalApplicationStatus.draft ||
      existingApplicationStatus == RentalApplicationStatus.changesRequested;
  String get actionLabel => hasExistingApplication
      ? (canContinue ? 'Continue application' : 'View application')
      : canApply
      ? 'Apply Now'
      : 'Apply after viewing';

  factory ApplicationEligibility.fromJson(Map<String, dynamic> json) {
    final canApply = json['canApply'];
    final completed = json['hasCompletedViewing'];
    final id = json['existingApplicationId'];
    final status = json['existingApplicationStatus'];
    final reason = json['reason'];
    if (canApply is! bool ||
        completed is! bool ||
        (reason != null && reason is! String) ||
        (id != null && (id is! String || id.trim().isEmpty)) ||
        ((id == null) != (status == null)) ||
        (canApply && (!completed || id != null))) {
      throw const FormatException('Invalid application eligibility.');
    }
    return ApplicationEligibility(
      canApply: canApply,
      hasCompletedViewing: completed,
      reason: reason as String?,
      existingApplicationId: id as String?,
      existingApplicationStatus: status == null
          ? null
          : RentalApplicationStatus.fromJson(status),
    );
  }
}

class EligibleApplicationProperty {
  const EligibleApplicationProperty({
    required this.id,
    required this.title,
    required this.address,
    required this.city,
    required this.monthlyRent,
  });
  final String id;
  final String title;
  final String address;
  final String city;
  final double monthlyRent;
  factory EligibleApplicationProperty.fromJson(Map<String, dynamic> json) {
    if (json['id'] is! String ||
        (json['id'] as String).isEmpty ||
        json['title'] is! String ||
        json['address'] is! String ||
        json['city'] is! String ||
        json['monthlyRent'] is! num) {
      throw const FormatException('Invalid eligible property.');
    }
    return EligibleApplicationProperty(
      id: json['id'] as String,
      title: json['title'] as String,
      address: json['address'] as String,
      city: json['city'] as String,
      monthlyRent: (json['monthlyRent'] as num).toDouble(),
    );
  }
}
