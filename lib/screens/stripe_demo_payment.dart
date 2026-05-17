import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:intl/intl.dart';

import '../config/payment_config.dart';
import 'stripe_demo_payment_completed.dart';

class StripeDemoPaymentPage extends StatefulWidget {
  const StripeDemoPaymentPage({
    super.key,
    required this.parentId,
    required this.parentName,
    required this.invoiceId,
    required this.invoiceScopeLabel,
    required this.amountSen,
    required this.currency,
  });

  final String parentId;
  final String parentName;
  final String invoiceId;
  final String invoiceScopeLabel;
  final int amountSen;
  final String currency;

  @override
  State<StripeDemoPaymentPage> createState() => _StripeDemoPaymentPageState();
}

class _StripeDemoPaymentPageState extends State<StripeDemoPaymentPage> {
  bool _isBusy = true;
  bool _hasStarted = false;
  String _headline = 'Preparing Stripe demo payment';
  String _detail = 'Creating a secure test-mode checkout session...';
  String _errorMessage = '';
  String _sessionId = '';
  String _paymentIntentId = '';
  int _amountSen = 0;
  String _currency = 'MYR';

  NumberFormat get _money => NumberFormat.currency(
        locale: 'ms_MY',
        symbol: widget.currency.toUpperCase() == 'MYR' ? 'RM' : '${widget.currency} ',
      );

