import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:parent_app_taskazurah/screens/attendance_dashboard.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:parent_app_taskazurah/screens/parent_profile_page.dart';
import 'package:parent_app_taskazurah/screens/chat_list_page.dart';
import 'package:intl/intl.dart';


class TaskaZurahDashboard extends StatelessWidget {
  const TaskaZurahDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final args =
    ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
    final parentId = args['parentId'] as String;
    final parentName = args['parentName'] as String;

    return DashboardPage(parentId: parentId, parentName: parentName);
  }
}

// ✅ Model QR info
class _QrInfo {
  final String data;
  final bool valid;
  const _QrInfo(this.data, this.valid);
}

// ✅ QR Logic function (KEPT 100% ORIGINAL)
Future<_QrInfo> _resolveQr(
    String parentId, Map<String, dynamic> parentData) async {
  String? tokenValue = parentData['dailyQrToken'];
  final now = DateTime.now();

  if (tokenValue != null && tokenValue.isNotEmpty) {
    final tokenRef = FirebaseFirestore.instance
        .collection('parents')
        .doc(parentId)
        .collection('tokens')
        .doc(tokenValue);

    final snap = await tokenRef.get();
    if (snap.exists) {
      final data = snap.data()!;
      final bool used = data['used'] ?? false;
      final DateTime? expiredAt = (data['expiredAt'] as Timestamp?)?.toDate();

      if (!used && expiredAt != null && now.isBefore(expiredAt)) {
        return _QrInfo("QR_$tokenValue", true);
      }
    }
  }

  // Generate new token
  final newToken = DateTime.now().millisecondsSinceEpoch.toString();
  final expiry = DateTime(now.year, now.month, now.day, 23, 59, 59);

  final parentDoc =
  FirebaseFirestore.instance.collection('parents').doc(parentId);
  await parentDoc.collection('tokens').doc(newToken).set({
    'tokenId': newToken,
    'tokenOwnerRef': parentDoc,
    'createdAt': Timestamp.now(),
    'expiredAt': Timestamp.fromDate(expiry),
    'used': false,
    'usedAt': null,
  });

  await parentDoc.update({'dailyQrToken': newToken});

  return _QrInfo("QR_$newToken", true);
}

class DashboardPage extends StatelessWidget {
  final String parentId;
  final String parentName;

  const DashboardPage({
    super.key,
    required this.parentId,
    required this.parentName,
  });

  // 🎨 TEMA GEMPAK LEVEL PERTANDINGAN
  static const Color primary = Color(0xFF7ACB9E);
  static const Color background = Color(0xFFF6F8F7);
  static const Color cardBg = Colors.white;
  static const Color shadowColor = Color(0x0D000000);
  static const double _radius = 24.0;
  static const double _elevation = 8.0;
  static const EdgeInsets _padding =
  EdgeInsets.symmetric(horizontal: 20, vertical: 16);
  static const List<double> _s = [4, 8, 12, 16, 20, 24, 32, 40];

  // Typography Plus Jakarta Sans — SEMUA
  TextStyle get _greeting => GoogleFonts.plusJakartaSans(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    color: Colors.black87,
    height: 1.2,
  );
  TextStyle get _title => GoogleFonts.plusJakartaSans(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: Colors.black87,
  );
  TextStyle get _subtitle => GoogleFonts.plusJakartaSans(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: primary,
  );
  TextStyle get _body => GoogleFonts.plusJakartaSans(
    fontSize: 15,
    color: Colors.grey[700],
  );
  TextStyle get _caption => GoogleFonts.plusJakartaSans(
    fontSize: 13,
    color: Colors.grey[600],
  );

