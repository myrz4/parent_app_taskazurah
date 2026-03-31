import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ChatScreen extends StatefulWidget {
  final String teacherId; // Firestore doc id
  final String teacherName; // display name, e.g. "Teacher Sofea"
  final String parentId; // Firestore doc id, e.g. "ezham_0194965099"
  final String parentName; // display name, e.g. "Ezham"

  const ChatScreen({
    super.key,
    required this.teacherId,
    required this.teacherName,
    required this.parentId,
    required this.parentName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgCtl = TextEditingController();
  final _scrollCtl = ScrollController();
  final _db = FirebaseFirestore.instance;

  late final DocumentReference<Map<String, dynamic>> _chatRef;

  static String _norm(String s) => s.trim().toLowerCase();

  static String _chatIdFor({required String teacherId, required String parentId}) {
    return 'teacher_${_norm(teacherId)}_parent_${_norm(parentId)}';
  }

  @override
  void initState() {
    super.initState();
    final chatId = _chatIdFor(teacherId: widget.teacherId, parentId: widget.parentId);
    _chatRef = _db.collection('chats').doc(chatId);

    // Mark as read for this side (best-effort).
    _chatRef.set({'unreadCountParent': 0}, SetOptions(merge: true)).catchError((_) {});
  }

  Future<void> _send() async {
    final text = _msgCtl.text.trim();
    if (text.isEmpty) return;

    // default: parent send
    await _chatRef.collection('messages').add({
      'senderRole': 'parent',
      'senderId': widget.parentId,
      'senderName': widget.parentName,
      // keep legacy field for backward-compatible UIs
      'sender': widget.parentName,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    });

    await _chatRef.set({
      'teacherId': widget.teacherId,
      // Legacy field kept for backward-compatible UIs; do not rely on this.
      'teacherUsername': _norm(widget.teacherId),
      'teacherName': widget.teacherName,
      'parentId': widget.parentId,
      // Legacy field kept for backward-compatible UIs; do not rely on this.
      'parentUsername': _norm(widget.parentId),
      'parentName': widget.parentName,
      'teacherRef': '/teachers/${widget.teacherId}',
      'parentRef': '/parents/${widget.parentId}',
      'lastMessage': text,
      'lastTimestamp': FieldValue.serverTimestamp(),
      // Unread counters (for list badge)
      'unreadCountParent': 0,
      'unreadCountTeacher': FieldValue.increment(1),
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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF7ACB9E),
        foregroundColor: Colors.white,
        title: Text('Chat • ${widget.teacherName}'),
      ),
      backgroundColor: const Color(0xFFF6F8F7),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _chatRef
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
                    final senderRole = (m['senderRole'] ?? '').toString();
                    final senderId = (m['senderId'] ?? '').toString();
                    final legacySender = (m['sender'] ?? '').toString();
                    final text = (m['text'] ?? '').toString();
                    final ts = m['timestamp'] as Timestamp?;

                    final isMe = (senderRole == 'parent' && senderId == widget.parentId) ||
                        (senderRole.isEmpty && (legacySender == widget.parentId || _norm(legacySender) == _norm(widget.parentName)));

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
