import 'package:flutter/material.dart';
import 'fee_invoice_details.dart';

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
      title: 'Taska Zurah - Monthly Ledger',
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
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    final cardBg = isDark ? Colors.grey[850] : Colors.white;
    final dividerColor = isDark ? Colors.grey[800] : Colors.grey[200];
    final textPrimary = isDark
        ? MonthlyLedgerApp.textDark
        : MonthlyLedgerApp.textLight;
    final subtle = isDark
        ? MonthlyLedgerApp.subtleDark
        : MonthlyLedgerApp.subtleLight;

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
                        'Monthly Ledger',
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
                  ListView(
                    padding: const EdgeInsets.fromLTRB(
                      16,
                      12,
                      16,
                      140,
                    ), // leave space for footer
                    children: [
                      // Header Card with name & balance
                      Container(
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
                              'Zahra Binti Abdullah',
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
                                      'Balance: RM550.00',
                                      style: TextStyle(color: subtle),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Overdue',
                                      style: TextStyle(
                                        color: MonthlyLedgerApp.statusUnpaid,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                // placeholder right side if needed
                                const SizedBox(width: 8),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Entries list
                      Column(
                        children: [
                          _ledgerEntry(
                            context: context,
                            iconBackground: MonthlyLedgerApp.primary,
                            icon: Icons.check_circle,
                            title: 'October 2024 Fee: RM550.00',
                            subtitle: 'Paid on: Oct 5, 2024',
                            actionLabel: 'View Details',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const InvoiceDetailsPage(),
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 12),
                          _ledgerEntry(
                            context: context,
                            iconBackground: MonthlyLedgerApp.statusPending,
                            icon: Icons.hourglass_empty,
                            title: 'September 2024 Fee: RM550.00',
                            subtitle: 'Status: Pending',
                            actionLabel: 'View Details',
                            onTap: () {},
                          ),
                          const SizedBox(height: 12),
                          _ledgerEntry(
                            context: context,
                            iconBackground: MonthlyLedgerApp.statusUnpaid,
                            icon: Icons.error_outline,
                            title: 'August 2024 Fee: RM550.00',
                            subtitle: 'Status: Unpaid',
                            actionLabel: 'View Details',
                            onTap: () {},
                          ),
                        ],
                      ),
                    ],
                  ),

                  // Footer (floating at bottom)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      color: isDark ? Colors.grey[850] : Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // summary row
                          Container(
                            constraints: const BoxConstraints(maxWidth: 600),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Total Paid',
                                        style: TextStyle(color: subtle),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'RM1100.00',
                                        style: TextStyle(
                                          color: textPrimary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Outstanding',
                                        style: TextStyle(color: subtle),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'RM550.00',
                                        style: TextStyle(
                                          color: MonthlyLedgerApp.statusUnpaid,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Last Payment',
                                        style: TextStyle(color: subtle),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Oct 5, 2024',
                                        style: TextStyle(
                                          color: textPrimary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Go green banner
                          Container(
                            constraints: const BoxConstraints(maxWidth: 600),
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 12,
                            ),
                            decoration: BoxDecoration(
                              color: MonthlyLedgerApp.primary.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.eco,
                                  color: MonthlyLedgerApp.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Go Green! All your receipts are saved digitally.',
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
                Text(subtitle, style: TextStyle(color: subtle, fontSize: 13)),
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
