import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'billing_invoice_presenter.dart';
import 'billing_invoice_status_repair.dart';

void main() {
  runApp(const MonthlyLedgerApp());
}

class MonthlyLedgerApp extends StatelessWidget {
  const MonthlyLedgerApp({super.key});

  // Colors from the HTML tailwind config
  static const Color primary = Color(0xFF7ACB9E);
  static const Color backgroundLight = Color(0xFFF6F8F7);
  static const Color backgroundDark = Color(0xFF122017);
  static const Color textLight = Color(0xFF333333);
  static const Color textDark = Color(0xFFF0F0F0);
  static const Color subtleLight = Color(0xFFA0A0A0);
  static const Color subtleDark = Color(0xFF888888);
  static const Color statusPending = Color(0xFFFFC107);
  static const Color statusUnpaid = Color(0xFFFF6B6B);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Taska Zurah - Billing History',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: backgroundLight,
        primaryColor: primary,
        useMaterial3: true,
        fontFamily: 'Plus Jakarta Sans',
        textTheme: const TextTheme(bodyMedium: TextStyle(color: textLight)),
      ),

      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: backgroundDark,
        primaryColor: primary,
        textTheme: const TextTheme(bodyMedium: TextStyle(color: textDark)),
      ),
      home: const MonthlyLedgerPage(),
    );
  }
}

class MonthlyLedgerPage extends StatelessWidget {
  const MonthlyLedgerPage({super.key});

  final String avatarUrl =
      'https://lh3.googleusercontent.com/aida-public/AB6AXuCESCXwy2oNifL2thtPkpNoIdo1EKjf0_Qb_q0phBEZumJ7t8bHNYGeXNkDbQx1Dro8qBJN2y5WqbBJNfUzWwSNZEd3VPQeF9xN9jhLyqCZPUQtRGfKAR1wVc3p5Ol0Oe3aoWuFNA9P_2ZvQwpCdjHqmZ4uOXrePSc1PpHEaG-UwckU9jk-DXMbZxwzQAodvXNo96xX9jwBPR9NfFAFmwGxFuGcSvn0nLubkFEFXFQIkpvAWVPNZDXMHtkxVRKCBsoPzMMdwT4WIF2y';

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final parentId = (args?['parentId'] ?? '').toString().trim();
    final parentName = (args?['parentName'] ?? 'Parent').toString().trim();

    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    final cardBg = isDark ? Colors.grey[850] : Colors.white;
    final textPrimary = isDark
        ? MonthlyLedgerApp.textDark
        : MonthlyLedgerApp.textLight;
    final subtle = isDark
        ? MonthlyLedgerApp.subtleDark
        : MonthlyLedgerApp.subtleLight;

    if (parentId.isEmpty) {
      return const Scaffold(
        body: SafeArea(
          child: Center(child: Text('Missing parentId argument')),
        ),
      );
    }

    final money = NumberFormat.currency(locale: 'ms_MY', symbol: 'RM');
    String fmtSen(Object? raw) {
      final n = raw is int ? raw : (raw is num ? raw.toInt() : 0);
      return money.format(n / 100.0);
    }

    DateTime? tsToDate(Object? raw) {
      if (raw is Timestamp) return raw.toDate();
      return null;
    }

