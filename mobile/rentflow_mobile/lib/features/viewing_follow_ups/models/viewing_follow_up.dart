import '../../rental_applications/models/application_eligibility.dart';

enum FollowUpDecision {
  applyNow('ApplyNow'),
  notNow('NotNow');

  const FollowUpDecision(this.value);
  final String value;
}

class ViewingFollowUp {
  const ViewingFollowUp({
    required this.id,
    required this.viewingId,
    required this.propertyId,
    required this.title,
    required this.address,
    required this.city,
    required this.application,
  });
  final String id, viewingId, propertyId, title, address, city;
  final ApplicationEligibility application;
  factory ViewingFollowUp.fromJson(Map<String, dynamic> json) {
    String requiredString(Map<String, dynamic> value, String key) {
      final result = value[key];
      if (result is! String || result.trim().isEmpty) {
        throw const FormatException();
      }
      return result;
    }

    final property = json['property'];
    final application = json['application'];
    if (property is! Map<String, dynamic> ||
        application is! Map<String, dynamic> ||
        property['address'] is! String ||
        property['city'] is! String) {
      throw const FormatException();
    }
    return ViewingFollowUp(
      id: requiredString(json, 'followUpId'),
      viewingId: requiredString(json, 'viewingId'),
      propertyId: requiredString(property, 'id'),
      title: requiredString(property, 'title'),
      address: property['address'] as String,
      city: property['city'] as String,
      application: ApplicationEligibility.fromJson(application),
    );
  }
}
