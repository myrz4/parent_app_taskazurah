import 'package:flutter/material.dart';

void main() {
  runApp(const MonthlyStoryApp());
}

class MonthlyStoryApp extends StatelessWidget {
  const MonthlyStoryApp({super.key});

  // Colors taken from the HTML/CSS
  static const Color primaryColor = Color(0xFF7ACB9E);
  static const Color backgroundColor = Color(0xFFF6F8F7);
  static const Color pastelButtonBg = Color(0xFFE6F4EA);
  static const Color pastelButtonText = Color(0xFF3C8B5C);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Monthly Story',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: backgroundColor,
        primaryColor: primaryColor,
        fontFamily: 'Poppins',
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        primaryColor: primaryColor,
        fontFamily: 'Poppins',
      ),
      home: const MonthlyStoryPage(),
    );
  }
}

class MonthlyStoryPage extends StatelessWidget {
  const MonthlyStoryPage({super.key});

  static const List<String> images = [
    'https://lh3.googleusercontent.com/aida-public/AB6AXuDTYiPsQdvM1NhVWbkLU86eFJJ-PA1xYGAtPT-1J0gf3RL4Z4ZDcqarWxHbpktGQamV8KpYJFzL9uMEJUkZehA4Ly4VG8FtOL5SD1m5Swc12Sk_Vnfidqq6fL0VJ8GHIZFL-v4CfFqvdmKJZVdpcyzHsWj0SEnFKUxw7lilihcbPz6TLJIVw6WT9EQ8u8-rcO14U4H1oi5RQTBfX48yGBcqgIupGsKyDvp4L7c0N3iBJW3-qiR25smkG4XT11e4ensuMHX5GcpDdnBD',
    'https://lh3.googleusercontent.com/aida-public/AB6AXuCStiGVcUnWId62EA6e0em6IWi6fwg3DwDkt30zKm7bL36uZXWFHpCR2mtlXjCwA0dMZbGfJevjBVPKdpOZ1fOF8AAu9C_H54jXV9_YODZ03GIlPLMth920uNg4W35HYjmKa9alOwsnFHbN__fHDNdvJXxpi3fZBv32Sosl5uI65SMRcbOQB4_oWF48zlZ9bO8G9mikfb_Ne2HQq0NRlOtR2Zmyn0pqxH3XaiDqTbI6T1s1g0dI5XOnY2sZzKiBHO3FfJ5ksLcxO_D7',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final headerBg = MonthlyStoryApp.primaryColor;
    final containerBg = isDark ? Colors.grey[900] : Colors.white;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                // Header with rounded bottom
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: headerBg,
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(18),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // top row: back + month selector
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.arrow_back_ios,
                              color: Colors.white,
                            ),
                            onPressed: () => Navigator.maybePop(context),
                          ),
                          Row(
                            children: const [
                              Text(
                                'October 2023',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(width: 6),
                              Icon(Icons.expand_more, color: Colors.white),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Monthly Story',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "[Child's Name]'s Journey",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ],
                  ),
                ),

                // Body
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Card: Highlights
                          Container(
                            decoration: BoxDecoration(
                              color: containerBg,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(
                                    isDark ? 0.25 : 0.05,
                                  ),
                                  blurRadius: 6,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'October Highlights',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'This month, [Child\'s Name] had a blast exploring nature, making new friends, and learning through play. From messy art projects to exciting outdoor adventures, it was a month full of growth and laughter.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Photo grid (2 columns)
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: 1,
                                ),
                            itemCount: 6,
                            itemBuilder: (context, index) {
                              final imageUrl = images[index % images.length];
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  color: Colors.grey[200],
                                  child: Image.network(
                                    imageUrl,
                                    fit: BoxFit.cover,
                                    loadingBuilder: (context, child, progress) {
                                      if (progress == null) return child;
                                      return const Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      );
                                    },
                                    errorBuilder: (context, error, stack) =>
                                        Container(color: Colors.grey[300]),
                                  ),
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 12),

                          // AI Highlight block
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: MonthlyStoryApp.primaryColor.withOpacity(
                                0.1,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'AI Highlight: ',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  TextSpan(
                                    text:
                                        "The pure joy on [Child's Name]'s face while painting shows a moment of creative bliss. This activity is great for developing fine motor skills and self-expression.",
                                  ),
                                ],
                              ),
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.black87,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Action buttons
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const MonthlyStoryPage(),
                                      ),
                                    );
                                  },

                                  icon: const Icon(
                                    Icons.download,
                                    color: MonthlyStoryApp.pastelButtonText,
                                  ),
                                  label: const Text(
                                    'Download Story PDF',
                                    style: TextStyle(
                                      color: MonthlyStoryApp.pastelButtonText,
                                    ),
                                  ),

                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        MonthlyStoryApp.pastelButtonBg,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {},
                                  icon: const Icon(
                                    Icons.download,
                                    color: MonthlyStoryApp.pastelButtonText,
                                  ),
                                  label: const Text(
                                    'Download Story PDF',
                                    style: TextStyle(
                                      color: MonthlyStoryApp.pastelButtonText,
                                    ),
                                  ),

                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        MonthlyStoryApp.pastelButtonBg,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
