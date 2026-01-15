import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class ParentProfilePage extends StatelessWidget {
  final String parentId;
  const ParentProfilePage({super.key, required this.parentId});

  // Theme constants
  static const Color primary = Color(0xFF7ACB9E);
  static const Color background = Color(0xFFF6F8F7);
  static const double _cardRadius = 16.0;
  static const double _cardElevation = 2.0;
  static const EdgeInsets _cardPadding = EdgeInsets.all(16.0);
  static const List<double> _spacing = [4.0, 8.0, 12.0, 16.0, 20.0, 24.0];

  // Text styles
  TextStyle get _heading => GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Colors.black87,
      );
  TextStyle get _subheading => GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Colors.black87,
      );
  TextStyle get _body => GoogleFonts.plusJakartaSans(
        fontSize: 15,
        color: Colors.grey[700],
      );
  TextStyle get _label => GoogleFonts.plusJakartaSans(
        fontSize: 14,
        color: Colors.grey[700],
      );
  TextStyle get _value => GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      );

  // Helpers
  String _formatDateTime(dynamic timestamp) {
    if (timestamp == null) return '–';
    DateTime? date;
    if (timestamp is Timestamp) {
      date = timestamp.toDate().toLocal();
    } else if (timestamp is String && timestamp.isNotEmpty) {
      try {
        date = DateTime.parse(timestamp).toLocal();
      } catch (_) {
        return timestamp;
      }
    }
    if (date == null) return '–';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final inputDay = DateTime(date.year, date.month, date.day);
    if (inputDay == today) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    return '${date.day} ${_shortMonth(date.month)} ${date.year}';
  }

  String _shortMonth(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month - 1];
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(title, style: _subheading),
        ),
      );

  Widget _avatar(String? photoUrl, {double size = 70, bool circular = false}) {
    final Widget fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: primary.withOpacity(0.15),
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular ? null : BorderRadius.circular(12),
      ),
      child: Icon(
        circular ? Icons.person : Icons.child_care,
        size: size * 0.5,
        color: primary,
      ),
    );

    if (photoUrl == null || photoUrl.isEmpty) return fallback;

    final image = NetworkImage(photoUrl);
    return circular
        ? CircleAvatar(radius: size / 2, backgroundImage: image)
        : ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image(
              image: image,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback,
            ),
          );
  }

  Widget _infoLabel(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _label),
          SizedBox(height: _spacing[0]),
          Text(value, style: _value),
        ],
      );

  Widget _switchTile(BuildContext context, String title, bool value,
      DocumentReference parentRef, String field) {
    return SwitchListTile(
      title: Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 15)),
      value: value,
      activeThumbColor: primary,
      onChanged: (bool newValue) async {
        try {
          await parentRef.set({
            'settings.notifications.$field': newValue,
          }, SetOptions(merge: true));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Notification preference updated')),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to save')),
            );
          }
        }
      },
    );
  }

  Future<DocumentSnapshot> _resolveRef(dynamic raw) async {
    if (raw == null) throw Exception('Reference is null');
    if (raw is DocumentReference) return raw.get();
    if (raw is String) {
      final path = raw.startsWith('/') ? raw.substring(1) : raw;
      return FirebaseFirestore.instance.doc(path).get();
    }
    throw Exception('Invalid reference type: ${raw.runtimeType}');
  }

  Future<String> _resolveTeacherName(dynamic teacherRef) async {
    if (teacherRef == null) return '–';
    try {
      final snap = await _resolveRef(teacherRef);
      if (!snap.exists) return '–';
      final data = snap.data() as Map<String, dynamic>?;
      return data?['name']?.toString() ?? '–';
    } catch (_) {
      return '–';
    }
  }

  void _stub(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('// TODO: Implement $feature')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parentRef =
        FirebaseFirestore.instance.collection('parents').doc(parentId);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        elevation: 2,
        backgroundColor: background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF2F5F4A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Profile',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: parentRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: primary));
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('Parent data not found'));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final parentName = data['parentName']?.toString() ?? 'N/A';
          final phone = data['phone']?.toString() ?? 'N/A';
          final photoUrl = data['photoUrl']?.toString();
          final rawChildren = data['childrenRefs'] ??
              (data['childRef'] != null ? [data['childRef']] : <dynamic>[]);
          final List<dynamic> childrenRefs =
              rawChildren is List ? rawChildren : [];
          final nfcTag = data['nfc']?['tagUid']?.toString() ??
              data['childId']?.toString() ??
              '–';
          final lastUsedRaw = data['nfc']?['lastUsed'] ?? data['qrExpiry'];
          final settings =
              (data['settings']?['notifications'] as Map<String, dynamic>?) ??
                  {};

          return SingleChildScrollView(
            padding: EdgeInsets.all(_spacing[3]),
            child: Column(
              children: [
                // A. Header
                Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(_cardRadius)),
                  elevation: _cardElevation,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: _cardPadding,
                    child: Column(
                      children: [
                        _avatar(photoUrl, size: 96, circular: true),
                        SizedBox(height: _spacing[3]),
                        Text(parentName, style: _heading),
                        SizedBox(height: _spacing[0]),
                        Text(phone, style: _body),
                        SizedBox(height: _spacing[3]),
                      
                      
                      ],
                    ),
                  ),
                ),

                // B. My Children
                _sectionTitle('My Children'),
                if (childrenRefs.isEmpty)
                  Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(_cardRadius)),
                    elevation: _cardElevation,
                    child: Padding(
                      padding: _cardPadding,
                      child: Row(
                        children: [
                          Icon(Icons.child_care, color: Colors.grey[600]),
                          SizedBox(width: _spacing[2]),
                          Text('No children linked yet', style: _body),
                        ],
                      ),
                    ),
                  )
                else
                  ...childrenRefs.map((rawRef) =>
                      FutureBuilder<DocumentSnapshot>(
                        future: _resolveRef(rawRef),
                        builder: (context, childSnap) {
                          if (childSnap.connectionState ==
                              ConnectionState.waiting) {
                            return _skeletonCard();
                          }
                          if (childSnap.hasError ||
                              !childSnap.hasData ||
                              !childSnap.data!.exists) {
                            return _errorCard('Failed to load child');
                          }
                          final childData =
                              childSnap.data!.data() as Map<String, dynamic>;
                          final childId = childSnap.data!.id;
                          final childName =
                              childData['name']?.toString() ?? 'Unknown';
                          final childPhoto = childData['photoUrl']?.toString();
                          final className =
                              childData['className']?.toString() ??
                                  data['className']?.toString() ??
                                  '–';

                          return FutureBuilder<String>(
                            future: _resolveTeacherName(
                                childData['teacherRef'] ?? data['teacherRef']),
                            builder: (context, teacherSnap) {
                              final teacherName = teacherSnap.data ?? '–';

                              return Card(
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(_cardRadius)),
                                elevation: _cardElevation,
                                margin:
                                    const EdgeInsets.only(bottom: 12, top: 4),
                                child: Padding(
                                  padding: _cardPadding,
                                  child: Row(
                                    children: [
                                      _avatar(childPhoto, size: 70),
                                      SizedBox(width: _spacing[3]),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(childName,
                                                style:
                                                    GoogleFonts.plusJakartaSans(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w600)),
                                            Text('Class: $className',
                                                style: _body),
                                            Text('Teacher: $teacherName',
                                                style: _body),
                                          ],
                                        ),
                                      ),
                                      ElevatedButton(
                                        onPressed: () => _stub(
                                            context, 'View Child: $childId'),
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor: primary,
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12))),
                                        child: Text('View Details',
                                            style: GoogleFonts.plusJakartaSans(
                                                color: Colors.white,
                                                fontSize: 14)),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      )),

                // C. Linked Guardians (optional)
                if (data['linkedGuardians'] is List &&
                    (data['linkedGuardians'] as List).isNotEmpty) ...[
                  _sectionTitle('Linked Guardians'),
                  ...(data['linkedGuardians'] as List)
                      .cast<Map<String, dynamic>>()
                      .map((g) {
                    final name = g['name']?.toString() ?? '–';
                    final relation = g['relationship']?.toString() ?? '–';
                    final phone = g['phone']?.toString() ?? '–';
                    return Card(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(_cardRadius)),
                      elevation: _cardElevation,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text(name, style: _value),
                        subtitle: Text('$relation • $phone', style: _body),
                      ),
                    );
                  }),
                ],

                // D. NFC Tag Information
                _sectionTitle('NFC Tag Information'),
                Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(_cardRadius)),
                  elevation: _cardElevation,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: _cardPadding,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.nfc, color: primary, size: 28),
                            SizedBox(width: _spacing[2]),
                            _infoLabel('Tag UID', nfcTag),
                          ],
                        ),
                        _infoLabel('Last Used', _formatDateTime(lastUsedRaw)),
                      ],
                    ),
                  ),
                ),

                // E. Notification Preferences
                _sectionTitle('Notifications'),
                Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(_cardRadius)),
                  elevation: _cardElevation,
                  child: Column(
                    children: [
                      _switchTile(context, 'Attendance Alerts',
                          settings['attendance'] ?? true, parentRef, 'attendance'),
                      const Divider(height: 1),
                      _switchTile(context, 'Activity Updates',
                          settings['activity'] ?? true, parentRef, 'activity'),
                      const Divider(height: 1),
                      _switchTile(context, 'Fee Reminders',
                          settings['fees'] ?? false, parentRef, 'fees'),
                      const Divider(height: 1),
                      _switchTile(context, 'Emergency Alerts',
                          settings['emergency'] ?? true, parentRef, 'emergency'),
                    ],
                  ),
                ),

                // F. Documents
                _sectionTitle('Documents'),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _stub(context, 'Attendance History'),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: primary),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: EdgeInsets.symmetric(vertical: _spacing[3]),
                        ),
                        child: Text('Attendance History',
                            style: GoogleFonts.plusJakartaSans(color: primary)),
                      ),
                    ),
                    SizedBox(width: _spacing[2]),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _stub(context, 'Invoices & Receipts'),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: primary),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: EdgeInsets.symmetric(vertical: _spacing[3]),
                        ),
                        child: Text('Invoices & Receipts',
                            style: GoogleFonts.plusJakartaSans(color: primary)),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: _spacing[5]),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _skeletonCard() => Card(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_cardRadius)),
        elevation: _cardElevation,
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: _cardPadding,
          child: Row(
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              SizedBox(width: _spacing[3]),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(width: 120, height: 16, color: Colors.grey[300]),
                    SizedBox(height: _spacing[1]),
                    Container(width: 80, height: 14, color: Colors.grey[300]),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _errorCard(String message) => Card(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_cardRadius)),
        elevation: _cardElevation,
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: _cardPadding,
          child: Text(message, style: TextStyle(color: Colors.red[700])),
        ),
      );
}