  // ✨ Avatar gempak
  Widget _avatar(String? url, {double size = 64}) {
    final Widget child = url == null || url.isEmpty
        ? Icon(Icons.child_care, size: size * 0.5, color: Colors.white)
        : ClipOval(
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.child_care, size: size * 0.5, color: Colors.white),
      ),
    );

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primary, Color(0xFF5AB68A)],
        ),
        boxShadow: [
          BoxShadow(
            color: primary.withOpacity(0.4),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: Container(
        decoration: const BoxDecoration(shape: BoxShape.circle, color: cardBg),
        padding: const EdgeInsets.all(4),
        child: child,
      ),
    );
  }

  String _formatTime(DateTime time) {
    final h = time.hour > 12 ? time.hour - 12 : time.hour;
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '${h.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} $period';
  }

  void _stub(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('// TODO: $msg', style: GoogleFonts.plusJakartaSans()),
        backgroundColor: primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future:
      FirebaseFirestore.instance.collection('parents').doc(parentId).get(),
      builder: (context, parentSnapshot) {
        if (!parentSnapshot.hasData) {
          return Scaffold(
            backgroundColor: background,
            body: Center(
              child: CircularProgressIndicator(
                color: primary,
                strokeWidth: 5,
              ),
            ),
          );
        }

        final parentData = parentSnapshot.data!.data() as Map<String, dynamic>;
        final dynamic rawChildRef = parentData['childRef'];

        DocumentReference? childRef;
        if (rawChildRef is DocumentReference) {
          childRef = rawChildRef;
        } else if (rawChildRef is String) {
          final path = rawChildRef.trim();
          if (path.contains('children/')) {
            final cleanPath = path.startsWith('/') ? path.substring(1) : path;
            childRef = FirebaseFirestore.instance.doc(cleanPath);
          }
        }

        if (childRef == null) {
          return Scaffold(
            backgroundColor: background,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.sentiment_dissatisfied,
                      size: 80, color: Colors.grey[400]),
                  SizedBox(height: _s[4]),
                  Text('Tiada anak berdaftar',
                      style: _title.copyWith(color: Colors.grey[600])),
                  SizedBox(height: _s[2]),
                  Text('Sila hubungi pengurusan taska', style: _caption),
                ],
              ),
            ),
          );
        }

        return FutureBuilder<DocumentSnapshot>(
          future: childRef.get(),
          builder: (context, childSnapshot) {
            if (!childSnapshot.hasData || !childSnapshot.data!.exists) {
              return Scaffold(
                backgroundColor: background,
                body: Center(child: CircularProgressIndicator(color: primary)),
              );
            }

            final childData =
            childSnapshot.data!.data() as Map<String, dynamic>;
            final String childId = childSnapshot.data!.id;
            final String childName = childData['name'] ?? 'Anak';
            final String className = childData['className'] ?? 'Kelas';
            final String teacherName = childData['teacherName'] ?? 'Cikgu';
            String photoUrl =
            (childData['photoUrl'] ?? childData['imageUrl'] ?? '')
                .toString()
                .trim();
            if (photoUrl.isEmpty || !photoUrl.startsWith('http')) {
              photoUrl =
              'https://ui-avatars.com/api/?name=${Uri.encodeComponent(childName)}&size=300&background=7ACB9E&color=fff&bold=true';
            }

            return FutureBuilder<_QrInfo>(
              future: _resolveQr(parentId, parentData),
              builder: (context, qrSnap) {
                if (!qrSnap.hasData) {
                  return Scaffold(
                    backgroundColor: background,
                    body: Center(
                        child: CircularProgressIndicator(color: primary)),
                  );
                }
                final qrInfo = qrSnap.data!;

                return Scaffold(
                  backgroundColor: background,
                  body: CustomScrollView(
                    slivers: [
                      SliverAppBar(
                        backgroundColor: background,
                        elevation: 0,
                        floating: true,
                        flexibleSpace: FlexibleSpaceBar(
                          background: Container(color: background),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: _padding,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 🔥 GEMPAK HEADER
                              Row(
                                children: [
                                  Expanded(
                                    child: RichText(
                                      text: TextSpan(
                                        children: [
                                          TextSpan(
                                              text: 'Good morning,\n',
                                              style: _greeting.copyWith(
                                                  fontSize: 24)),
                                          TextSpan(
                                              text: parentName,
                                              style: _greeting.copyWith(
                                                  color: primary)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => Navigator.push(
                                      context,
                                      PageRouteBuilder(
                                        pageBuilder: (_, __, ___) =>
                                            ParentProfilePage(
                                                parentId: parentId),
                                        transitionDuration:
                                        const Duration(milliseconds: 400),
                                        transitionsBuilder: (_, a, __, c) =>
                                            FadeTransition(
                                                opacity: a, child: c),
                                      ),
                                    ),
                                    child: _avatar(photoUrl, size: 72),
                                  ),
                                ],
                              ),
                              SizedBox(height: _s[5]),

                              // 🌟 CHILD HERO CARD
                              Card(
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                    BorderRadius.circular(_radius)),
                                elevation: _elevation,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius:
                                    BorderRadius.circular(_radius),
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        cardBg,
                                        primary.withOpacity(0.03)
                                      ],
                                    ),
                                  ),
                                  padding: EdgeInsets.all(_s[4]),
                                  child: Row(
                                    children: [
                                      Hero(
                                        tag: 'child_avatar_$childId',
                                        child: _avatar(photoUrl, size: 80),
                                      ),
                                      SizedBox(width: _s[4]),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                          children: [
                                            Text(childName,
                                                style: _title.copyWith(
                                                    fontSize: 22)),
                                            SizedBox(height: _s[0]),
                                            Row(
                                              children: [
                                                Icon(Icons.class_,
                                                    size: 16, color: primary),
                                                SizedBox(width: 4),
                                                Text(className, style: _body),
                                                SizedBox(width: _s[3]),
                                                Icon(Icons.person,
                                                    size: 16, color: primary),
                                                SizedBox(width: 4),
                                                Text(teacherName, style: _body),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(height: _s[5]),

                              // 🚀 LIVE ATTENDANCE — FIXED OVERFLOW & PERFECT ALIGNMENT
                              Card(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(_radius),
                                ),
                                elevation: _elevation,
                                child: Container(
                                  padding: EdgeInsets.all(_s[4]),
                                  decoration: BoxDecoration(
                                    borderRadius:
                                    BorderRadius.circular(_radius),
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        const Color.fromARGB(255, 241, 255, 247).withOpacity(0.05),
                                        cardBg
                                      ],
                                    ),
                                  ),
                                  child: StreamBuilder<QuerySnapshot>(
                                    stream: FirebaseFirestore.instance
                                        .collection('attendance')
                                        .where('childId', isEqualTo: childId)
                                        .orderBy('check_in_time',
                                        descending: true)
                                        .limit(1)
                                        .snapshots(),
                                    builder: (context, snapshot) {
                                      // Default UI state
                                      String statusText = 'Belum check-in';
                                      String subtitleText = 'Tiada rekod';
                                      Color statusColor = Colors.orange;
                                      IconData statusIcon = Icons.access_time;
                                      bool glow = false;

                                      if (snapshot.hasData &&
                                          snapshot.data!.docs.isNotEmpty) {
                                        final data = snapshot.data!.docs.first
                                            .data() as Map<String, dynamic>;
                                        final isPresent =
                                            data['isPresent'] ?? false;
                                        final checkInRaw =
                                        data['check_in_time'];
                                        DateTime? checkInTime;

                                        if (checkInRaw is Timestamp) {
                                          checkInTime = checkInRaw
                                              .toDate()
                                              .add(const Duration(hours: 8));
                                        } else if (checkInRaw is String) {
                                          checkInTime = DateTime.tryParse(
                                              checkInRaw)
                                              ?.add(const Duration(hours: 8));
                                        }

                                        if (isPresent == true) {
                                          statusText = 'Checked In';
                                          statusIcon = Icons.check_circle;
                                          statusColor = const Color.fromARGB(255, 111, 177, 140);
                                          glow = true;
                                          subtitleText = checkInTime != null
                                              ? 'Jam ${DateFormat('hh:mm a').format(checkInTime)}'
                                              : '-';
                                        } else {
                                          statusText = 'Absent';
                                          statusIcon = Icons.cancel;
                                          statusColor = Colors.red;
                                          subtitleText = 'Tidak hadir hari ini';
                                        }
                                      }

                                      return Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        children: [
                                          // === Title & View History ===
                                          Row(
                                            mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                'Live Attendance Status',
                                                style: _title,
                                              ),
                                              GestureDetector(
                                                onTap: () {
                                                  Navigator.pushNamed(
                                                    context,
                                                    '/attendance_history',
                                                    arguments: {
                                                      'childId': childId,
                                                      'childName': childName,
                                                      'className': className,
                                                    },
                                                  );
                                                },
                                                child: Text(
                                                  'View History',
                                                  style: _subtitle.copyWith(
                                                      fontSize: 14),
                                                ),
                                              ),
                                            ],
                                          ),
                                          SizedBox(height: _s[2]),

                                          // === Status Card (tap untuk buka AttendancePage) ===
                                          GestureDetector(
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      AttendancePage(
                                                        childId: childId,
                                                        childName: childName,
                                                        className: className,
                                                      ),
                                                ),
                                              );
                                            },
                                            child: Container(
                                              padding: EdgeInsets.all(_s[3]),
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                BorderRadius.circular(
                                                    _radius),
                                                color: statusColor
                                                    .withOpacity(0.08),
                                                border: Border.all(
                                                    color: statusColor
                                                        .withOpacity(0.4)),
                                                boxShadow: glow
                                                    ? [
                                                  BoxShadow(
                                                    color: statusColor
                                                        .withOpacity(
                                                        0.35),
                                                    blurRadius: 20,
                                                    spreadRadius: 1,
                                                  )
                                                ]
                                                    : [],
                                              ),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    padding:
                                                    EdgeInsets.all(_s[2]),
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: statusColor
                                                          .withOpacity(0.15),
                                                    ),
                                                    child: Icon(
                                                      statusIcon,
                                                      color: statusColor,
                                                      size: 30,
                                                    ),
                                                  ),
                                                  SizedBox(width: _s[3]),
                                                  Column(
                                                    crossAxisAlignment:
                                                    CrossAxisAlignment
                                                        .start,
                                                    children: [
                                                      Text(
                                                        statusText,
                                                        style:
                                                        _subtitle.copyWith(
                                                            color:
                                                            statusColor),
                                                      ),
                                                      Text(
                                                        subtitleText,
                                                        style: _caption,
                                                      ),
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

                              // ⚡ QUICK ACCESS — 3D GRID (FIXED OVERFLOW)
                              Text('Quick Access', style: _title),
                              SizedBox(height: _s[3]),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final double tileWidth =
                                      (constraints.maxWidth - _s[3] * 2) /
                                          3; // Hitung width dinamik
                                  return GridView.builder(
                                    gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 3,
                                      crossAxisSpacing: _s[3],
                                      mainAxisSpacing: _s[3],
                                      childAspectRatio: tileWidth /
                                          (tileWidth +
                                              20), // Auto adjust height, no overflow!
                                    ),
                                    itemCount: 6,
                                    shrinkWrap: true,
                                    physics:
                                    const NeverScrollableScrollPhysics(),
                                    itemBuilder: (context, index) {
                                      final tiles = [
                                        _quickTile(
                                            Icons.receipt_long,
                                            'Invoices',
                                                () => Navigator.pushNamed(
                                                context, '/fees_dashboard')),
                                        _quickTile(
                                            Icons.event_available, 'Attendance',
                                                () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => AttendancePage(
                                                      childId: childId,
                                                      childName: childName,
                                                      className: className),
                                                ),
                                              );
                                            }),
                                        _quickTile(
                                            Icons.photo_library,
                                            'Memory\nJourney',
                                                () => Navigator.pushNamed(context,
                                                '/memory_journey')), // \n untuk wrap
                                        _quickTile(
                                            Icons.school,
                                            'Teacher\nInfo',
                                                () => Navigator.pushNamed(
                                                context, '/teacher_list')),
                                        _quickTile(
                                            Icons.qr_code_2,
                                            'Pickup',
                                                () => _showQrModal(context,
                                                qrInfo.data, qrInfo.valid)),
                                        _quickTile(Icons.person, 'Profile', () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                                builder: (_) =>
                                                    ParentProfilePage(
                                                        parentId: parentId)),
                                          );
                                        }),
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
                      // ✅ Direct buka ChatListPage (inbox view)
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatListPage(
                            parentUsername: parentName.toLowerCase(),
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  floatingActionButtonLocation:
                  FloatingActionButtonLocation.centerFloat,
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _attendanceRow({
    required IconData icon,
    required String status,
    required String subtitle,
    required Color color,
    required bool glow,
  }) {
    return Container(
      padding: EdgeInsets.all(_s[3]),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: glow
            ? [
          BoxShadow(
            color: color.withOpacity(0.4),
            blurRadius: 20,
            spreadRadius: 2,
          )
        ]
            : null,
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(_s[2]),
            decoration: BoxDecoration(
                color: color.withOpacity(0.2), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 32),
          ),
          SizedBox(width: _s[3]),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(status, style: _subtitle.copyWith(color: color)),
                Text(subtitle, style: _caption),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickTile(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radius)),
        elevation: 12,
        shadowColor: shadowColor,
        child: Container(
          padding: EdgeInsets.all(_s[2]), // Kurang padding sikit
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_radius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cardBg, primary.withOpacity(0.08)],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(_s[2]),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [primary, Color(0xFF5AB68A)]),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: primary.withOpacity(0.5),
                        blurRadius: 12,
                        offset: const Offset(0, 6)),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 32),
              ),
              SizedBox(height: _s[1]),
              Text(
                label,
                style: _body.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 12), // Font kecil sikit
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

  void _showQrModal(BuildContext context, String qrData, bool isValid) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 30,
                offset: const Offset(0, 10)),
          ],
        ),
        padding: EdgeInsets.fromLTRB(
            24, 32, 24, MediaQuery.of(context).viewInsets.bottom + 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 60,
                height: 6,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(3))),
            SizedBox(height: _s[4]),
            Text('Parent Pickup QR Code', style: _title.copyWith(fontSize: 22)),
            SizedBox(height: _s[5]),
            Card(
              elevation: 12,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(32)),
              child: Padding(
                padding: EdgeInsets.all(_s[5]),
                child: qrData.isEmpty
                    ? Icon(Icons.qr_code_2, size: 200, color: Colors.grey[400])
                    : QrImageView(
                  data: qrData,
                  size: 280,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.H,
                ),
              ),
            ),
            SizedBox(height: _s[4]),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isValid
                      ? [primary.withOpacity(0.2), primary.withOpacity(0.1)]
                      : [
                    Colors.red.withOpacity(0.2),
                    Colors.red.withOpacity(0.1)
                  ],
                ),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                    color: isValid ? primary : Colors.red, width: 1.5),
              ),
              child: Text(
                isValid
                    ? 'Valid for today only'
                    : 'QR Expired — Renews at 12:00 AM',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  color: isValid ? primary : Colors.red[700],
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}