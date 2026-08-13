/// Basic data shape for a tenant viewing booking.
class Viewing {
  const Viewing({
    required this.id,
    required this.propertyId,
    required this.scheduledAt,
    required this.status,
  });

  final String id;
  final String propertyId;
  final DateTime scheduledAt;
  final String status;
}
