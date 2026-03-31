import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'chat_screen.dart';

class ChatListPage extends StatelessWidget {
  final String parentId; // Firestore doc id, e.g. "ezham_0194965099"
  final String parentName; // display name, e.g. "Ezham"

  const ChatListPage({
    super.key,
    required this.parentId,
    required this.parentName,
  });

  static const Color primary = Color(0xFF7ACB9E);

  static String _norm(String s) => s.trim().toLowerCase();

  static String _chatIdFor({required String teacherId, required String parentId}) {
    return 'teacher_${_norm(teacherId)}_parent_${_norm(parentId)}';
  }

  static int _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F7),
      appBar: AppBar(
        backgroundColor: primary,
        title: const Text(
          'Chat with Teachers',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('teachers').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final teacherDocs = snapshot.data?.docs ?? [];
          if (teacherDocs.isEmpty) {
            return const Center(
              child: Text(
                'No teachers available yet.',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            );
          }

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('chats')
                .where('parentId', isEqualTo: parentId)
                .snapshots(),
            builder: (context, chatsSnap) {
              if (chatsSnap.hasError) {
                return Center(child: Text('Error: ${chatsSnap.error}'));
              }

              final chatById = <String, Map<String, dynamic>>{};
              for (final d in (chatsSnap.data?.docs ?? const [])) {
                final data = d.data();
                if (data is Map<String, dynamic>) {
                  chatById[d.id] = data;
                }
              }

              final items = teacherDocs.map((doc) {
                final data = doc.data()! as Map<String, dynamic>;
                final teacherId = doc.id.trim();
                final teacherName =
                    (data['name'] as String?)?.trim().isNotEmpty == true
                        ? (data['name'] as String).trim()
                    : teacherId;

                final chatId = _chatIdFor(teacherId: teacherId, parentId: parentId);
                final chat = chatById[chatId];
                final lastTs = chat?['lastTimestamp'];

                return (
                  teacherId: teacherId,
                  teacherName: teacherName,
                  chatId: chatId,
                  lastTimestamp: lastTs is Timestamp ? lastTs : null,
                  lastMessage: (chat?['lastMessage'] ?? '').toString(),
                  unread: _asInt(chat?['unreadCountParent']),
                );
              }).toList();

              items.sort((a, b) {
                final at = a.lastTimestamp;
                final bt = b.lastTimestamp;
                if (at == null && bt == null) {
                  return a.teacherName.toLowerCase().compareTo(b.teacherName.toLowerCase());
                }
                if (at == null) return 1;
                if (bt == null) return -1;
                final cmp = bt.compareTo(at); // desc
                if (cmp != 0) return cmp;
                return a.teacherName.toLowerCase().compareTo(b.teacherName.toLowerCase());
              });

              return ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final it = items[index];
                  final subtitle = it.lastMessage.trim().isEmpty
                      ? 'Tap to start chatting'
                      : it.lastMessage.trim();

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: primary.withOpacity(0.25),
                        child: const Icon(Icons.person, color: Colors.black54),
                      ),
                      title: Text(
                        it.teacherName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.grey),
                      ),
                      trailing: it.unread > 0
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: primary,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                it.unread > 99 ? '99+' : it.unread.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            )
                          : null,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              teacherId: it.teacherId,
                              teacherName: it.teacherName,
                              parentId: parentId,
                              parentName: parentName,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
