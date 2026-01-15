import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ChatScreen extends StatefulWidget {
  final String chatId; // contoh: teacher_sofea_parent_ezham
  final String teacherUsername; // contoh: sofea
  final String parentUsername; // contoh: ezham

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.teacherUsername,
    required this.parentUsername,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgCtl = TextEditingController();
  final _scrollCtl = ScrollController();
  final _db = FirebaseFirestore.instance;

  Future<void> _send() async {
    final text = _msgCtl.text.trim();
    if (text.isEmpty) return;

    print('🟢 Sending message: $text');
    print('Chat ID: ${widget.chatId}');
    print(
        'Teacher: ${widget.teacherUsername}, Parent: ${widget.parentUsername}');

    final chatRef = _db.collection('chats').doc(widget.chatId);

    // default: parent send
    await chatRef.collection('messages').add({
      'sender': widget.parentUsername,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    });

    await chatRef.set({
      'teacherUsername': widget.teacherUsername,
      'parentUsername': widget.parentUsername,
      'teacherRef': '/teachers/${widget.teacherUsername}',
      'parentRef': '/parents/${widget.parentUsername}',
      'lastMessage': text,
      'lastTimestamp': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    _msgCtl.clear();

    Future.delayed(const Duration(milliseconds: 250), () {
      if (_scrollCtl.hasClients) {
        _scrollCtl.jumpTo(_scrollCtl.position.maxScrollExtent);
      }
    });
  }

  // 🌟 Quick Suggested Message Button
  Widget _quickMsg(String text, {String? emoji}) {
    return GestureDetector(
      onTap: () {
        _msgCtl.text = text;
        _send();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF7ACB9E).withOpacity(0.15),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF7ACB9E)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (emoji != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(emoji, style: const TextStyle(fontSize: 14)),
              ),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(
                  color: Color(0xFF2E7D32),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _msgCtl.dispose();
    _scrollCtl.dispose();
    super.dispose();
  }

  String _formatLocalTime(Timestamp? ts) {
    if (ts == null) return '';
    final localTime =
        ts.toDate(); // Firestore already returns in local timezone
    return DateFormat('hh:mm a').format(localTime);
  }

  @override
  Widget build(BuildContext context) {
    final chatRef = _db.collection('chats').doc(widget.chatId);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF7ACB9E),
        foregroundColor: Colors.white,
        title: Text('Chat • ${widget.teacherUsername.toUpperCase()}'),
      ),
      backgroundColor: const Color(0xFFF6F8F7),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: chatRef
                  .collection('messages')
                  .orderBy('timestamp', descending: false)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snap.data!.docs;
                if (messages.isEmpty) {
                  return const Center(child: Text('No messages yet.'));
                }

                return ListView.builder(
                  controller: _scrollCtl,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (_, i) {
                    final m = messages[i].data() as Map<String, dynamic>;
                    final sender = (m['sender'] ?? '').toString();
                    final text = (m['text'] ?? '').toString();
                    final ts = m['timestamp'] as Timestamp?;
                    final isMe = sender == widget.parentUsername;

                    final time = _formatLocalTime(ts);

                    return Align(
                      alignment:
                          isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.all(12),
                        constraints:
                            const BoxConstraints(maxWidth: 280, minWidth: 60),
                        decoration: BoxDecoration(
                          color: isMe ? const Color(0xFFB2E4C8) : Colors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(14),
                            topRight: const Radius.circular(14),
                            bottomLeft: Radius.circular(isMe ? 14 : 0),
                            bottomRight: Radius.circular(isMe ? 0 : 14),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(text, style: const TextStyle(fontSize: 16)),
                            const SizedBox(height: 4),
                            Text(
                              time,
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // 🌟 Suggested Quick Messages
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _quickMsg("Anak saya okay harini 😊", emoji: "👶"),
                  const SizedBox(width: 8),
                  _quickMsg("Saya on the way pickup 🚗", emoji: "🚗"),
                  const SizedBox(width: 8),
                  _quickMsg("Saya ada emergency ⚠️", emoji: "⚠️"),
                  const SizedBox(width: 8),
                  _quickMsg("Terima kasih cikgu 🙏", emoji: "🙏"),
                ],
              ),
            ),
          ),

          // 💬 Input section
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F4F3),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _msgCtl,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          hintText: 'Type a message...',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: const Color(0xFF2E7D32),
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: _send,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
