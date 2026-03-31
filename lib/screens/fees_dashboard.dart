import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'billing_invoice_presenter.dart';
import 'billing_invoice_status_repair.dart';

void main() {
  runApp(const FeesPaymentApp());
}

class FeesPaymentApp extends StatelessWidget {
  const FeesPaymentApp({super.key});

  // Colors taken from the HTML tailwind config
  static const Color primary = Color(0xFF7ACB9E);
  static const Color backgroundLight = Color(0xFFF6F8F7);
  static const Color backgroundDark = Color(0xFF122017);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Billing & Payments',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: backgroundLight,
        primaryColor: primary,
        fontFamily: 'Plus Jakarta Sans',
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: backgroundDark,
        primaryColor: primary,
        fontFamily: 'Plus Jakarta Sans',
      ),
      home: const FeesPaymentPage(),
    );
  }
}

class FeesPaymentPage extends StatelessWidget {
  const FeesPaymentPage({super.key});

  final String avatarUrl =
      'https://lh3.googleusercontent.com/aida-public/AB6AXuDVc0xV6ymf5YntytIkU8k4NsWhY_Q667s_0AwlCkDW0yd6wCkcnt1oR6Z_KOc6Allxs3VlmDg5grwefKneQznN-euV7Vyr0F3hR7zJWJLyzNmRhHSkfBCti7HlXvKMbXXvAh9VVYYYgDBNHlu6PpWMzxje4N2KmCbRBLbZoyf206Db_UwSKyJjlKDuuP_yUwauUgTCwMlhpiYy2_PKTFSlHDF5qMoKFxVH14puY34621mqIJMlnjfkbBrmD3Vl6_ypVTODox5kEo-L';

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final parentId = (args?['parentId'] ?? '').toString().trim();
    final parentName = (args?['parentName'] ?? 'Parent').toString().trim();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = FeesPaymentApp.primary;

    final cardBg = isDark ? Colors.grey[900] : Colors.white;
    final dividerColor = isDark ? Colors.grey[700] : Colors.grey[200];
    final muted = isDark ? Colors.grey[400] : Colors.grey[600];

    if (parentId.isEmpty) {
      return const Scaffold(
        body: SafeArea(
          child: Center(child: Text('Missing parentId argument')),
        ),
      );
    }

    final now = DateTime.now();
    final period = DateFormat('yyyy-MM').format(now);
    final money = NumberFormat.currency(locale: 'ms_MY', symbol: 'RM');