  @override
  void initState() {
    super.initState();
    _amountSen = widget.amountSen;
    _currency = widget.currency;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_hasStarted) return;
      _hasStarted = true;
      _startPaymentFlow();
    });
  }

  Future<void> _startPaymentFlow() async {
    final configError = PaymentConfig.stripeConfigError;
    if (configError != null) {
      setState(() {
        _isBusy = false;
        _headline = 'Stripe demo unavailable';
        _detail = 'Add a Stripe test publishable key and try again.';
        _errorMessage = configError;
      });
      return;
    }

    setState(() {
      _isBusy = true;
      _headline = 'Preparing Stripe demo payment';
      _detail = 'Creating a secure test-mode checkout session...';
      _errorMessage = '';
    });

    try {
      final createData = await _callCallable('createStripeDemoPaymentIntent', {
        'parentId': widget.parentId,
        'invoiceId': widget.invoiceId,
      });
      if (createData['ok'] != true) {
        throw Exception(_responseMessage(
          createData,
          fallback: 'Unable to start Stripe demo payment.',
        ));
      }

      _sessionId = (createData['sessionId'] ?? '').toString().trim();
      _paymentIntentId = (createData['paymentIntentId'] ?? '').toString().trim();
      final rawAmount = createData['amountSen'];
      _amountSen = rawAmount is int
          ? rawAmount
          : (rawAmount is num ? rawAmount.toInt() : widget.amountSen);
      _currency = (createData['currency'] ?? widget.currency).toString().trim();

      if (createData['paid'] == true) {
        await _openCompletionPage(createData);
        return;
      }

      final clientSecret = (createData['clientSecret'] ?? '').toString().trim();
      if (clientSecret.isEmpty) {
        throw Exception('Stripe demo did not return a PaymentIntent client secret.');
      }

      if (!mounted) return;
      setState(() {
        _headline = 'Opening Stripe test card sheet';
        _detail = 'Use card 4242 4242 4242 4242 with any future date and CVC.';
      });

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          merchantDisplayName: 'Taska Zurah',
          paymentIntentClientSecret: clientSecret,
          style: ThemeMode.system,
          billingDetailsCollectionConfiguration:
              const BillingDetailsCollectionConfiguration(
            name: CollectionMode.never,
            email: CollectionMode.never,
            phone: CollectionMode.never,
            address: AddressCollectionMode.never,
          ),
        ),
      );

      await Stripe.instance.presentPaymentSheet();

      if (!mounted) return;
      setState(() {
        _headline = 'Confirming payment';
        _detail = 'Checking the Stripe test PaymentIntent and finalizing your receipt...';
      });

      var completeData = await _callCallable('completeStripeDemoPayment', {
        'parentId': widget.parentId,
        'invoiceId': widget.invoiceId,
        'sessionId': _sessionId,
        'paymentIntentId': _paymentIntentId,
      });

      if (completeData['ok'] != true &&
          (completeData['reason'] ?? '').toString() == 'payment-not-settled') {
        completeData = await _callCallable('syncStripeDemoPayment', {
          'parentId': widget.parentId,
          'invoiceId': widget.invoiceId,
          'sessionId': _sessionId,
          'paymentIntentId': _paymentIntentId,
        });
      }

      if (completeData['ok'] != true || completeData['paid'] != true) {
        throw Exception(_responseMessage(
          completeData,
          fallback: 'Unable to confirm Stripe demo payment yet.',
        ));
      }

      await _openCompletionPage(completeData);
    } on StripeException catch (error) {
      final cancelled = error.error.code == FailureCode.Canceled;
      setState(() {
        _isBusy = false;
        _headline = cancelled ? 'Payment cancelled' : 'Stripe demo failed';
        _detail = cancelled
            ? 'No charge was made. You can try the test payment again.'
            : 'Stripe test-mode checkout could not be completed.';
        _errorMessage = error.error.localizedMessage ??
            (cancelled
                ? 'Payment cancelled.'
                : 'Stripe demo checkout failed.');
      });
    } catch (error) {
      setState(() {
        _isBusy = false;
        _headline = 'Stripe demo failed';
        _detail = 'Please review the message below and try again.';
        _errorMessage = error.toString().replaceFirst('Exception: ', '').trim();
      });
    }
  }

  Future<Map<String, dynamic>> _callCallable(
    String name,
    Map<String, Object?> payload,
  ) async {
    final callable = FirebaseFunctions.instanceFor(region: 'asia-southeast1')
        .httpsCallable(name);
    final response = await callable.call(payload);
    return (response.data as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
  }

  String _responseMessage(
    Map<String, dynamic> data, {
    required String fallback,
  }) {
    final message = (data['message'] ?? '').toString().trim();
    if (message.isNotEmpty) return message;

    switch ((data['reason'] ?? '').toString().trim()) {
      case 'already-paid':
        return 'This invoice is already marked as paid.';
      case 'session-not-found':
        return 'The Stripe demo session could not be found. Start the payment again.';
      case 'stripe-demo-not-configured':
      case 'stripe-demo-test-key-required':
        return PaymentConfig.stripeConfigError ?? fallback;
      case 'payment-not-settled':
        return 'Stripe is still settling the payment. Try syncing again.';
      default:
        return fallback;
    }
  }

  Future<void> _openCompletionPage(Map<String, dynamic> result) async {
    if (!mounted) return;
    final summary = StripeDemoPaymentSummary.fromCallableResult(
      data: result,
      parentId: widget.parentId,
      parentName: widget.parentName,
      invoiceId: widget.invoiceId,
      invoiceScopeLabel: widget.invoiceScopeLabel,
      fallbackAmountSen: _amountSen,
      fallbackCurrency: _currency,
    );

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => StripeDemoPaymentCompletedPage(summary: summary),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final panelColor = isDark ? const Color(0xFF1D2B23) : Colors.white;
    final muted = isDark ? Colors.white70 : const Color(0xFF5F6B66);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stripe Demo Payment'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: panelColor,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                          color: Color.fromRGBO(0, 0, 0, 0.08),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          widget.invoiceScopeLabel,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: const Color(0xFF2F9E6F),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _money.format(_amountSen / 100.0),
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Invoice ${widget.invoiceId}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: muted,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2F9E6F).withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Text(
                            'Test mode only. Use Stripe card 4242 4242 4242 4242 with any future expiry date and any CVC. No real money is charged.',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              height: 1.45,
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          _headline,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _detail,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: muted,
                            height: 1.45,
                          ),
                        ),
                        if (_isBusy) ...[
                          const SizedBox(height: 20),
                          const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF2F9E6F),
                            ),
                          ),
                        ],
                        if (_errorMessage.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE76F51).withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFE76F51).withValues(alpha: 0.30),
                              ),
                            ),
                            child: Text(
                              _errorMessage,
                              style: const TextStyle(
                                color: Color(0xFF9C331A),
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (!_isBusy)
                    ElevatedButton(
                      onPressed: _startPaymentFlow,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2F9E6F),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Try Again',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Back to Invoice',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}