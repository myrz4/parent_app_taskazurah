import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'billing_invoice_presenter.dart';
import 'billing_invoice_status_repair.dart';
import 'demo_checkout.dart';
import 'redirect_checkout.dart';

void main() {
  runApp(const InvoiceDetailsApp());
}

class InvoiceDetailsApp extends StatelessWidget {
  const InvoiceDetailsApp({super.key});

  static const Color primary = Color(0xFF7ACB9E);
  static const Color backgroundLight = Color(0xFFF6F8F7);
  static const Color backgroundDark = Color(0xFF122017);
  static const Color textLight = Color(0xFF333333);
  static const Color textDark = Color(0xFFF0F0F0);
  static const Color subtleLight = Color(0xFFA0A0A0);
  static const Color subtleDark = Color(0xFF888888);
  static const Color statusPaid = Color(0xFF7ACB9E);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Billing Details',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: backgroundLight,
        primaryColor: primary,
        brightness: Brightness.light,
        textTheme: const TextTheme(bodyMedium: TextStyle(color: textLight)),

        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        scaffoldBackgroundColor: backgroundDark,
        primaryColor: primary,
        brightness: Brightness.dark,
        textTheme: const TextTheme(bodyMedium: TextStyle(color: textDark)),

        useMaterial3: true,
      ),
      home: const InvoiceDetailsPage(),
    );
  }
}



class InvoiceDetailsPage extends StatelessWidget {
  const InvoiceDetailsPage({super.key});

  final String avatarUrl =
      'https://lh3.googleusercontent.com/aida-public/AB6AXuCESCXwy2oNifL2thtPkpNoIdo1EKjf0_Qb_q0phBEZumJ7t8bHNYGeXNkDbQx1Dro8qBJN2y5WqbBJNfUzWwSNZEd3VPQeF9xN9jhLyqCZPUQtRGfKAR1wVc3p5Ol0Oe3aoWuFNA9P_2ZvQwpCdjHqmZ4uOXrePSc1PpHEaG-UwckU9jk-DXMbZxwzQAodvXNo96xX9jwBPR9NfFAFmwGxFuGcSvn0nLubkFEFXFQIkpvAWVPNZDXMHtkxVRKCBsoPzMMdwT4WIF2y';

  final String proofImage =
      'https://lh3.googleusercontent.com/aida-public/AB6AXuCESCXwy2oNifL2thtPkpNoIdo1EKjf0_Qb_q0phBEZumJ7t8bHNYGeXNkDbQx1Dro8qBJN2y5WqbBJNfUzWwSNZEd3VPQeF9xN9jhLyqCZPUQtRGfKAR1wVc3p5Ol0Oe3aoWuFNA9P_2ZvQwpCdjHqmZ4uOXrePSc1PpHEaG-UwckU9jk-DXMbZxwzQAodvXNo96xX9jwBPR9NfFAFmwGxFuGcSvn0nLubkFEFXFQIkpvAWVPNZDXMHtkxVRKCBsoPzMMdwT4WIF2y';

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final parentId = (args?['parentId'] ?? '').toString().trim();
    final parentNameArg = (args?['parentName'] ?? '').toString().trim();
    final invoiceId = (args?['invoiceId'] ?? '').toString().trim();

