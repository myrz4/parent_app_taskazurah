import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'teacher_model.dart'; // import model + profile page

class TeacherListPage extends StatelessWidget {
  const TeacherListPage({super.key});

  static const Color primary = Color(0xFF7ACB9E);
  static const Color backgroundLight = Color(0xFFFFFFFF);
  static const Color backgroundDark = Color(0xFF112117);
  static const Color textLight = Color(0xFF1E293B);
  static const Color textDark = Color(0xFFF8FAFC);
  static const Color subtleLight = Color(0xFFF1F5F9);
  static const Color subtleDark = Color(0xFF1E293B);

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final parentId = (args?['parentId'] ?? '').toString().trim();
    final parentName = (args?['parentName'] ?? '').toString().trim();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? textDark : textLight;
    final bgSubtle = isDark ? subtleDark : subtleLight;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 🔹 HEADER
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              color: isDark ? backgroundDark : backgroundLight,
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: textColor),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      'Our Teachers',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            // 🔹 FIRESTORE STREAM
            Expanded(
              child: FirebaseAuth.instance.currentUser == null
                  ? const Center(child: Text('Please sign in to view teachers.'))
                  : StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('teachers')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          'Failed to load teachers.\n${snapshot.error}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data?.docs ?? const [];
                  if (docs.isEmpty) {
                    return const Center(child: Text("No teachers found"));
                  }

                  final teachers = docs
                      .map((d) {
                        final raw = d.data();
                        if (raw is! Map<String, dynamic>) return null;

                        final name = (raw['name'] ?? '').toString().trim();
                        final image = (raw['image'] ?? '').toString().trim();
                        final experience = (raw['experience'] ?? 'N/A').toString().trim();

                        return Teacher(
                          id: d.id,
                          name: name.isEmpty ? d.id : name,
                          imageUrl: image,
                          experience: experience.isEmpty ? 'N/A' : experience,
                        );
                      })
                      .whereType<Teacher>()
                      .toList();

                  teachers.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

                  if (teachers.isEmpty) {
                    return const Center(child: Text("No teachers found"));
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: teachers.length,
                    itemBuilder: (context, index) {
                      final teacher = teachers[index];

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Material(
                          borderRadius: BorderRadius.circular(16),
                          color: bgSubtle,
                          elevation: 3,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      TeacherProfilePage(
                                        teacher: teacher,
                                        parentId: parentId.isEmpty ? null : parentId,
                                        parentName: parentName.isEmpty ? null : parentName,
                                      ),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: bgSubtle,
                                    ),
                                    child: teacher.imageUrl.trim().isEmpty
                                        ? Icon(Icons.person,
                                            color: primary.withOpacity(0.9))
                                        : ClipOval(
                                            child: Image.network(
                                              teacher.imageUrl,
                                              width: 64,
                                              height: 64,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  Icon(Icons.person,
                                                      color: primary
                                                          .withOpacity(0.9)),
                                            ),
                                          ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          teacher.name,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: textColor,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Experience: ${teacher.experience}',
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey.shade600),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.chevron_right,
                                      color: Colors.grey.shade600),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
