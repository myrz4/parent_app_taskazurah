import 'dart:math';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:parent_app_taskazurah/screens/attendance_dashboard.dart';
import 'package:parent_app_taskazurah/screens/chat_list_page.dart';
import 'package:parent_app_taskazurah/screens/parent_profile_page.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';



class TaskaZurahDashboard extends StatefulWidget {
  const TaskaZurahDashboard({super.key});

  @override
  State<TaskaZurahDashboard> createState() => _TaskaZurahDashboardState();

  static const Color primary = Color(0xFF7ACB9E);
  static const Color background = Color(0xFFF1F8E9);
  static const Color cardBg = Colors.white;
  static const Color shadowColor = Color(0x1F000000);
}

class _TaskaZurahDashboardState extends State<TaskaZurahDashboard> {
  String? _selectedChildId;

  static const MethodChannel _qrGalleryChannel = MethodChannel('com.taska/qr_gallery');

  static const Color primary = TaskaZurahDashboard.primary;
  static const Color background = TaskaZurahDashboard.background;
  static const Color cardBg = TaskaZurahDashboard.cardBg;
  static const Color shadowColor = TaskaZurahDashboard.shadowColor;

  static const double _radius = 24;
  static const double _elevation = 10;
  static const EdgeInsets _padding = EdgeInsets.symmetric(horizontal: 20, vertical: 12);
  static const List<double> _s = [0, 6, 12, 16, 20, 28, 36, 48];

