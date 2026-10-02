import 'property.dart';

/// Display status only; listing eligibility still comes from isAvailable.
enum PropertyAvailability {
  unavailable,
  availableNow,
  availableSoon;

  String get label => switch (this) {
    unavailable => 'Unavailable',
    availableNow => 'Available now',
    availableSoon => 'Available soon',
  };

  /// Defaults to the device's current calendar date. Tests can supply today.
  /// Calendar components are compared without converting either date to UTC.
  static PropertyAvailability fromProperty(
    Property property, {
    DateTime? today,
  }) {
    if (!property.isAvailable) return unavailable;
    final date = property.availableFrom;
    if (date == null) return availableNow;
    final currentDate = today ?? DateTime.now();
    return _calendarDate(date) > _calendarDate(currentDate)
        ? availableSoon
        : availableNow;
  }
}

int _calendarDate(DateTime date) =>
    date.year * 10000 + date.month * 100 + date.day;
