import 'package:flutter/material.dart';

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
      title: 'Fees & Payment Dashboard',
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = FeesPaymentApp.primary;

    final cardBg = isDark ? Colors.grey[900] : Colors.white;
    final dividerColor = isDark ? Colors.grey[700] : Colors.grey[200];
    final muted = isDark ? Colors.grey[400] : Colors.grey[600];

    return Scaffold(
      body: SafeArea(
        child: ListView(
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
                        'Fees & Payment',
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
                'This Month’s Fee Summary',
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
                            'Ahmad bin Ali',
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
                              color: primary.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'Paid',
                              style: TextStyle(
                                color: primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),
                      Divider(height: 1, color: dividerColor),

                      const SizedBox(height: 12),

                      // Fee lines
                      _feeRow('Base Fee', 'RM500.00', isDark),
                      const SizedBox(height: 8),
                      _feeRow('Overtime', 'RM50.00', isDark),
                      const SizedBox(height: 8),
                      _feeRow('Discount', '-RM20.00', isDark),
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
                            'RM530.00',
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
                        'Paid on 15 June 2024',
                        style: TextStyle(color: muted, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 18),

            // Heading: Attendance Summary
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Attendance Summary',
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
                        "Your fee is calculated based on your child's attendance. Higher attendance may result in lower overtime charges.",
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
                  color: primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.eco, color: primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Go paperless, save trees! View your receipts online.',
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

            // View Monthly Ledger button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/fee_ledger');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 6,
                    shadowColor: primary.withOpacity(0.3),
                  ),
                  child: const Text(
                    'View Monthly Ledger',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),
          ],
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