  TextStyle get _greeting => GoogleFonts.plusJakartaSans(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: Colors.black87,
      );
  TextStyle get _title => GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: Colors.black87,
      );
  TextStyle get _subtitle => GoogleFonts.plusJakartaSans(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: Colors.black87,
      );
  TextStyle get _body => GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      );
  TextStyle get _caption => GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: Colors.black54,
      );

  DateTime? _readAttendanceTimestamp(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  String _readAttendanceString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = (data[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _attendanceMethodLabel(String value, {required bool isCheckout}) {
    switch (value.trim().toUpperCase()) {
      case 'NFC':
        return isCheckout ? 'NFC scan' : 'NFC tap';
      case 'QR':
      case 'PARENT_QR':
        return 'Parent QR';
      case 'MANUAL':
      case 'ADMIN_MANUAL':
        return 'Admin manual';
      default:
        return '';
    }
  }

  String _attendanceSourceSummary(Map<String, dynamic> data) {
    final inMethod = _attendanceMethodLabel(
      _readAttendanceString(data, const ['checkInMethod', 'checkin_method']),
      isCheckout: false,
    );
    final outMethod = _attendanceMethodLabel(
      _readAttendanceString(data, const ['checkOutMethod', 'checkout_method']),
      isCheckout: true,
    );
    final parts = <String>[];
    if (inMethod.isNotEmpty) parts.add('In: $inMethod');
    if (outMethod.isNotEmpty) parts.add('Out: $outMethod');
    return parts.join(' • ');
  }

  String _attendanceCorrectionActor(Map<String, dynamic> data) {
    final auditMetadata = data['auditMetadata'];
    if (auditMetadata is Map) {
      final lastActorName = (auditMetadata['lastActorName'] ?? '').toString().trim();
      if (lastActorName.isNotEmpty) return lastActorName;
    }
    return _readAttendanceString(data, const ['checkedOutByName', 'checkedInByName']);
  }

  Widget _adminCorrectedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2BC55)),
      ),
      child: Text(
        'Admin corrected',
        style: _caption.copyWith(
          color: const Color(0xFF7A5C00),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  List<_ChildChoice> _extractChildren(Map<String, dynamic> parentData) {
    final List<_ChildChoice> out = [];

    List<dynamic> asList(dynamic v) {
      if (v is List) return v;
      return const <dynamic>[];
    }

    DocumentReference? toChildRef(dynamic raw) {
      if (raw == null) return null;
      if (raw is DocumentReference) return raw;
      if (raw is String) {
        var path = raw.trim();
        if (path.isEmpty) return null;

        // JavaFX (Firestore REST) often stores full resource names like:
        // projects/<p>/databases/(default)/documents/children/<id>
        // Convert these into a Firestore SDK path: children/<id>
        path = path.startsWith('/') ? path.substring(1) : path;
        final docsMarker = '/documents/';
        final idx = path.indexOf(docsMarker);
        if (idx >= 0) {
          path = path.substring(idx + docsMarker.length);
        }
        if (path.startsWith('documents/')) {
          path = path.substring('documents/'.length);
        }
        final childIdx = path.indexOf('children/');
        if (childIdx < 0) return null;
        path = path.substring(childIdx);

        return FirebaseFirestore.instance.doc(path);
      }
      return null;
    }

    String idFromRef(DocumentReference ref) => ref.id.trim();

    // New arrays from JavaFX Admin
    final refsRaw = parentData['childRefs'] ?? parentData['childrenRefs'];
    final idsRaw = parentData['childIds'];
    final namesRaw = parentData['childNames'];

    final List<dynamic> refs = asList(refsRaw);
    final List<dynamic> ids = asList(idsRaw);
    final List<dynamic> names = asList(namesRaw);

    if (refs.isNotEmpty) {
      for (int i = 0; i < refs.length; i++) {
        final ref = toChildRef(refs[i]);
        if (ref == null) continue;
        final id = idFromRef(ref);
        if (id.isEmpty) continue;
        final name = (i < names.length ? (names[i] ?? '') : '').toString().trim();
        out.add(_ChildChoice(childId: id, childName: name.isEmpty ? id : name, childRef: ref));
      }
    } else if (ids.isNotEmpty) {
      for (int i = 0; i < ids.length; i++) {
        final id = (ids[i] ?? '').toString().trim();
        if (id.isEmpty) continue;
        final name = (i < names.length ? (names[i] ?? '') : '').toString().trim();
        final ref = FirebaseFirestore.instance.collection('children').doc(id);
        out.add(_ChildChoice(childId: id, childName: name.isEmpty ? id : name, childRef: ref));
      }
    }

    // Legacy single-child fallback
    if (out.isEmpty) {
      final legacyRef = toChildRef(parentData['childRef']);
      if (legacyRef != null) {
        final id = idFromRef(legacyRef);
        final name = (parentData['childName'] ?? id).toString().trim();
        out.add(_ChildChoice(childId: id, childName: name.isEmpty ? id : name, childRef: legacyRef));
      } else {
        final legacyId = (parentData['childId'] ?? '').toString().trim();
        if (legacyId.isNotEmpty) {
          final name = (parentData['childName'] ?? legacyId).toString().trim();
          out.add(
            _ChildChoice(
              childId: legacyId,
              childName: name.isEmpty ? legacyId : name,
              childRef: FirebaseFirestore.instance.collection('children').doc(legacyId),
            ),
          );
        }
      }
    }

    // Dedupe by childId (keep first)
    final seen = <String>{};
    final deduped = <_ChildChoice>[];
    for (final c in out) {
      if (seen.add(c.childId)) deduped.add(c);
    }
    return deduped;
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final parentId = (args?['parentId'] ?? '').toString().trim();
    final parentName = (args?['parentName'] ?? 'Parent').toString().trim();

    if (parentId.isEmpty) {
      return const Scaffold(
        backgroundColor: background,
        body: Center(child: Text('Missing parentId argument')),
      );
    }

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('parents').doc(parentId).get(),
      builder: (context, parentSnapshot) {
        if (parentSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: background,
            body: Center(child: CircularProgressIndicator(color: primary)),
          );
        }
        if (!parentSnapshot.hasData || !parentSnapshot.data!.exists) {
          return const Scaffold(
            backgroundColor: background,
            body: Center(child: Text('Parent record not found')),
          );
        }

        final parentData = parentSnapshot.data!.data() as Map<String, dynamic>;

        final children = _extractChildren(parentData);
        if (children.isEmpty) {
          return Scaffold(
            backgroundColor: background,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.sentiment_dissatisfied, size: 80, color: Colors.grey[400]),
                  SizedBox(height: _s[4]),
                  Text('Tiada anak berdaftar', style: _title.copyWith(color: Colors.grey[600])),
                  SizedBox(height: _s[2]),
                  Text('Sila hubungi pengurusan taska', style: _caption),
                ],
              ),
            ),
          );
        }

        final String selectedId =
            children.any((c) => c.childId == _selectedChildId) ? _selectedChildId! : children.first.childId;
        final _ChildChoice selectedChild = children.firstWhere((c) => c.childId == selectedId);

        return FutureBuilder<DocumentSnapshot>(
          future: selectedChild.childRef.get(),
          builder: (context, childSnapshot) {
            if (childSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                backgroundColor: background,
                body: Center(child: CircularProgressIndicator(color: primary)),
              );
            }
            if (childSnapshot.hasError) {
              final msg = childSnapshot.error.toString();
              final isPermission = msg.toLowerCase().contains('permission') || msg.toLowerCase().contains('permission-denied');
              return Scaffold(
                backgroundColor: background,
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isPermission
                              ? 'Permission denied to read child record. Please contact admin to refresh child-parent linking.'
                              : 'Failed to load child record: $msg',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () async {
                            try {
                              await FirebaseAuth.instance.signOut();
                            } catch (_) {
                              // Best-effort.
                            }
                            if (!context.mounted) return;
                            Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
                          },
                          child: const Text('Back to Login'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
            if (!childSnapshot.hasData || !childSnapshot.data!.exists) {
              return const Scaffold(
                backgroundColor: background,
                body: Center(child: Text('Child record not found')),
              );
            }

            final childData = childSnapshot.data!.data() as Map<String, dynamic>;
            final String childDocId = childSnapshot.data!.id;
            final String childName = (childData['name'] ?? selectedChild.childName).toString();
            final String childIdForAttendance = selectedChild.childId;

            String photoUrl = (childData['photoUrl'] ?? childData['imageUrl'] ?? '').toString().trim();
            if (photoUrl.isEmpty || !photoUrl.startsWith('http')) {
              photoUrl =
                  'https://ui-avatars.com/api/?name=${Uri.encodeComponent(childName)}&size=300&background=7ACB9E&color=fff&bold=true';
            }

            return Scaffold(
              backgroundColor: background,
              body: CustomScrollView(
                slivers: [
                  SliverAppBar(
                    backgroundColor: background,
                    elevation: 0,
                    floating: true,
                    actions: const [],
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: _padding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    children: [
                                      TextSpan(text: 'Good morning,\n', style: _greeting.copyWith(fontSize: 24)),
                                      TextSpan(text: parentName, style: _greeting.copyWith(color: primary)),
                                    ],
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () => Navigator.push(
                                  context,
                                  PageRouteBuilder(
                                    pageBuilder: (_, __, ___) => ParentProfilePage(parentId: parentId),
                                    transitionDuration: const Duration(milliseconds: 400),
                                    transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
                                  ),
                                ),
                                child: _avatar(photoUrl, size: 72),
                              ),
                            ],
                          ),
                          SizedBox(height: _s[5]),

                          Card(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
                            elevation: _elevation,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(_radius),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [cardBg, primary.withValues(alpha: 0.03)],
                                ),
                              ),
                              padding: EdgeInsets.all(_s[4]),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Hero(tag: 'child_avatar_$childDocId', child: _avatar(photoUrl, size: 80)),
                                      SizedBox(width: _s[4]),
                                      Expanded(
                                        child: Text(childName, style: _title.copyWith(fontSize: 22)),
                                      ),
                                    ],
                                  ),
                                  if (children.length > 1) ...[
                                    SizedBox(height: _s[3]),
                                    DropdownButtonFormField<String>(
                                      initialValue: selectedChild.childId,
                                      decoration: const InputDecoration(
                                        labelText: 'Select child',
                                        border: OutlineInputBorder(),
                                      ),
                                      items: [
                                        for (final c in children)
                                          DropdownMenuItem<String>(
                                            value: c.childId,
                                            child: Text(c.childName),
                                          ),
                                      ],
                                      onChanged: (v) {
                                        final newId = (v ?? '').trim();
                                        if (newId.isEmpty || newId == _selectedChildId) return;
                                        setState(() => _selectedChildId = newId);
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          SizedBox(height: _s[5]),

                          Card(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
                            elevation: _elevation,
                            child: Container(
                              padding: EdgeInsets.all(_s[4]),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(_radius),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    const Color.fromARGB(255, 241, 255, 247).withValues(alpha: 0.05),
                                    cardBg,
                                  ],
                                ),
                              ),
                              child: StreamBuilder<QuerySnapshot>(
                                stream: FirebaseFirestore.instance
                                    .collection('attendance')
                                  .where('childId', isEqualTo: childIdForAttendance)
                                    .orderBy('check_in_time', descending: true)
                                    .limit(1)
                                    .snapshots(),
                                builder: (context, snapshot) {
                                  String statusText = 'Belum check-in';
                                  String subtitleText = 'Tiada rekod';
                                  Color statusColor = Colors.orange;
                                  IconData statusIcon = Icons.access_time;
                                  bool glow = false;
                                  bool isAdminCorrected = false;

                                  if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                                    final data = snapshot.data!.docs.first.data() as Map<String, dynamic>;
                                    final checkInTime = _readAttendanceTimestamp(
                                      data,
                                      const ['checkInAt', 'check_in_time', 'checkInTime', 'check_in'],
                                    );
                                    final checkOutTime = _readAttendanceTimestamp(
                                      data,
                                      const ['checkOutAt', 'check_out_time', 'checkOutTime', 'check_out'],
                                    );
                                    final sourceSummary = _attendanceSourceSummary(data);
                                    final manualReason = _readAttendanceString(
                                      data,
                                      const ['manualEditReason', 'reason'],
                                    );
                                    final correctionActor = _attendanceCorrectionActor(data);
                                    isAdminCorrected =
                                      manualReason.isNotEmpty || sourceSummary.toLowerCase().contains('admin manual');

                                    if (checkOutTime != null) {
                                      statusText = 'Checked Out';
                                      statusIcon = Icons.logout_rounded;
                                      statusColor = const Color.fromARGB(255, 76, 142, 107);
                                      subtitleText = 'Jam ${DateFormat('hh:mm a').format(checkOutTime)}';
                                    } else if (checkInTime != null) {
                                      statusText = 'Checked In';
                                      statusIcon = Icons.check_circle;
                                      statusColor = const Color.fromARGB(255, 111, 177, 140);
                                      glow = true;
                                      subtitleText = 'Jam ${DateFormat('hh:mm a').format(checkInTime)}';
                                    } else {
                                      statusText = 'Absent';
                                      statusIcon = Icons.cancel;
                                      statusColor = Colors.red;
                                      subtitleText = 'Tidak hadir hari ini';
                                    }

                                    if (sourceSummary.isNotEmpty) {
                                      subtitleText = '$subtitleText\n$sourceSummary';
                                    }
                                    if (manualReason.isNotEmpty) {
                                      subtitleText = '$subtitleText\nReason: $manualReason';
                                    }
                                    if (isAdminCorrected && correctionActor.isNotEmpty) {
                                      subtitleText = '$subtitleText\nUpdated by: $correctionActor';
                                    }
                                  }

                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('Live Attendance Status', style: _title),
                                          GestureDetector(
                                            onTap: () {
                                              Navigator.pushNamed(
                                                context,
                                                '/attendance_history',
                                                arguments: {
                                                  'childId': childIdForAttendance,
                                                  'childName': childName,
                                                },
                                              );
                                            },
                                            child: Text(
                                              'View History',
                                              style: _body.copyWith(
                                                color: primary,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: _s[2]),
                                      GestureDetector(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  AttendancePage(childId: childIdForAttendance, childName: childName),
                                            ),
                                          );
                                        },
                                        child: Container(
                                          padding: EdgeInsets.all(_s[3]),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(_radius),
                                            color: statusColor.withValues(alpha: 0.08),
                                            border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                                            boxShadow: glow
                                                ? [
                                                    BoxShadow(
                                                      color: statusColor.withValues(alpha: 0.35),
                                                      blurRadius: 20,
                                                      spreadRadius: 1,
                                                    )
                                                  ]
                                                : [],
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                padding: EdgeInsets.all(_s[2]),
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: statusColor.withValues(alpha: 0.15),
                                                ),
                                                child: Icon(statusIcon, color: statusColor, size: 30),
                                              ),
                                              SizedBox(width: _s[3]),
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(statusText, style: _subtitle.copyWith(color: statusColor)),
                                                  if (snapshot.hasData && snapshot.data!.docs.isNotEmpty && isAdminCorrected) ...[
                                                    SizedBox(height: _s[1]),
                                                    _adminCorrectedBadge(),
                                                  ],
                                                  Text(subtitleText, style: _caption),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                          SizedBox(height: _s[5]),

                          Text('Quick Access', style: _title),
                          SizedBox(height: _s[3]),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final double tileWidth = (constraints.maxWidth - _s[3] * 2) / 3;
                              return GridView.builder(
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: _s[3],
                                  mainAxisSpacing: _s[3],
                                  childAspectRatio: tileWidth / (tileWidth + 20),
                                ),
                                itemCount: 6,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemBuilder: (context, index) {
                                  final tiles = [
                                    _quickTile(
                                      icon: Icons.receipt_long,
                                      label: 'Invoices',
                                      onTap: () => Navigator.pushNamed(
                                        context,
                                        '/fees_dashboard',
                                        arguments: {
                                          'parentId': parentId,
                                          'parentName': parentName,
                                        },
                                      ),
                                    ),
                                    _quickTile(
                                      icon: Icons.event_available,
                                      label: 'Attendance',
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                AttendancePage(childId: childIdForAttendance, childName: childName),
                                          ),
                                        );
                                      },
                                    ),
                                    _quickTile(
                                      icon: Icons.photo_library,
                                      label: 'Memory\nJourney',
                                      onTap: () => Navigator.pushNamed(context, '/memory_journey'),
                                    ),
                                    _quickTile(
                                      icon: Icons.school,
                                      label: 'Teacher\nInfo',
                                      onTap: () => Navigator.pushNamed(
                                        context,
                                        '/teacher_list',
                                        arguments: {
                                          'parentId': parentId,
                                          'parentName': parentName,
                                        },
                                      ),
                                    ),
                                    _quickTile(
                                      icon: Icons.qr_code_2,
                                      label: 'Pickup',
                                      onTap: () => _showQrModal(
                                        context,
                                        parentId: parentId,
                                        parentData: parentData,
                                        childId: selectedChild.childId,
                                        childName: childName,
                                        childRef: selectedChild.childRef,
                                      ),
                                    ),
                                    _quickTile(
                                      icon: Icons.person,
                                      label: 'Profile',
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => ParentProfilePage(parentId: parentId)),
                                        );
                                      },
                                    ),
                                  ];
                                  return tiles[index];
                                },
                              );
                            },
                          ),
                          SizedBox(height: _s[7]),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              floatingActionButton: FloatingActionButton.extended(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatListPage(
                        parentId: parentId,
                        parentName: parentName,
                      ),
                    ),
                  );
                },
                backgroundColor: primary,
                elevation: 12,
                icon: const Icon(Icons.chat_bubble, color: Colors.white),
                label: Text(
                  'Chat',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
            );
          },
        );
      },
    );
  }

  Widget _quickTile({required IconData icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
        elevation: 12,
        shadowColor: shadowColor,
        child: Container(
          padding: EdgeInsets.all(_s[2]),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_radius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cardBg, primary.withValues(alpha: 0.08)],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(_s[2]),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [primary, Color(0xFF5AB68A)]),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.5),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 32),
              ),
              SizedBox(height: _s[1]),
              Text(
                label,
                style: _body.copyWith(fontWeight: FontWeight.w700, fontSize: 12),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatar(String url, {required double size}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          color: primary.withValues(alpha: 0.15),
          child: Icon(Icons.person, color: primary, size: size * 0.6),
        ),
      ),
    );
  }

  void _showQrModal(
    BuildContext context, {
    required String parentId,
    required Map<String, dynamic> parentData,
    required String childId,
    required String childName,
    required DocumentReference childRef,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        final repNameCtrl = TextEditingController();
        final repRoleCtrl = TextEditingController();
        final qrBoundaryKey = GlobalKey();
        var reloadTick = 0;

        Future<Uint8List?> capturePng() async {
          final ctx = qrBoundaryKey.currentContext;
          if (ctx == null) return null;

          final renderObj = ctx.findRenderObject();
          final boundary = renderObj is RenderRepaintBoundary ? renderObj : null;
          if (boundary == null) return null;

          final image = await boundary.toImage(pixelRatio: 3.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          return byteData?.buffer.asUint8List();
        }

        String tokenFromQrData(String qrData) {
          final v = qrData.trim();
          if (v.startsWith('QR_') && v.length > 3) return v.substring(3);
          return '';
        }

        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<_QrInfo> loadQr() async {
              final snap = await FirebaseFirestore.instance.collection('parents').doc(parentId).get();
              return _resolveQr(
                parentId: parentId,
                parentData: (snap.data() ?? {}),
                desiredChildId: childId,
                desiredChildName: childName,
                desiredChildRef: childRef,
              );
            }

            return Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              padding: EdgeInsets.fromLTRB(24, 32, 24, MediaQuery.of(context).viewInsets.bottom + 32),
              child: FutureBuilder<_QrInfo>(
                key: ValueKey(reloadTick),
                future: loadQr(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                    return const SizedBox(
                      height: 280,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (snap.hasError) {
                    return SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 60,
                            height: 6,
                            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(3)),
                          ),
                          SizedBox(height: _s[4]),
                          Text('Shareable Pickup QR', style: _title.copyWith(fontSize: 22)),
                          SizedBox(height: _s[2]),
                          Text('Failed to load QR: ${snap.error}', style: _body, textAlign: TextAlign.center),
                          SizedBox(height: _s[4]),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.refresh),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              onPressed: () => setModalState(() => reloadTick++),
                              label: const Text('Retry'),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final info = snap.data;
                  final qrData = info?.data ?? '';
                  final isValid = info?.valid ?? false;
                  final expiresAt = info?.expiresAt;

                  final expiryLabel = expiresAt == null
                      ? (isValid ? 'Valid (short-lived)' : 'Expired')
                      : 'Valid until ${DateFormat('hh:mm a').format(expiresAt)}';

                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                      Container(
                        width: 60,
                        height: 6,
                        decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(3)),
                      ),
                      SizedBox(height: _s[4]),
                      Text('Shareable Pickup QR', style: _title.copyWith(fontSize: 22)),
                      SizedBox(height: _s[2]),
                      Text(
                        'You can share this QR with a relative (no account needed). It expires automatically.',
                        style: _body,
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: _s[4]),
                      RepaintBoundary(
                        key: qrBoundaryKey,
                        child: Card(
                          elevation: 12,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                          child: Padding(
                            padding: EdgeInsets.all(_s[5]),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  childName,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: Colors.black87,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 10),
                                qrData.isEmpty
                                    ? Icon(Icons.qr_code_2, size: 200, color: Colors.grey[400])
                                    : QrImageView(
                                        data: qrData,
                                        size: 240,
                                        backgroundColor: Colors.white,
                                        errorCorrectionLevel: QrErrorCorrectLevel.H,
                                      ),
                                const SizedBox(height: 10),
                                Text(
                                  expiryLabel,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                    color: isValid ? primary : Colors.red[700],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  (repNameCtrl.text.trim().isEmpty && repRoleCtrl.text.trim().isEmpty)
                                      ? 'Pickup details: (optional)'
                                      : 'Pickup by: ${repNameCtrl.text.trim().isEmpty ? '-' : repNameCtrl.text.trim()} (${repRoleCtrl.text.trim().isEmpty ? '-' : repRoleCtrl.text.trim()})',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: _s[3]),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isValid
                                ? [primary.withValues(alpha: 0.2), primary.withValues(alpha: 0.1)]
                                : [Colors.red.withValues(alpha: 0.2), Colors.red.withValues(alpha: 0.1)],
                          ),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: isValid ? primary : Colors.red, width: 1.5),
                        ),
                        child: Text(
                          expiryLabel,
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700,
                            color: isValid ? primary : Colors.red[700],
                            fontSize: 15,
                          ),
                        ),
                      ),
                      SizedBox(height: _s[4]),
                      TextField(
                        controller: repNameCtrl,
                        onChanged: (_) => setModalState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Pickup By (name) — optional',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      SizedBox(height: _s[2]),
                      TextField(
                        controller: repRoleCtrl,
                        onChanged: (_) => setModalState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Relationship (e.g. uncle, sister) — optional',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      SizedBox(height: _s[3]),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.refresh),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: () async {
                            try {
                              final parentSnap =
                                  await FirebaseFirestore.instance.collection('parents').doc(parentId).get();
                              final data = parentSnap.data() ?? {};

                              final newInfo = await _createPickupToken(
                                parentId: parentId,
                                parentData: data,
                                childId: childId,
                                childName: childName,
                                childRef: childRef,
                                representativeName: repNameCtrl.text,
                                representativeRole: repRoleCtrl.text,
                                ttlMinutes: 15,
                              );

                              setModalState(() => reloadTick++);

                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('New QR generated: ${newInfo.token}'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Failed to generate QR: $e'),
                                    duration: const Duration(seconds: 3),
                                  ),
                                );
                              }
                            }
                          },
                          label: const Text('Generate New QR (15 min)'),
                        ),
                      ),
                      SizedBox(height: _s[2]),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.ios_share),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              onPressed: qrData.isEmpty
                                  ? null
                                  : () async {
                                      try {
                                        // Best-effort: persist the optional fields for pickup logging.
                                        final token = tokenFromQrData(qrData);
                                        final parentRef = FirebaseFirestore.instance.collection('parents').doc(parentId);
                                        await parentRef.set(
                                          {
                                            'representativeName': repNameCtrl.text.trim(),
                                            'representativeRole': repRoleCtrl.text.trim(),
                                          },
                                          SetOptions(merge: true),
                                        );
                                        if (token.isNotEmpty) {
                                          await parentRef.collection('tokens').doc(token).set(
                                            {
                                              'representativeName': repNameCtrl.text.trim(),
                                              'representativeRole': repRoleCtrl.text.trim(),
                                            },
                                            SetOptions(merge: true),
                                          );
                                        }

                                        final bytes = await capturePng();
                                        if (bytes == null || bytes.isEmpty) {
                                          throw Exception('Unable to capture QR image');
                                        }

                                        final tmp = await getTemporaryDirectory();
                                        final file = File(
                                          '${tmp.path}/pickup_qr_${DateTime.now().millisecondsSinceEpoch}.png',
                                        );
                                        await file.writeAsBytes(bytes);

                                        final details = <String>[
                                          'Pickup QR for $childName',
                                          if (repNameCtrl.text.trim().isNotEmpty)
                                            'Pickup by: ${repNameCtrl.text.trim()}',
                                          if (repRoleCtrl.text.trim().isNotEmpty)
                                            'Relationship: ${repRoleCtrl.text.trim()}',
                                          expiryLabel,
                                        ].join('\n');

                                        await SharePlus.instance.share(
                                          ShareParams(
                                            files: [XFile(file.path)],
                                            text: details,
                                            subject: 'Taska Pickup QR',
                                          ),
                                        );
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Failed to share QR: $e'),
                                              duration: const Duration(seconds: 3),
                                            ),
                                          );
                                        }
                                      }
                                    },
                              label: const Text('Share'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.download),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              onPressed: qrData.isEmpty
                                  ? null
                                  : () async {
                                      try {
                                        final bytes = await capturePng();
                                        if (bytes == null || bytes.isEmpty) {
                                          throw Exception('Unable to capture QR image');
                                        }

                                        if (!Platform.isAndroid) {
                                          throw Exception('Download is supported on Android only. Use Share to save the image.');
                                        }

                                        final name = 'pickup_qr_${DateTime.now().millisecondsSinceEpoch}.png';
                                        final uri = await _qrGalleryChannel.invokeMethod<String>(
                                          'saveImage',
                                          <String, dynamic>{
                                            'bytes': bytes,
                                            'name': name,
                                          },
                                        );

                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(uri == null || uri.isEmpty ? 'Saved to gallery' : 'Saved to gallery: $uri'),
                                              duration: const Duration(seconds: 2),
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Failed to save QR: $e'),
                                              duration: const Duration(seconds: 3),
                                            ),
                                          );
                                        }
                                      }
                                    },
                              label: const Text('Download'),
                            ),
                          ),
                        ],
                      ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<_QrInfo> _resolveQr({
    required String parentId,
    required Map<String, dynamic> parentData,
    required String desiredChildId,
    required String desiredChildName,
    required DocumentReference desiredChildRef,
  }) async {
    final token = (parentData['dailyQrToken'] ?? '').toString().trim();
    if (token.isNotEmpty) {
      final tokenSnap = await FirebaseFirestore.instance
          .collection('parents')
          .doc(parentId)
          .collection('tokens')
          .doc(token)
          .get();
      if (tokenSnap.exists) {
        final data = tokenSnap.data() ?? {};
        final used = (data['used'] ?? false) == true;
        final expiredAtTs = data['expiredAt'] as Timestamp?;
        final expiredAt = expiredAtTs?.toDate();
        final expired = expiredAt != null && DateTime.now().isAfter(expiredAt);

        final tokenChildId = (data['childId'] ?? '').toString().trim();
        final bool childMatches = tokenChildId.isNotEmpty && tokenChildId == desiredChildId;

        if (!used && !expired && childMatches) {
          return _QrInfo(valid: true, data: 'QR_$token', expiresAt: expiredAt);
        }
      }
    }

    final created = await _createPickupToken(
      parentId: parentId,
      parentData: parentData,
      childId: desiredChildId,
      childName: desiredChildName,
      childRef: desiredChildRef,
      representativeName: (parentData['representativeName'] ?? '').toString(),
      representativeRole: (parentData['representativeRole'] ?? '').toString(),
      ttlMinutes: 15,
    );
    return _QrInfo(valid: true, data: 'QR_${created.token}', expiresAt: created.expiresAt);
  }

  Future<_TokenInfo> _createPickupToken({
    required String parentId,
    required Map<String, dynamic> parentData,
    required String childId,
    required String childName,
    required DocumentReference childRef,
    required String representativeName,
    required String representativeRole,
    required int ttlMinutes,
  }) async {
    final token = _randomToken(20);
    final expiresAt = DateTime.now().add(Duration(minutes: ttlMinutes));
    final resolvedChildId = childId.trim();
    final resolvedChildName = childName.trim();
    final resolvedChildRefPath = childRef.path.startsWith('/') ? childRef.path : '/${childRef.path}';

    final parentRef = FirebaseFirestore.instance.collection('parents').doc(parentId);
    final tokenRef = parentRef.collection('tokens').doc(token);

    // Update parent doc to point to the current active token
    await parentRef.set(
      {
        'dailyQrToken': token,
        // Keep legacy single-child fields in sync with the selected child
        'childId': resolvedChildId,
        'childName': resolvedChildName,
        'childRef': resolvedChildRefPath,
        'representativeName': representativeName.trim(),
        'representativeRole': representativeRole.trim(),
      },
      SetOptions(merge: true),
    );

    await tokenRef.set({
      'parentId': parentId,
      'childId': resolvedChildId,
      'childName': resolvedChildName,
      'childRef': resolvedChildRefPath,
      'used': false,
      'createdAt': FieldValue.serverTimestamp(),
      'expiredAt': Timestamp.fromDate(expiresAt),
      'representativeName': representativeName.trim(),
      'representativeRole': representativeRole.trim(),
    });

    return _TokenInfo(token: token, expiresAt: expiresAt);
  }

  String _randomToken(int length) {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(length, (_) => alphabet[rnd.nextInt(alphabet.length)]).join();
  }
}

class _QrInfo {
  final bool valid;
  final String data;
  final DateTime? expiresAt;

  const _QrInfo({required this.valid, required this.data, required this.expiresAt});
}

class _TokenInfo {
  final String token;
  final DateTime expiresAt;

  const _TokenInfo({required this.token, required this.expiresAt});
}

class _ChildChoice {
  final String childId;
  final String childName;
  final DocumentReference childRef;

  const _ChildChoice({
    required this.childId,
    required this.childName,
    required this.childRef,
  });
}
