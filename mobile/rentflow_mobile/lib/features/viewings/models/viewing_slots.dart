// Weekly API contract: Sunday=0 through Saturday=6 (Dart Sunday=7 maps to 0).
// The tenant sends a calendar date; the backend resolves its property-local weekday.
class ViewingSlot {
  const ViewingSlot({
    required this.localTime,
    required this.displayTime,
    required this.requestedDateTimeIso,
    this.isAvailable = true,
    this.unavailableReason,
  });
  final String localTime;
  final String displayTime;
  final String requestedDateTimeIso;
  final bool isAvailable;
  final String? unavailableReason;
  DateTime get requestedDateTime => DateTime.parse(requestedDateTimeIso);
  factory ViewingSlot.fromJson(Map<String, dynamic> json) {
    final local = json['localTime'],
        display = json['displayTime'],
        instant = json['requestedDateTime'];
    if (local is! String ||
        !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(local) ||
        display is! String ||
        display.trim().isEmpty ||
        instant is! String ||
        DateTime.tryParse(instant)?.isUtc != true ||
        (json['isAvailable'] != null && json['isAvailable'] is! bool) ||
        (json['unavailableReason'] != null &&
            json['unavailableReason'] is! String)) {
      throw const FormatException('Invalid viewing slot.');
    }
    return ViewingSlot(
      localTime: local,
      displayTime: display,
      requestedDateTimeIso: instant,
      isAvailable: json['isAvailable'] as bool? ?? true,
      unavailableReason: json['unavailableReason'] as String?,
    );
  }
}

class ViewingSlots {
  const ViewingSlots({
    required this.date,
    required this.timeZoneId,
    required this.slots,
    required this.state,
    required this.slotDurationMinutes,
  });
  final String date;
  final String timeZoneId;
  final List<ViewingSlot> slots;
  final String state;
  final int slotDurationMinutes;
  factory ViewingSlots.fromJson(Map<String, dynamic> json) {
    if (json['date'] is! String ||
        json['timeZoneId'] is! String ||
        json['slots'] is! List ||
        json['slotDurationMinutes'] is! int ||
        (json['slotDurationMinutes'] as int) <= 0) {
      throw const FormatException('Invalid viewing availability.');
    }
    final slots = (json['slots'] as List)
        .map((item) => ViewingSlot.fromJson(item as Map<String, dynamic>))
        .toList();
    if (slots.map((s) => s.requestedDateTimeIso).toSet().length !=
        slots.length) {
      throw const FormatException('Duplicate viewing slots.');
    }
    return ViewingSlots(
      date: json['date'] as String,
      timeZoneId: json['timeZoneId'] as String,
      slotDurationMinutes: json['slotDurationMinutes'] as int,
      slots: slots,
      state:
          json['state'] as String? ?? (slots.isEmpty ? 'empty' : 'available'),
    );
  }
}