    String fmtSen(Object? raw) {
      final n = raw is int ? raw : (raw is num ? raw.toInt() : 0);
      return money.format(n / 100.0);
    }

    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('parents')
              .doc(parentId)
              .collection('invoices')
              .where('period', isEqualTo: period)
              .limit(1)
              .snapshots(),
          builder: (context, snap) {
            final latest = (snap.data?.docs.isNotEmpty ?? false) ? snap.data!.docs.first : null;
            final inv = latest?.data() ?? <String, dynamic>{};
            if (latest != null) {
              BillingInvoiceStatusRepair.maybeRepair(
                parentId: parentId,
                invoiceId: latest.id,
                invoice: inv,
              );
            }
            final invoicePresentation = BillingInvoicePresentation.fromInvoice(
              inv,
              parentNameFallback: parentName,
            );
            final status = (inv['status'] ?? 'unpaid').toString().toLowerCase();
            final isPaid = status == 'paid';
            final totalSen = inv['totalSen'] ?? 0;
            final items = (inv['items'] is List) ? (inv['items'] as List) : const [];

            Future<void> createDemoInvoice() async {
              final fn = FirebaseFunctions.instanceFor(region: 'asia-southeast1')
                  .httpsCallable('billingCreateDemoInvoiceForCurrentMonth');
              await fn.call({
                'parentId': parentId,
              });
            }

            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.maybePop(context),
                    icon: Icon(
                      Icons.arrow_back,
                      color: isDark ? Colors.white : const Color(0xFF111714),
                    ),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Billing & Payments',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  // Avatar button
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: ClipOval(
                      child: Image.network(
                        avatarUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Container(color: Colors.grey),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Heading: This Month's Fee Summary
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Current Billing Summary',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),
            ),

            const SizedBox(height: 12),

            // Fee summary card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color.fromRGBO(0, 0, 0, 0.08),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Header row: name + badge
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            parentName,
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF111714),
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: primary.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              isPaid ? 'Paid' : 'Unpaid',
                              style: TextStyle(
                                color: primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),
                      if (latest != null) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            invoicePresentation.supportingLabel,
                            style: TextStyle(color: muted, fontSize: 13),
                          ),
                        ),
                        if (invoicePresentation.policySummary.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: invoicePresentation.managementReviewRecommended
                                  ? Colors.orange.withValues(alpha: 0.14)
                                  : primary.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: invoicePresentation.managementReviewRecommended
                                    ? Colors.orange.withValues(alpha: 0.32)
                                    : primary.withValues(alpha: 0.18),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  invoicePresentation.managementReviewRecommended
                                      ? Icons.warning_amber_rounded
                                      : Icons.info_outline,
                                  size: 18,
                                  color: invoicePresentation.managementReviewRecommended
                                      ? Colors.orange
                                      : primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    invoicePresentation.managementReviewRecommended
                                        ? 'Management review recommended. Open the invoice for details.'
                                        : invoicePresentation.policySummary,
                                    style: TextStyle(
                                      color: isDark ? Colors.white : const Color(0xFF111714),
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                      ],
                      Divider(height: 1, color: dividerColor),

                      const SizedBox(height: 12),

                      // Fee lines
                      if (latest == null) ...[
                        _feeRow('No billing record yet', '—', isDark),
                      ] else ...[
                        for (final it in items.take(4)) ...[
                          _feeRow(
                            (it is Map ? (it['description'] ?? it['code'] ?? 'Item') : 'Item').toString(),
                            fmtSen(it is Map ? it['amountSen'] : 0),
                            isDark,
                          ),
                          const SizedBox(height: 8),
                        ]
                      ],
                      const SizedBox(height: 12),
                      Divider(height: 1, color: dividerColor),
                      const SizedBox(height: 12),

                      // Total
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF111714),
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            latest == null ? '—' : fmtSen(totalSen),
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF111714),
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),
                      Divider(height: 1, color: dividerColor),

                      const SizedBox(height: 12),

                      Text(
                        latest == null
                            ? 'Period: $period'
                            : (isPaid
                                ? 'Payment completed'
                                : 'Due: ${(inv['dueDate'] is Timestamp) ? DateFormat('d MMM yyyy').format((inv['dueDate'] as Timestamp).toDate()) : '7th'}'),
                        style: TextStyle(color: muted, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      if (latest != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          invoicePresentation.scopeLabel,
                          style: TextStyle(color: primary, fontSize: 13, fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            if (latest == null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () async {
                      try {
                        await createDemoInvoice();
                      } catch (_) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Unable to create demo billing record')),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 6,
                    ),
                    child: const Text(
                      'Generate Demo Billing Record',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white),
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 18),

            // Heading: Attendance Snapshot
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Attendance Snapshot',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),
            ),

            const SizedBox(height: 12),

            // Attendance summary card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color.fromRGBO(0, 0, 0, 0.08),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        'Attendance can affect overtime and other monthly charges. Review the latest attendance trend together with your billing summary.',
                        style: TextStyle(color: muted),
                      ),
                      const SizedBox(height: 12),

                      // Monthly attendance rate
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Monthly Attendance Rate',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF111714),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '92%',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF111714),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Progress bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: LinearProgressIndicator(
                          value: 0.92,
                          minHeight: 10,
                          backgroundColor: isDark
                              ? Colors.grey[700]
                              : Colors.grey[300],
                          color: primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Paperless callout
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 12,
                ),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.eco, color: primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Go paperless. Your invoices and receipts are stored digitally for easy review anytime.',
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // View Billing History button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      '/fee_ledger',
                      arguments: {
                        'parentId': parentId,
                        'parentName': parentName,
                      },
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 6,
                    shadowColor: primary.withValues(alpha: 0.3),
                  ),
                  child: const Text(
                    'View Billing History',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _feeRow(String label, String value, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: isDark ? Colors.grey[300] : Colors.grey[600]),
        ),
        Text(
          value,
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF111714),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