    if (parentId.isEmpty || invoiceId.isEmpty) {
      return const Scaffold(
        body: SafeArea(
          child: Center(child: Text('Missing invoice arguments')),
        ),
      );
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final cardBg = isDark ? Colors.grey[850] : Colors.white;
    final muted = isDark
        ? InvoiceDetailsApp.subtleDark
        : InvoiceDetailsApp.subtleLight;
    final textColor = isDark
        ? InvoiceDetailsApp.textDark
        : InvoiceDetailsApp.textLight;

    final money = NumberFormat.currency(locale: 'ms_MY', symbol: 'RM');
    String fmtSen(Object? raw) {
      final n = raw is int ? raw : (raw is num ? raw.toInt() : 0);
      return money.format(n / 100.0);
    }

    DateTime? tsToDate(Object? raw) {
      if (raw is Timestamp) return raw.toDate();
      return null;
    }

    List<String> policyNotesFromInvoice(Map<String, dynamic> invoice) {
      final billingMeta = invoice['billingMeta'];
      if (billingMeta is Map) {
        final raw = billingMeta['policyNotes'];
        if (raw is List) {
          return raw
              .map((item) => item?.toString().trim() ?? '')
              .where((item) => item.isNotEmpty)
              .toList(growable: false);
        }
      }
      return const <String>[];
    }

    bool managementReviewRecommended(Map<String, dynamic> invoice) {
      final billingMeta = invoice['billingMeta'];
      if (billingMeta is Map) {
        final raw = billingMeta['managementReviewRecommended'];
        return raw == true;
      }
      return false;
    }

    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('parents')
              .doc(parentId)
              .collection('invoices')
              .doc(invoiceId)
              .snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: InvoiceDetailsApp.primary),
              );
            }
            if (!snap.hasData || !snap.data!.exists) {
              return const Center(child: Text('Invoice not found'));
            }

            final inv = snap.data!.data() ?? <String, dynamic>{};
            BillingInvoiceStatusRepair.maybeRepair(
              parentId: parentId,
              invoiceId: invoiceId,
              invoice: inv,
            );
            final invoicePresentation = BillingInvoicePresentation.fromInvoice(
              inv,
              parentNameFallback: parentNameArg,
            );
            final displayName = invoicePresentation.displayName;
            final period = (inv['period'] ?? '').toString().trim();
            final status = (inv['status'] ?? 'unpaid').toString().toLowerCase();
            final isPaid = status == 'paid';
            final items = (inv['items'] is List) ? (inv['items'] as List) : const [];
            final totalSen = inv['totalSen'] ?? 0;
            final paidAt = tsToDate(inv['paidAt']);
            final paidMethod = (inv['paidMethod'] ?? '').toString();
            final paidBank = (inv['paidBank'] ?? '').toString();
            final receiptNo = (inv['paidReceiptNo'] ?? '').toString();
            final policyNotes = policyNotesFromInvoice(inv);
            final needsManagementReview = managementReviewRecommended(inv);

            Future<void> startPayFlow() async {
              final create = FirebaseFunctions.instanceFor(region: 'asia-southeast1')
                  .httpsCallable('billingCreateCheckoutSession');
              final res = await create.call({
                'parentId': parentId,
                'invoiceId': invoiceId,
              });

              final data = (res.data as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
              if (data['ok'] != true) {
                throw Exception(data['reason'] ?? 'create-session-failed');
              }

              if (!context.mounted) return;

              final sessionId = (data['sessionId'] ?? '').toString();
              final amountSen = (data['amountSen'] is int)
                  ? data['amountSen'] as int
                  : (data['amountSen'] is num ? (data['amountSen'] as num).toInt() : 0);
              final currency = (data['currency'] ?? 'MYR').toString();
              final mode = (data['mode'] ?? 'dummy').toString().toLowerCase();
              final provider = (data['provider'] ?? 'dummy').toString().toLowerCase();
              final checkoutUrl = (data['checkoutUrl'] ?? '').toString().trim();

              if (mode == 'redirect') {
                if (checkoutUrl.isEmpty) {
                  throw Exception(data['reason'] ?? 'payment-provider-create-failed');
                }

                final ok = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => RedirectCheckoutPage(
                      parentId: parentId,
                      invoiceId: invoiceId,
                      sessionId: sessionId,
                      amountSen: amountSen,
                      currency: currency,
                      provider: provider,
                      checkoutUrl: checkoutUrl,
                    ),
                  ),
                );

                if (ok == true && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Payment successful.')),
                  );
                }
                return;
              }

              if (mode != 'dummy') {
                throw Exception(data['reason'] ?? 'payment-provider-not-implemented');
              }

              final ok = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => DemoCheckoutPage(
                    parentId: parentId,
                    invoiceId: invoiceId,
                    sessionId: sessionId,
                    amountSen: amountSen,
                    currency: currency,
                  ),
                ),
              );

              if (ok == true && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Payment successful.')),
                );
              }
            }

            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              children: [
                // Top app bar
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.maybePop(context),
                      icon: Icon(Icons.arrow_back, color: textColor),
                    ),
                    const Expanded(
                      child: Center(
                        child: Text(
                          'Billing Details',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: ClipOval(
                        child: Image.network(
                          avatarUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(color: Colors.grey),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Header block
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Color.fromRGBO(0, 0, 0, 0.06),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: textColor),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        invoicePresentation.supportingLabel,
                        style: TextStyle(color: muted, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Invoice ID: $invoiceId${period.isEmpty ? '' : '  •  $period'}',
                        style: TextStyle(color: muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                const Text('Invoice Breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Color.fromRGBO(0, 0, 0, 0.06),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      if (items.isEmpty) ...[
                        _lineItem(label: 'No charges recorded', value: '—', valueColor: textColor),
                      ] else ...[
                        for (final it in items) ...[
                          _lineItem(
                            label: (it is Map ? (it['description'] ?? it['code'] ?? 'Item') : 'Item').toString(),
                            value: fmtSen(it is Map ? it['amountSen'] : 0),
                            valueColor: textColor,
                          ),
                          const SizedBox(height: 8),
                        ]
                      ],
                      const SizedBox(height: 4),
                      Divider(color: isDark ? Colors.grey[700] : Colors.grey[200]),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total Amount',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: InvoiceDetailsApp.primary),
                          ),
                          Text(
                            fmtSen(totalSen),
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: InvoiceDetailsApp.primary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                if (needsManagementReview) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.28)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Late-night overtime exceeded the policy threshold. This invoice should be reviewed by management.',
                            style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                if (policyNotes.isNotEmpty) ...[
                  const Text('Policy Notes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Color.fromRGBO(0, 0, 0, 0.06),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final note in policyNotes) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('• ', style: TextStyle(color: textColor, fontWeight: FontWeight.w700)),
                              Expanded(
                                child: Text(
                                  note,
                                  style: TextStyle(color: textColor, height: 1.35),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                const Text('Payment Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Color.fromRGBO(0, 0, 0, 0.06),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _lineItem(
                        label: 'Payment Method',
                        value: isPaid ? (paidMethod.isEmpty ? 'Online Banking' : paidMethod) : '—',
                        valueColor: textColor,
                      ),
                      const SizedBox(height: 8),
                      _lineItem(
                        label: 'Bank',
                        value: isPaid ? (paidBank.isEmpty ? '—' : paidBank) : '—',
                        valueColor: textColor,
                      ),
                      const SizedBox(height: 8),
                      _lineItem(
                        label: 'Payment Date',
                        value: isPaid && paidAt != null ? DateFormat('d MMM yyyy').format(paidAt) : '—',
                        valueColor: textColor,
                      ),
                      const SizedBox(height: 8),
                      _lineItem(
                        label: 'Receipt No',
                        value: isPaid ? (receiptNo.isEmpty ? '—' : receiptNo) : '—',
                        valueColor: textColor,
                      ),
                      const SizedBox(height: 8),
                      _lineItem(
                        label: 'Invoice Scope',
                        value: invoicePresentation.scopeLabel,
                        valueColor: textColor,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Status', style: TextStyle(color: muted)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: (isPaid ? InvoiceDetailsApp.statusPaid : Colors.orange).withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              isPaid ? 'Paid' : 'Unpaid',
                              style: TextStyle(
                                color: isPaid ? InvoiceDetailsApp.statusPaid : Colors.orange,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                if (!isPaid)
                  ElevatedButton(
                    onPressed: () async {
                      try {
                        await startPayFlow();
                      } catch (_) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Unable to start payment.')),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: InvoiceDetailsApp.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 4,
                      shadowColor: InvoiceDetailsApp.primary.withValues(alpha: 0.25),
                    ),
                    child: const Text('Pay This Invoice', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                  )
                else
                  ElevatedButton(
                    onPressed: null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: InvoiceDetailsApp.primary.withValues(alpha: 0.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('Payment Completed', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                  ),

                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () => Navigator.maybePop(context),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: InvoiceDetailsApp.primary),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Back to Ledger', style: TextStyle(fontWeight: FontWeight.w700)),
                ),

                const SizedBox(height: 18),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: InvoiceDetailsApp.primary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.eco, color: InvoiceDetailsApp.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Go Green! Help us save the environment by using digital receipts.',
                          style: TextStyle(color: InvoiceDetailsApp.primary, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),
              ],
            );
          },
        ),
      ),
    );
  }

  static Widget _lineItem({
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: valueColor.withValues(alpha: 0.7))),
        Text(
          value,
          style: TextStyle(color: valueColor, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
