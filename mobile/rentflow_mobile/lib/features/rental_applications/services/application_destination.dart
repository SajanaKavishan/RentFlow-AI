import 'package:flutter/material.dart';
import '../models/rental_application.dart';
import '../screens/rental_application_details_screen.dart';
import '../screens/rental_application_form_screen.dart';
import 'rental_application_api_service.dart';

/// Rechecks Task 3 eligibility and loads the existing application before navigation.
Future<Widget> applicationDestination({
  required String propertyId,
  String? propertyTitle,
  required RentalApplicationApiService apiService,
  bool allowNew = true,
}) async {
  final eligibility = await apiService.getEligibility(propertyId);
  if (eligibility.hasExistingApplication) {
    final application = await apiService.getApplicationById(
      eligibility.existingApplicationId!,
    );
    if (application.propertyId != propertyId ||
        application.id != eligibility.existingApplicationId) {
      throw const RentalApplicationApiException(
        'The application response was invalid.',
      );
    }
    return application.status == RentalApplicationStatus.draft ||
            application.status == RentalApplicationStatus.changesRequested
        ? RentalApplicationFormScreen(
            propertyId: propertyId,
            propertyTitle: propertyTitle,
            application: application,
            rentalApplicationApiService: apiService,
          )
        : RentalApplicationDetailsScreen(
            application: application,
            rentalApplicationApiService: apiService,
          );
  }
  if (!eligibility.canApply || !allowNew) {
    throw RentalApplicationApiException(
      eligibility.reason ??
          'This property is not currently available for an application.',
    );
  }
  return RentalApplicationFormScreen(
    propertyId: propertyId,
    propertyTitle: propertyTitle,
    rentalApplicationApiService: apiService,
  );
}
