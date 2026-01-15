import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:parent_app_taskazurah/screens/chat_screen.dart';

class Teacher {
  final String id;
  final String name;
  final String imageUrl;
  final String className;
  final String experience;

  const Teacher({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.className,
    required this.experience,
  });
}

class TeacherProfilePage extends StatelessWidget {
  final Teacher teacher;
  const TeacherProfilePage({super.key, required this.teacher});

  static const Color primary = Color(0xFF7ACB9E);
  static const Color backgroundLight = Color(0xFFFFFFFF);
  static const Color backgroundDark = Color(0xFF112117);
  static const Color textLight = Color(0xFF333333);
  static const Color textDark = Color(0xFFF0F0F0);
  static const Color textSecondaryLight = Color(0xFF888888);
  static const Color textSecondaryDark = Color(0xFFB0B0B0);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? textDark : textLight;
    final textSecondary = isDark ? textSecondaryDark : textSecondaryLight;
    final cardBg = isDark ? Colors.black.withOpacity(0.25) : Colors.white;
    final dividerColor = isDark ? Colors.grey.shade800 : Colors.grey.shade200;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(teacher.name, textAlign: TextAlign.center),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Profile Header
              Column(
                children: [
                  Container(
                    width: 128,
                    height: 128,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      image: DecorationImage(
                        image: NetworkImage(teacher.imageUrl),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    teacher.name,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Info Card
              Card(
                color: cardBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 12,
                  ),
                  child: Column(
                    children: [
                      _infoRow(
                        Icons.school,
                        'Class handled',
                        teacher.className,
                        textSecondary,
                        textColor,
                        dividerColor,
                      ),
                      _infoRow(
                        Icons.group,
                        'Total students',
                        '12 Students',
                        textSecondary,
                        textColor,
                        dividerColor,
                      ),
                      _infoRow(
                        Icons.star,
                        'Experience',
                        teacher.experience,
                        textSecondary,
                        textColor,
                        dividerColor,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // About Card
              Card(
                color: cardBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'About Me',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Cikgu ${teacher.name.split(" ").last} has over ${teacher.experience} of experience teaching early childhood learners. '
                        'She is known for her caring approach and creative class activities.',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Badges
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: const [
                  _Badge(emoji: '🌸', text: 'Early Childhood Educator'),
                  _Badge(emoji: '💬', text: 'Communicative'),
                  _Badge(emoji: '🎨', text: 'Creative Learning'),
                ],
              ),

              const SizedBox(height: 96),
            ],
          ),
        ),
      ),

      // Bottom buttons
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? backgroundDark : backgroundLight,
            border: Border(
              top: BorderSide(
                color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
              ),
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🟢 Message Teacher button — linked to real ChatScreen
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.message),
                  label: const Text(
                    'Message Teacher',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    try {
                      // Sementara hardcode parent, nanti link dengan login
                      final teacherUsername = teacher.name.toLowerCase().trim();
                      final parentUsername =
                          "ezham"; // ← Gantikan ikut parent login dynamic

                      final chatId =
                          'teacher_${teacherUsername}_parent_$parentUsername';

                      final chatRef = FirebaseFirestore.instance
                          .collection('chats')
                          .doc(chatId);
                      final chatSnap = await chatRef.get();

                      if (!chatSnap.exists) {
                        await chatRef.set({
                          'teacherUsername': teacherUsername,
                          'parentUsername': parentUsername,
                          'teacherRef': '/teachers/$teacherUsername',
                          'parentRef': '/parents/$parentUsername',
                          'lastMessage': '',
                          'lastTimestamp': FieldValue.serverTimestamp(),
                        });
                      }

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            chatId: chatId,
                            teacherUsername: teacherUsername,
                            parentUsername: parentUsername,
                          ),
                        ),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Ralat buka chat: $e')),
                      );
                    }
                  },
                ),
              ),

              const SizedBox(height: 8),

              // 🔹 View Class Activities (placeholder)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.collections_bookmark),
                  label: const Text(
                    'View Class Activities',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primary,
                    side: const BorderSide(color: primary, width: 2),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('View Class Activities clicked'),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(
    IconData icon,
    String label,
    String value,
    Color labelColor,
    Color valueColor,
    Color dividerColor,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: labelColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 14, color: labelColor),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: valueColor,
                ),
                textAlign: TextAlign.right,
              ),
            ],
          ),
        ),
        Divider(height: 1, color: dividerColor),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String emoji;
  final String text;
  const _Badge({required this.emoji, required this.text});

  @override
  Widget build(BuildContext context) {
    final bg = TeacherProfilePage.primary.withOpacity(0.18);
    final fg = TeacherProfilePage.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
