import 'package:flutter/material.dart';
import 'package:parent_app_taskazurah/screens/chat_screen.dart';

import 'teacher_activity_page.dart';

class Teacher {
  final String id;
  final String name;
  final String imageUrl;
  final String experience;
  final String username;

  const Teacher({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.experience,
    this.username = '',
  });
}

class TeacherProfilePage extends StatelessWidget {
  final Teacher teacher;
  final String? parentId;
  final String? parentName;
  const TeacherProfilePage({
    super.key,
    required this.teacher,
    this.parentId,
    this.parentName,
  });

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
    final cardBg = isDark ? Colors.black.withValues(alpha: 0.25) : Colors.white;

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
                      color: primary.withValues(alpha: 0.12),
                    ),
                    child: teacher.imageUrl.trim().isEmpty
                        ? Icon(Icons.person,
                            size: 64, color: primary.withValues(alpha: 0.9))
                        : ClipOval(
                            child: Image.network(
                              teacher.imageUrl,
                              width: 128,
                              height: 128,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(Icons.person,
                                  size: 64,
                                  color: primary.withValues(alpha: 0.9)),
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
                  if (teacher.username.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '@${teacher.username}',
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),

              // Profile details
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
                        Icons.star,
                        'Experience',
                        teacher.experience,
                        textSecondary,
                        textColor,
                        isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                      ),
                      if (teacher.username.trim().isNotEmpty)
                        _infoRow(
                          Icons.badge_outlined,
                          'Username',
                          teacher.username,
                          textSecondary,
                          textColor,
                          isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                        ),
                      if (parentId?.trim().isNotEmpty == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            'Messages and activity updates shown here are scoped to your family account.',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              color: textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (teacher.username.trim().isEmpty && teacher.experience.trim().isEmpty)
                        Text(
                          'No public teacher profile details are available yet.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Card(
                color: cardBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.collections_bookmark_outlined,
                        color: primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Open the activity feed to view teacher memories that involve your linked child records.',
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.45,
                            color: textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
                      final pid = (parentId ?? '').trim();
                      final pname = (parentName ?? '').trim();
                      if (pid.isEmpty || pname.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Please open chat from Dashboard so parent session is known.'),
                          ),
                        );
                        return;
                      }

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            teacherId: teacher.id,
                            teacherName: teacher.name,
                            parentId: pid,
                            parentName: pname,
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

              // 🔹 View Activities
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.collections_bookmark),
                  label: const Text(
                    'View Activities',
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
                    final pid = (parentId ?? '').trim();
                    if (pid.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Open this profile from the parent dashboard to load family activity updates.'),
                        ),
                      );
                      return;
                    }

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TeacherActivityPage(
                          teacher: teacher,
                          parentId: pid,
                        ),
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
