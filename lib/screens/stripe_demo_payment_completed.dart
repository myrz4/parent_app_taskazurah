import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class StripeDemoPaymentSummary {
  const StripeDemoPaymentSummary({
    required this.parentId,
    required this.parentName,
    required this.invoiceId,
    required this.invoiceScopeLabel,
    required this.amountSen,
    required this.currency,
    required this.receiptNo,
    required this.paymentId,
    required this.paymentIntentId,
    required this.providerLabel,
    required this.method,
    required this.cardBrand,
    required this.cardLast4,
    required this.paidAt,
  });

  final String parentId;
  final String parentName;
  final String invoiceId;
  final String invoiceScopeLabel;
  final int amountSen;
  final String currency;
  final String receiptNo;
  final String paymentId;
  final String paymentIntentId;
  final String providerLabel;
  final String method;
  final String cardBrand;
  final String cardLast4;
  final DateTime paidAt;

  factory StripeDemoPaymentSummary.fromCallableResult({
    required Map<String, dynamic> data,
    required String parentId,
    required String parentName,
    required String invoiceId,
    required String invoiceScopeLabel,
    required int fallbackAmountSen,
    required String fallbackCurrency,
  }) {
    final rawAmount = data['amountSen'];
    return StripeDemoPaymentSummary(
      parentId: parentId,
      parentName: parentName,
      invoiceId: invoiceId,
      invoiceScopeLabel: invoiceScopeLabel,
      amountSen: rawAmount is int
          ? rawAmount
          : (rawAmount is num ? rawAmount.toInt() : fallbackAmountSen),
      currency: (data['currency'] ?? fallbackCurrency).toString().trim(),
      receiptNo: (data['receiptNo'] ?? '').toString().trim(),
      paymentId: (data['paymentId'] ?? '').toString().trim(),
      paymentIntentId: (data['paymentIntentId'] ?? '').toString().trim(),
      providerLabel: (data['providerLabel'] ?? 'Stripe Test Mode')
          .toString()
          .trim(),
      method: (data['method'] ?? 'Stripe Demo').toString().trim(),
      cardBrand: (data['cardBrand'] ?? '').toString().trim(),
      cardLast4: (data['cardLast4'] ?? '').toString().trim(),
      paidAt: DateTime.now(),
    );
  }

  String get amountLabel {
    final symbol = currency.toUpperCase() == 'MYR' ? 'RM' : '$currency ';
    return NumberFormat.currency(locale: 'ms_MY', symbol: symbol)
        .format(amountSen / 100.0);
  }

  String get cardLabel {
    if (cardBrand.isEmpty && cardLast4.isEmpty) {
      return 'Card details unavailable';
    }
    if (cardBrand.isEmpty) {
      return 'Card ending in $cardLast4';
    }
    if (cardLast4.isEmpty) {
      return cardBrand.toUpperCase();
    }
    return '${cardBrand.toUpperCase()} ending in $cardLast4';
  }
}

class StripeDemoPaymentCompletedPage extends StatelessWidget {
  const StripeDemoPaymentCompletedPage({
    super.key,
    required this.summary,
  });

  final StripeDemoPaymentSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final panelColor = isDark ? const Color(0xFF1D2B23) : Colors.white;
    final muted = isDark ? Colors.white70 : const Color(0xFF5F6B66);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Completed'),
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
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 76,
                          color: Color(0xFF2F9E6F),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Stripe Demo Payment Completed',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No real charge was made. This was processed in Stripe test mode.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: muted,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          summary.amountLabel,
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF2F9E6F),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _detailRow('Invoice ID', summary.invoiceId),
                        _detailRow('Invoice Scope', summary.invoiceScopeLabel),
                        _detailRow('Payment Method', summary.method),
                        _detailRow('Provider', summary.providerLabel),
                        _detailRow(
                          'Paid At',
                          DateFormat('d MMM yyyy, h:mm a').format(summary.paidAt),
                        ),
                        _detailRow(
                          'Card',
                          summary.cardLabel,
                        ),
                        _detailRow(
                          'Receipt No',
                          summary.receiptNo.isEmpty ? '—' : summary.receiptNo,
                        ),
                        _detailRow(
                          'Payment Record ID',
                          summary.paymentId.isEmpty ? '—' : summary.paymentId,
                        ),
                        _detailRow(
                          'PaymentIntent ID',
                          summary.paymentIntentId.isEmpty
                              ? '—'
                              : summary.paymentIntentId,
                          emphasize: false,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pushNamedAndRemoveUntil(
                        '/fee_ledger',
                        (route) => route.isFirst,
                        arguments: {
                          'parentId': summary.parentId,
                          'parentName': summary.parentName,
                        },
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2F9E6F),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Back to Ledger',
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

  static Widget _detailRow(String label, String value, {bool emphasize = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF70817A),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}