import 'package:flutter/material.dart';

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
      title: 'Invoice Details',
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final cardBg = isDark ? Colors.grey[850] : Colors.white;
    final muted = isDark
        ? InvoiceDetailsApp.subtleDark
        : InvoiceDetailsApp.subtleLight;
    final textColor = isDark
        ? InvoiceDetailsApp.textDark
        : InvoiceDetailsApp.textLight;

    return Scaffold(
      body: SafeArea(
        child: ListView(
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
                      'Invoice Details',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
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
                      errorBuilder: (_, __, ___) =>
                          Container(color: Colors.grey),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Header block: student & invoice meta
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
                    'Zahra Binti Abdullah',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('Class: Pre-K', style: TextStyle(color: muted)),
                  const SizedBox(height: 8),
                  Text(
                    'Invoice ID: #INV-2024-10-001  •  October 2024',
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Fee Breakdown
            const Text(
              'Fee Breakdown',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
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
                    label: 'Base Fee',
                    value: 'RM500.00',
                    valueColor: textColor,
                  ),
                  const SizedBox(height: 8),
                  _lineItem(
                    label: 'Overtime (2 hrs)',
                    value: 'RM50.00',
                    valueColor: textColor,
                  ),
                  const SizedBox(height: 8),
                  _lineItem(
                    label: 'Sibling Discount',
                    value: '-RM25.00',
                    valueColor: textColor,
                  ),
                  const SizedBox(height: 12),
                  Divider(color: isDark ? Colors.grey[700] : Colors.grey[200]),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Amount',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: InvoiceDetailsApp.primary,
                        ),
                      ),
                      Text(
                        'RM525.00',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: InvoiceDetailsApp.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Payment Info
            const Text(
              'Payment Info',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
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
                    value: 'Online Banking',
                    valueColor: textColor,
                  ),
                  const SizedBox(height: 8),
                  _lineItem(
                    label: 'Payment Date',
                    value: 'Oct 5, 2024',
                    valueColor: textColor,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Status'),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: InvoiceDetailsApp.statusPaid.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Paid',
                          style: TextStyle(
                            color: InvoiceDetailsApp.statusPaid,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Proof of Payment',
                      style: TextStyle(color: muted),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 96,
                    width: 96,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        proofImage,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Container(color: Colors.grey[300]),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Actions
            ElevatedButton(
              onPressed: () {
                // implement download receipt
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: InvoiceDetailsApp.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
                shadowColor: InvoiceDetailsApp.primary.withOpacity(0.25),
              ),
              child: const Text(
                'Download Receipt',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () {
                Navigator.maybePop(context);
              },
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: InvoiceDetailsApp.primary),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Back to Ledger',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),

            const SizedBox(height: 18),

            // Eco banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: InvoiceDetailsApp.primary.withOpacity(0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.eco, color: InvoiceDetailsApp.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Go Green! Help us save the environment by using digital receipts.',
                      style: TextStyle(
                        color: InvoiceDetailsApp.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),
          ],
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
        Text(label, style: TextStyle(color: valueColor.withOpacity(0.7))),
        Text(
          value,
          style: TextStyle(color: valueColor, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
