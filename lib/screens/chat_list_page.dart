import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'chat_screen.dart';

class ChatListPage extends StatelessWidget {
  final String parentUsername; // e.g. "ezham", dynamic ikut login parent

  const ChatListPage({super.key, required this.parentUsername});

  static const Color primary = Color(0xFF7ACB9E);

  @override
  Widget build(BuildContext context) {
    final lowerParent = parentUsername.toLowerCase();

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
        stream: FirebaseFirestore.instance
            .collection('chats')
            .where('parentUsername', isEqualTo: lowerParent)
            .orderBy('lastTimestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final chatDocs = snapshot.data?.docs ?? [];
          if (chatDocs.isEmpty) {
            return const Center(
              child: Text(
                'No chats available yet.',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            );
          }

          return ListView.builder(
            itemCount: chatDocs.length,
            itemBuilder: (context, index) {
              final data = chatDocs[index].data()! as Map<String, dynamic>;

              // safe casting
              final String teacherUsername =
                  (data['teacherUsername'] as String?)?.trim().toLowerCase() ??
                      'unknown';
              final String parentUsernameField =
                  (data['parentUsername'] as String?)?.trim().toLowerCase() ??
                      lowerParent;
              final String lastMessage =
                  (data['lastMessage'] as String?) ?? 'No message yet';
              final Timestamp? lastTimestamp =
                  data['lastTimestamp'] as Timestamp?;

              // format time nicely
              String formattedTime = '';
              if (lastTimestamp != null) {
                try {
                  formattedTime =
                      DateFormat('hh:mm a').format(lastTimestamp.toDate());
                } catch (_) {}
              }

              String capitalize(String text) {
                if (text.isEmpty) return text;
                return text[0].toUpperCase() + text.substring(1);
              }

              // build chatId dynamically (same pattern used in chat_screen)
              final chatId =
                  'teacher_${teacherUsername}_parent_$parentUsernameField'
                      .toLowerCase();

              return Card(
                margin:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                    'Teacher ${capitalize(teacherUsername)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Text(
                    lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  trailing: Text(
                    formattedTime,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  onTap: () {
                    // when user taps a teacher, open chat_screen with correct document id
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          chatId: chatId,
                          teacherUsername: teacherUsername,
                          parentUsername: parentUsernameField,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
