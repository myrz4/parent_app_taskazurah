import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../memory_journey/memory_detail_page.dart';
import '../parent_linked_children.dart';
import 'teacher_model.dart';

class TeacherActivityPage extends StatelessWidget {
  const TeacherActivityPage({
    super.key,
    required this.teacher,
    required this.parentId,
  });

  final Teacher teacher;
  final String parentId;

  static const Color primary = Color(0xFF7ACB9E);
  static const Color background = Color(0xFFF6F8F7);

  String _normalize(dynamic value) => (value ?? '').toString().trim().toLowerCase();

  String _extractChildId(Map<String, dynamic> data) {
    final childId = (data['child_id'] ?? data['childId'] ?? '').toString().trim();
    if (childId.isNotEmpty) {
      return childId;
    }
    final childRef = (data['child_ref'] ?? data['childRef'] ?? '').toString().trim();
    final marker = 'children/';
    final index = childRef.indexOf(marker);
    if (index < 0) {
      return '';
    }
    return childRef.substring(index + marker.length).trim();
  }

  Map<String, String> _detailPayload(Map<String, dynamic> data) {
    final timestamp = data['timestamp'];
    final time = timestamp is Timestamp
        ? DateFormat('d MMM yyyy, hh:mm a').format(timestamp.toDate())
        : '';
    return <String, String>{
      'image': (data['photo_url'] ?? '').toString(),
      'photo_url': (data['photo_url'] ?? '').toString(),
      'text': (data['description'] ?? '').toString(),
      'teacher': (data['teacher_name'] ?? '').toString(),
      'category': (data['category'] ?? '').toString(),
      'time': time,
      'child_name': (data['child_name'] ?? '').toString(),
      'child_ref': (data['child_ref'] ?? data['childRef'] ?? '').toString(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final parentRef = FirebaseFirestore.instance.collection('parents').doc(parentId.trim());

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: Text('${teacher.name} Activities'),
      ),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: parentRef.get(),
        builder: (context, parentSnapshot) {
          if (parentSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: primary),
            );
          }

          if (!parentSnapshot.hasData || !parentSnapshot.data!.exists) {
            return const Center(child: Text('Parent record not found.'));
          }

          final parentData = parentSnapshot.data!.data() ?? <String, dynamic>{};
          final linkedChildren = extractParentLinkedChildren(parentData);
          final allowedChildIds = linkedChildren
              .map((child) => child.childId.trim().toLowerCase())
              .where((id) => id.isNotEmpty)
              .toSet();

          if (allowedChildIds.isEmpty) {
            return const Center(
              child: Text('No linked children available for activity history.'),
            );
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('memory')
                .orderBy('timestamp', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: primary),
                );
              }

              final teacherUsername = _normalize(teacher.username);
              final teacherName = _normalize(teacher.name);
              final docs = snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];

              final filteredDocs = docs.where((doc) {
                final data = doc.data();
                final memoryTeacherUsername = _normalize(data['teacher_username']);
                final memoryTeacherName = _normalize(data['teacher_name']);
                final matchesTeacher = teacherUsername.isNotEmpty
                    ? memoryTeacherUsername == teacherUsername ||
                        (memoryTeacherUsername.isEmpty && memoryTeacherName == teacherName)
                    : memoryTeacherName == teacherName;
                if (!matchesTeacher) {
                  return false;
                }

                final childId = _extractChildId(data).toLowerCase();
                return allowedChildIds.contains(childId);
              }).toList();

              if (filteredDocs.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No activity updates from ${teacher.name} have been shared with your linked children yet.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: primary.withValues(alpha: 0.16),
                            backgroundImage: teacher.imageUrl.trim().isEmpty
                                ? null
                                : NetworkImage(teacher.imageUrl),
                            child: teacher.imageUrl.trim().isEmpty
                                ? Text(
                                    teacher.name.substring(0, 1).toUpperCase(),
                                    style: GoogleFonts.plusJakartaSans(
                                      color: primary,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  teacher.name,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${filteredDocs.length} activity updates across ${allowedChildIds.length} linked child${allowedChildIds.length == 1 ? '' : 'ren'}',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    color: Colors.black54,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ...filteredDocs.map((doc) {
                    final data = doc.data();
                    final photoUrl = (data['photo_url'] ?? '').toString().trim();
                    final description = (data['description'] ?? '').toString().trim();
                    final childName = (data['child_name'] ?? 'Child').toString().trim();
                    final category = (data['category'] ?? 'General').toString().trim();
                    final timestamp = data['timestamp'];
                    final formattedTime = timestamp is Timestamp
                        ? DateFormat('d MMM • hh:mm a').format(timestamp.toDate())
                        : '';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MemoryDetailPage(
                                memory: _detailPayload(data),
                              ),
                            ),
                          );
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (photoUrl.isNotEmpty)
                              ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(18),
                                ),
                                child: Image.network(
                                  photoUrl,
                                  width: double.infinity,
                                  height: 220,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    height: 220,
                                    color: Colors.grey.shade200,
                                    child: const Icon(Icons.broken_image_outlined),
                                  ),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: primary.withValues(alpha: 0.16),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          category,
                                          style: GoogleFonts.plusJakartaSans(
                                            color: primary,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        formattedTime,
                                        style: GoogleFonts.plusJakartaSans(
                                          color: Colors.black54,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    childName,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    description.isEmpty
                                        ? 'No description provided.'
                                        : description,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 14,
                                      height: 1.45,
                                      color: Colors.black87,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              );
            },
          );
        },
      ),
    );
  }
}