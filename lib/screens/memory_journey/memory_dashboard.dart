import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'memory_detail_page.dart';
import 'monthly_story_page.dart';

class MemoryJourneyPage extends StatefulWidget {
  const MemoryJourneyPage({super.key});

  @override
  State<MemoryJourneyPage> createState() => _MemoryJourneyPageState();
}

class _MemoryJourneyPageState extends State<MemoryJourneyPage> {
  String selectedCategory = 'All';
  final List<String> categories = [
    'All',
    'Learning',
    'Play',
    'Art',
    'Meal',
    'Nap'
  ];

  static const Color primary = Color(0xFF7ACB9E);
  static const Color backgroundLight = Color(0xFFF6F8F7);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundLight,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                // Header
                Container(
                  decoration: const BoxDecoration(
                    color: primary,
                    borderRadius:
                        BorderRadius.vertical(bottom: Radius.circular(18)),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 4),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Digital Memory Journey',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Your Child\'s Special Moments',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      ClipOval(
                        child: Image.network(
                          'https://i.pravatar.cc/300?img=8',
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Category chips
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, idx) {
                      final cat = categories[idx];
                      final selected = cat == selectedCategory;
                      return ChoiceChip(
                        label: Text(
                          cat,
                          style: TextStyle(
                              color: selected ? Colors.white : Colors.black87),
                        ),
                        selected: selected,
                        onSelected: (_) =>
                            setState(() => selectedCategory = cat),
                        selectedColor: primary,
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999)),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),

                // Firestore dynamic list
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('memory')
                        .orderBy('timestamp', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator(color: primary));
                      }

                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const Center(
                          child: Text(
                            'Tiada memori lagi hari ini 📷',
                            style: TextStyle(color: Colors.grey),
                          ),
                        );
                      }

                      final docs = snapshot.data!.docs;
                      final memories = docs
                          .map((d) => d.data() as Map<String, dynamic>)
                          .toList();

                      final filtered = selectedCategory == 'All'
                          ? memories
                          : memories
                              .where((m) =>
                                  (m['category'] ?? '') == selectedCategory)
                              .toList();

                      return ListView.separated(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final m = filtered[i];
                          final photoUrl = (m['photo_url'] ?? '').toString();
                          final description =
                              (m['description'] ?? '').toString();
                          final teacher = (m['teacher_name'] ?? '').toString();
                          final category =
                              (m['category'] ?? 'General').toString();
                          final ts = m['timestamp'] as Timestamp?;
                          final formattedTime = ts != null
                              ? DateFormat('hh:mm a').format(ts.toDate())
                              : '';

                          final detailPayload = <String, String>{
                            // ikut apa yang MemoryDetailPage guna
                            'image': photoUrl, // kalau MD guna 'image'
                            'photo_url': photoUrl, // kalau MD guna 'photo_url'
                            'text': description,
                            'teacher': teacher,
                            'category': category,
                            'time': formattedTime,
                            // optional extra:
                            'child_name': (m['child_name'] ?? '').toString(),
                            'child_ref': (m['child_ref'] ?? '').toString(),
                          };

                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      MemoryDetailPage(memory: detailPayload),
                                ),
                              );
                            },
                            child: _MemoryCard(
                              imageUrl: photoUrl,
                              description: description,
                              teacher: teacher,
                              category: category,
                              time: formattedTime,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),

                // Footer
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: backgroundLight,
                    border:
                        Border(top: BorderSide(color: Colors.grey.shade300)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {},
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary.withOpacity(0.2),
                            foregroundColor: primary,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Export Memory Book',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const MonthlyStoryPage()),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary.withOpacity(0.2),
                            foregroundColor: primary,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Monthly Story',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
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

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({
    super.key,
    required this.imageUrl,
    required this.description,
    required this.teacher,
    required this.category,
    required this.time,
  });

  final String imageUrl;
  final String description;
  final String teacher;
  final String category;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imageUrl.isNotEmpty)
            Image.network(
              imageUrl,
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 200,
                color: Colors.grey[200],
                child: const Icon(Icons.broken_image,
                    size: 48, color: Colors.grey),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(description,
                    style: const TextStyle(
                        color: Colors.black87, fontSize: 14, height: 1.3)),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(teacher,
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12)),
                        const SizedBox(width: 8),
                        const Icon(Icons.circle, size: 4, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(category,
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                    Row(
                      children: [
                        Text(time,
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12)),
                        const SizedBox(width: 4),
                        const Icon(Icons.access_time,
                            color: Colors.grey, size: 16),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
