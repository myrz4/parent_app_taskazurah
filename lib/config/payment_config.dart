import 'package:flutter/foundation.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

class PaymentConfig {
  PaymentConfig._();

  static const String _defaultStripePublishableKey =
      'pk_test_51TY3hRQwTQk7bQARq6BVlbL3Vnk7N8Qwkvzf8ep7Vq1oo3n7MmV6yyJUiGu50EHRtO010g0xz7Hge2IgsEm9GaYM007a29Iltq';

  // Allow local launch-time overrides, but keep a test publishable key
  // available so the demo flow works from the normal workspace run path.
  static const String stripePublishableKey = String.fromEnvironment(
    'STRIPE_PUBLISHABLE_KEY',
  );

  static String get resolvedStripePublishableKey {
    final runtimeKey = stripePublishableKey.trim();
    if (runtimeKey.isNotEmpty) {
      return runtimeKey;
    }
    return _defaultStripePublishableKey;
  }

  static String? get stripeConfigError {
    final key = resolvedStripePublishableKey.trim();
    if (key.isEmpty) {
      return 'Stripe demo is not configured. Launch the app with '
          '--dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_...';
    }
    if (!key.startsWith('pk_test_')) {
      return 'Stripe demo only accepts Stripe test publishable keys '
          '(pk_test_...).';
    }
    return null;
  }

  static bool get isStripeConfigured => stripeConfigError == null;

  static Future<void> initStripe() async {
    final configError = stripeConfigError;
    if (configError != null) {
      debugPrint('Stripe demo disabled: $configError');
      return;
    }

    Stripe.publishableKey = resolvedStripePublishableKey.trim();
    await Stripe.instance.applySettings();
  }
}