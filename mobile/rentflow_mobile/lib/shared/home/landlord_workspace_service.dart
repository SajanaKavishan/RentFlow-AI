import '../../features/properties/services/property_api_service.dart';
import '../../features/viewings/models/viewing.dart';
import '../../features/viewings/services/viewing_api_service.dart';
import '../../features/rental_applications/models/rental_application.dart';
import '../../features/rental_applications/services/rental_application_api_service.dart';

/// Uses the existing owner-scoped property endpoint and existing guarded lists.
/// A partial fetch fails as a whole: it must never cancel another property's reminders.
class LandlordWorkspaceService {
  const LandlordWorkspaceService(this.properties);
  final PropertyApiService properties;

  Future<List<Viewing>> viewings(ViewingApiService service) async {
    final owned = await properties.getMyProperties();
    final result = <Viewing>[];
    for (final property in owned) {
      result.addAll(await service.getViewingsByProperty(property.id));
    }
    result.sort((a, b) => b.requestedDateTime.compareTo(a.requestedDateTime));
    return result;
  }

  Future<List<RentalApplication>> applications(
    RentalApplicationApiService service,
  ) async {
    final owned = await properties.getMyProperties();
    final result = <RentalApplication>[];
    for (final property in owned) {
      result.addAll(await service.getApplicationsByProperty(property.id));
    }
    return result;
  }
}