    return Scaffold(
      // top bar implemented manually to mimic sticky header
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Container(
              decoration: BoxDecoration(
                color: isDark ? MonthlyLedgerApp.backgroundDark : Colors.white,
                boxShadow: const [
                  BoxShadow(
                    color: Color.fromRGBO(0, 0, 0, 0.06),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.maybePop(context),
                    icon: Icon(Icons.arrow_back, color: textPrimary),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Billing History',
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  // avatar
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

            // content
            Expanded(
              child: Stack(
                children: [
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('parents')
                        .doc(parentId)
                        .collection('invoices')
                        .orderBy('createdAt', descending: true)
                        .snapshots(),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(color: MonthlyLedgerApp.primary),
                        );
                      }

                      final docs = snap.data?.docs ?? const [];
                      int totalPaidSen = 0;
                      int outstandingSen = 0;
                      DateTime? lastPaidAt;

                      for (final d in docs) {
                        final m = d.data();
                        final status = (m['status'] ?? '').toString().toLowerCase();
                        final total = (m['totalSen'] is int)
                            ? (m['totalSen'] as int)
                            : (m['totalSen'] is num ? (m['totalSen'] as num).toInt() : 0);

                        if (status == 'paid') {
                          totalPaidSen += total;
                          final paidAt = tsToDate(m['paidAt']);
                          if (paidAt != null &&
                              (lastPaidAt == null ||
                                  paidAt.isAfter(lastPaidAt))) {
                            lastPaidAt = paidAt;
                          }
                        } else if (status != 'void') {
                          outstandingSen += total;
                        }
                      }

                      final header = Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(14),
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
                              parentName,
                              style: TextStyle(
                                color: textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Outstanding: ${fmtSen(outstandingSen)}',
                                      style: TextStyle(color: subtle),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      outstandingSen > 0 ? 'Payment required' : 'Up to date',
                                      style: TextStyle(
                                        color: outstandingSen > 0
                                            ? MonthlyLedgerApp.statusUnpaid
                                            : MonthlyLedgerApp.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 8),
                              ],
                            ),
                          ],
                        ),
                      );

                      final entries = docs.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.only(top: 24),
                              child: Center(
                                child: Text('No billing records yet', style: TextStyle(color: subtle)),
                              ),
                            )
                          : Column(
                              children: [
                                for (final d in docs) ...[
                                  Builder(
                                    builder: (context) {
                                      final m = d.data();
                                      BillingInvoiceStatusRepair.maybeRepair(
                                        parentId: parentId,
                                        invoiceId: d.id,
                                        invoice: m,
                                      );
                                      final invoicePresentation = BillingInvoicePresentation.fromInvoice(
                                        m,
                                        parentNameFallback: parentName,
                                      );
                                      final status = (m['status'] ?? 'unpaid').toString().toLowerCase();
                                      final totalSen = m['totalSen'] ?? 0;
                                      final period = (m['period'] ?? '').toString();

                                      Color bg;
                                      IconData icon;
                                      String paymentLine;

                                      if (status == 'paid') {
                                        bg = MonthlyLedgerApp.primary;
                                        icon = Icons.check_circle;
                                        final paidAt = tsToDate(m['paidAt']);
                                        paymentLine = paidAt == null
                                            ? 'Payment completed'
                                            : 'Paid on: ${DateFormat('d MMM yyyy').format(paidAt)}';
                                      } else if (status == 'pending') {
                                        bg = MonthlyLedgerApp.statusPending;
                                        icon = Icons.hourglass_empty;
                                        paymentLine = 'Payment pending';
                                      } else {
                                        bg = MonthlyLedgerApp.statusUnpaid;
                                        icon = Icons.error_outline;
                                        final due = tsToDate(m['dueDate']);
                                        paymentLine = due == null
                                            ? 'Payment outstanding'
                                            : 'Outstanding (due ${DateFormat('d MMM').format(due)})';
                                      }

                                      final title = '${period.isEmpty ? 'Invoice' : period} • ${fmtSen(totalSen)}';
                                      final subtitleBuffer = StringBuffer()
                                        ..writeln(invoicePresentation.supportingLabel)
                                        ..write(paymentLine);
                                      if (invoicePresentation.policySummary.isNotEmpty) {
                                        subtitleBuffer
                                          ..writeln()
                                          ..write(invoicePresentation.managementReviewRecommended
                                              ? 'Review: ${invoicePresentation.policySummary}'
                                              : 'Note: ${invoicePresentation.policySummary}');
                                      }
                                      final subtitle = subtitleBuffer.toString();

                                      return _ledgerEntry(
                                        context: context,
                                        iconBackground: bg,
                                        icon: icon,
                                        title: title,
                                        subtitle: subtitle,
                                        actionLabel: 'Open',
                                        onTap: () {
                                          Navigator.pushNamed(
                                            context,
                                            '/fee_invoice_details',
                                            arguments: {
                                              'parentId': parentId,
                                              'parentName': parentName,
                                              'invoiceId': d.id,
                                            },
                                          );
                                        },
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                ],
                              ],
                            );

                      return Stack(
                        children: [
                          ListView(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
                            children: [
                              header,
                              const SizedBox(height: 16),
                              entries,
                            ],
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              color: isDark ? Colors.grey[850] : Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    constraints: const BoxConstraints(maxWidth: 600),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            children: [
                                              Text('Total Paid', style: TextStyle(color: subtle)),
                                              const SizedBox(height: 6),
                                              Text(
                                                fmtSen(totalPaidSen),
                                                style: TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            children: [
                                              Text('Outstanding', style: TextStyle(color: subtle)),
                                              const SizedBox(height: 6),
                                              Text(
                                                fmtSen(outstandingSen),
                                                style: TextStyle(
                                                  color: outstandingSen > 0
                                                      ? MonthlyLedgerApp.statusUnpaid
                                                      : MonthlyLedgerApp.primary,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            children: [
                                              Text('Last Payment', style: TextStyle(color: subtle)),
                                              const SizedBox(height: 6),
                                              Text(
                                                lastPaidAt == null
                                                    ? '—'
                                                    : DateFormat('d MMM yyyy').format(lastPaidAt),
                                                style: TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    constraints: const BoxConstraints(maxWidth: 600),
                                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: MonthlyLedgerApp.primary.withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.eco, color: MonthlyLedgerApp.primary),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Go paperless. All billing records and receipts are saved digitally.',
                                            style: TextStyle(
                                              color: MonthlyLedgerApp.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ledgerEntry({
    required BuildContext context,
    required Color iconBackground,
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? Colors.grey[850] : Colors.white;
    final textPrimary = isDark
        ? MonthlyLedgerApp.textDark
        : MonthlyLedgerApp.textLight;
    final subtle = isDark
        ? MonthlyLedgerApp.subtleDark
        : MonthlyLedgerApp.subtleLight;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: subtle, fontSize: 13),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onTap,
            child: Text(
              actionLabel,
              style: TextStyle(
                color: MonthlyLedgerApp.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
