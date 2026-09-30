import 'rent_schedule_item.dart';

class RentScheduleOutstandingSummary {
  const RentScheduleOutstandingSummary({
    required this.totalPending,
    required this.totalOverdue,
    required this.totalOutstanding,
    required this.items,
  });

  final double totalPending;
  final double totalOverdue;
  final double totalOutstanding;
  final List<RentScheduleItem> items;

  factory RentScheduleOutstandingSummary.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    if (rawItems is! List<dynamic>) {
      throw const FormatException('Missing or invalid "items".');
    }

    return RentScheduleOutstandingSummary(
      totalPending: _requiredDouble(json, 'totalPending'),
      totalOverdue: _requiredDouble(json, 'totalOverdue'),
      totalOutstanding: _requiredDouble(json, 'totalOutstanding'),
      items: rawItems
          .map((item) {
            if (item is! Map<String, dynamic>) {
              throw const FormatException('Invalid rent schedule item.');
            }
            return RentScheduleItem.fromJson(item);
          })
          .toList(growable: false),
    );
  }

  static double _requiredDouble(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is num && value.isFinite) return value.toDouble();
    throw FormatException('Missing or invalid "$key".');
  }
}
