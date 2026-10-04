/// Calendar dates are already resolved in the property's timezone by the API.
/// Keep their year/month/day components; converting to device-local time would
/// shift dates for tenants in a different timezone.
class ViewingDates {
  ViewingDates._({
    required this.propertyId,
    required this.timeZoneId,
    required this.firstDate,
    required this.lastDate,
    required this.availableDates,
    required this.state,
  });

  final String propertyId;
  final String timeZoneId;
  final DateTime firstDate;
  final DateTime lastDate;
  final Set<DateTime> availableDates;
  final String state;

  bool isSelectable(DateTime date) =>
      availableDates.contains(DateTime(date.year, date.month, date.day));

  factory ViewingDates.fromJson(Map<String, dynamic> json) {
    final propertyId = json['propertyId'];
    final timeZoneId = json['timeZoneId'];
    final dates = json['availableDates'];
    final state = json['state'];
    if (propertyId is! String ||
        propertyId.trim().isEmpty ||
        timeZoneId is! String ||
        timeZoneId.trim().isEmpty ||
        dates is! List ||
        !['available', 'empty', 'unconfigured'].contains(state)) {
      throw const FormatException('Invalid viewing dates.');
    }
    final firstDate = _calendarDate(json['firstDate']);
    final lastDate = _calendarDate(json['lastDate']);
    if (lastDate.isBefore(firstDate)) {
      throw const FormatException('Invalid viewing date range.');
    }
    final availableDates = dates.map(_calendarDate).toSet();
    if (availableDates.any(
          (date) => date.isBefore(firstDate) || date.isAfter(lastDate),
        ) ||
        (state == 'available') != availableDates.isNotEmpty) {
      throw const FormatException('Invalid available viewing dates.');
    }
    return ViewingDates._(
      propertyId: propertyId,
      timeZoneId: timeZoneId,
      firstDate: firstDate,
      lastDate: lastDate,
      availableDates: Set.unmodifiable(availableDates),
      state: state as String,
    );
  }

  static DateTime _calendarDate(dynamic value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw const FormatException('Invalid calendar date.');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null ||
        parsed.year != int.parse(value.substring(0, 4)) ||
        parsed.month != int.parse(value.substring(5, 7)) ||
        parsed.day != int.parse(value.substring(8, 10))) {
      throw const FormatException('Invalid calendar date.');
    }
    return DateTime(parsed.year, parsed.month, parsed.day);
  }
}
