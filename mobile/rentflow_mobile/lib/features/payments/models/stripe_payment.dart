import 'payment.dart';

class StripeIntentResponse {
  const StripeIntentResponse({
    required this.paymentId,
    required this.clientSecret,
    required this.publishableKey,
    required this.amount,
    required this.currency,
    required this.paymentStatus,
    required this.status,
  });

  final String paymentId;
  final String? clientSecret;
  final String publishableKey;
  final double amount;
  final String currency;
  final PaymentStatus paymentStatus;
  final String status;

  factory StripeIntentResponse.fromJson(Map<String, dynamic> json) =>
      StripeIntentResponse(
        paymentId: _requiredString(json, 'paymentId'),
        clientSecret: _optionalString(json, 'clientSecret'),
        publishableKey: _requiredString(json, 'publishableKey'),
        amount: _requiredAmount(json),
        currency: _requiredCurrency(json),
        paymentStatus: PaymentStatus.fromJson(json['paymentStatus']),
        status: _requiredString(json, 'status'),
      );
}

class StripePaymentStatusResponse {
  const StripePaymentStatusResponse({
    required this.paymentId,
    required this.paymentStatus,
    required this.status,
    required this.paidAt,
  });

  final String paymentId;
  final PaymentStatus paymentStatus;
  final String status;
  final DateTime? paidAt;

  factory StripePaymentStatusResponse.fromJson(Map<String, dynamic> json) =>
      StripePaymentStatusResponse(
        paymentId: _requiredString(json, 'paymentId'),
        paymentStatus: PaymentStatus.fromJson(json['paymentStatus']),
        status: _requiredString(json, 'status'),
        paidAt: _optionalTimestamp(json, 'paidAt'),
      );
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) return value;
  throw FormatException('Invalid $key');
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null || value is String) return value as String?;
  throw FormatException('Invalid $key');
}

double _requiredAmount(Map<String, dynamic> json) {
  final value = json['amount'];
  if (value is num && value.isFinite && value > 0) return value.toDouble();
  throw const FormatException('Invalid amount');
}

String _requiredCurrency(Map<String, dynamic> json) {
  final value = _requiredString(json, 'currency');
  if (value.toLowerCase() == 'lkr') return value;
  throw const FormatException('Unsupported currency');
}

DateTime? _optionalTimestamp(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
    throw FormatException('Invalid $key');
  }
  return DateTime.tryParse(value)?.toUtc() ??
      (throw FormatException('Invalid $key'));
}
