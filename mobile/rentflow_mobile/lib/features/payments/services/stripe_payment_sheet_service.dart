import 'package:flutter_stripe/flutter_stripe.dart';

abstract class StripePaymentSheetService {
  Future<void> initialize({
    required String publishableKey,
    required String clientSecret,
  });

  Future<void> present();
}

class NativeStripePaymentSheetService implements StripePaymentSheetService {
  const NativeStripePaymentSheetService();

  @override
  Future<void> initialize({
    required String publishableKey,
    required String clientSecret,
  }) async {
    try {
      Stripe.publishableKey = publishableKey;
      await Stripe.instance.applySettings();
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'RentFlow',
        ),
      );
    } catch (_) {
      throw const StripePaymentSheetException();
    }
  }

  @override
  Future<void> present() async {
    try {
      await Stripe.instance.presentPaymentSheet();
    } on StripeException catch (error) {
      if (error.error.code == FailureCode.Canceled) {
        throw const StripePaymentSheetCanceledException();
      }
      throw const StripePaymentSheetException();
    } catch (_) {
      throw const StripePaymentSheetException();
    }
  }
}

class StripePaymentSheetCanceledException implements Exception {
  const StripePaymentSheetCanceledException();
}

class StripePaymentSheetException implements Exception {
  const StripePaymentSheetException();
}
