import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AttendancePage extends StatelessWidget {
  final String childId;
  final String childName;

  const AttendancePage({
    super.key,
    required this.childId,
    required this.childName,
  });

  static const Color primary = Color(0xFF7ACB9E);
  static const Color secondary = Color(0xFFFFC107);
  static const Color accent = Color(0xFFF44336);
  static const Color backgroundLight = Color(0xFFF6F8F7);

  DateTime? _readTimestamp(Map<String, dynamic> data, List<String> keys) {
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

  String _readString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = (data[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _methodLabel(String value, {required bool isCheckout}) {
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

  String _sourceSummary(Map<String, dynamic> data) {
    final checkInMethod = _methodLabel(
      _readString(data, const ['checkInMethod', 'checkin_method']),
      isCheckout: false,
    );
    final checkOutMethod = _methodLabel(
      _readString(data, const ['checkOutMethod', 'checkout_method']),
      isCheckout: true,
    );
    final parts = <String>[];
    if (checkInMethod.isNotEmpty) {
      parts.add('Check-in via $checkInMethod');
    }
    if (checkOutMethod.isNotEmpty) {
      parts.add('Check-out via $checkOutMethod');
    }
    return parts.isEmpty ? 'Attendance source not recorded yet' : parts.join(' • ');
  }

  String _manualReason(Map<String, dynamic> data) {
    return _readString(data, const ['manualEditReason', 'reason']);
  }

  String _correctionActor(Map<String, dynamic> data) {
    final auditMetadata = data['auditMetadata'];
    if (auditMetadata is Map) {
      final lastActorName = (auditMetadata['lastActorName'] ?? '').toString().trim();
      if (lastActorName.isNotEmpty) return lastActorName;
    }
    return _readString(data, const ['checkedOutByName', 'checkedInByName']);
  }

  Widget _adminCorrectedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2BC55)),
      ),
      child: const Text(
        'Admin corrected',
        style: TextStyle(
          color: Color(0xFF7A5C00),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _auditActionLabel(String value) {
    switch (value.trim().toUpperCase()) {
      case 'NFC_CHECK_IN':
        return 'NFC check-in';
      case 'QR_CHECK_OUT':
        return 'Parent QR checkout';
      case 'MANUAL_CHECK_IN':
        return 'Manual check-in';
      case 'MANUAL_CHECK_OUT':
        return 'Manual check-out';
      case 'EDIT_RECORD':
        return 'Record edited';
      case 'REOPEN_RECORD':
        return 'Record reopened';
      case 'MARK_ABSENT':
        return 'Marked absent';
      default:
        return value.trim().isEmpty ? 'Unknown action' : value;
    }
  }

  String _formatAuditTimestamp(dynamic value) {
    final dt = _readTimestamp({'value': value}, const ['value']);
    if (dt == null) return '-';
    return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
  }

  String _formatAuditTimeRange(Map<String, dynamic> details) {
    final previousIn = _formatAuditTimestamp(details['previousCheckInAt']);
    final previousOut = _formatAuditTimestamp(details['previousCheckOutAt']);
    final nextIn = _formatAuditTimestamp(details['nextCheckInAt']);
    final nextOut = _formatAuditTimestamp(details['nextCheckOutAt']);
    return 'Before: in $previousIn, out $previousOut\nAfter: in $nextIn, out $nextOut';
  }

  void _openAuditDialog({
    required BuildContext context,
    required String attendanceId,
    required String dateLabel,
  }) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Audit History • $dateLabel'),
          content: SizedBox(
            width: 720,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('attendanceAudit')
                  .where('attendanceId', isEqualTo: attendanceId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text('Failed to load audit history.\n${snapshot.error}');
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 160,
                    child: Center(child: CircularProgressIndicator(color: primary)),
                  );
                }

                final docs = [...?snapshot.data?.docs];
                docs.sort((a, b) {
                  final left = _readTimestamp((a.data() as Map<String, dynamic>), const ['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
                  final right = _readTimestamp((b.data() as Map<String, dynamic>), const ['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
                  return right.compareTo(left);
                });

                if (docs.isEmpty) {
                  return const Text('No audit entries found for this attendance record.');
                }

                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final details = data['details'] is Map<String, dynamic>
                        ? data['details'] as Map<String, dynamic>
                        : <String, dynamic>{};
                    final actorName = (data['actorName'] ?? '').toString().trim();
                    final reason = (data['reason'] ?? '').toString().trim();
                    final method = (data['method'] ?? '').toString().trim();

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE0E0E0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _auditActionLabel((data['action'] ?? '').toString()),
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                                ),
                              ),
                              Text(
                                _formatAuditTimestamp(data['createdAt']),
                                style: const TextStyle(color: Colors.black54, fontSize: 12),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('Updated by: ${actorName.isEmpty ? '-' : actorName}', style: const TextStyle(fontSize: 13)),
                          Text('Method: ${method.isEmpty ? '-' : method}', style: const TextStyle(fontSize: 13)),
                          Text('Reason: ${reason.isEmpty ? '-' : reason}', style: const TextStyle(fontSize: 13)),
                          const SizedBox(height: 6),
                          Text(
                            _formatAuditTimeRange(details),
                            style: const TextStyle(fontSize: 12, color: Colors.black87),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundLight,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            _buildHeader(context),
            const SizedBox(height: 8),

            // === TODAY ATTENDANCE ===
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('attendance')
                  .where('childId', isEqualTo: childId.trim())
                  .orderBy('check_in_time', descending: true)
                  .limit(1)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: primary),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Firestore Error: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _buildNoRecordCard();
                }

                final data =
                    snapshot.data!.docs.first.data() as Map<String, dynamic>;
                return _buildAttendanceCard(context, data);
              },
            ),

            const SizedBox(height: 16),
            _buildMonthlySummary(childId),
            const SizedBox(height: 16),
            _buildStatCards(childId),
            const SizedBox(height: 16),
            _buildTeacherNote(),
            const SizedBox(height: 18),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      '/attendance_history',
                      arguments: {
                        'childId': childId,
                        'childName': childName,
                      },
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 8,
                    shadowColor: primary.withValues(alpha: 0.3),
                  ),
                  child: const Text(
                    'View History',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ==================== HEADER ====================
  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Color(0xFF111714)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "$childName's Attendance",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111714),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== NO RECORD ====================
  Widget _buildNoRecordCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.05),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            const Icon(Icons.event_busy, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              "Tiada rekod check-in hari ini",
              style: TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ==================== ATTENDANCE CARD ====================
  Widget _buildAttendanceCard(BuildContext context, Map<String, dynamic> data) {
    final checkInTime = _readTimestamp(
      data,
      const ['checkInAt', 'check_in_time', 'checkInTime', 'check_in'],
    );
    final checkOutTime = _readTimestamp(
      data,
      const ['checkOutAt', 'check_out_time', 'checkOutTime', 'check_out'],
    );
    final teacher = data['teacher'] ?? 'Unknown Teacher';
    final sourceSummary = _sourceSummary(data);
    final manualReason = _manualReason(data);
    final correctionActor = _correctionActor(data);
    final attendanceId = _readString(data, const ['attendanceId']);
    final isAdminCorrected = manualReason.isNotEmpty || sourceSummary.toLowerCase().contains('admin manual');

    if (checkInTime == null) return _buildNoRecordCard();

    final formattedDate = DateFormat('MMMM dd, yyyy').format(checkInTime);
    final formattedCheckIn = DateFormat('hh:mm a').format(checkInTime);
    final formattedCheckOut =
        checkOutTime != null ? DateFormat('hh:mm a').format(checkOutTime) : '-';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(formattedDate,
                style: const TextStyle(fontSize: 14, color: Color(0xFF111714))),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, 0.05),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  checkOutTime != null
                      ? 'Checked Out'
                      : 'Checked In',
                  style: const TextStyle(
                    color: primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                if (isAdminCorrected) ...[
                  const SizedBox(height: 8),
                  _adminCorrectedBadge(),
                ],
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formattedCheckIn,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF111714),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            checkOutTime != null
                                ? 'Check-Out: $formattedCheckOut'
                                : 'Not checked out yet',
                            style: const TextStyle(
                              color: Color(0xFF648772),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            sourceSummary,
                            style: const TextStyle(
                              color: Color(0xFF456556),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (manualReason.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Manual update reason: $manualReason',
                              style: const TextStyle(
                                color: Color(0xFF7A5C00),
                                fontSize: 12,
                              ),
                            ),
                          ],
                          if (isAdminCorrected && correctionActor.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Updated by: $correctionActor',
                              style: const TextStyle(
                                color: Color(0xFF7A5C00),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          if (isAdminCorrected && attendanceId.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: () => _openAuditDialog(
                                context: context,
                                attendanceId: attendanceId,
                                dateLabel: formattedDate,
                              ),
                              child: const Text('View audit history'),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            teacher,
                            style: const TextStyle(
                              color: Color(0xFF648772),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== MONTHLY SUMMARY ====================
  Widget _buildMonthlySummary(String childId) {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('attendance')
            .where('childId', isEqualTo: childId)
            .where('check_in_time',
                isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
            .where('check_in_time',
                isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const LinearProgressIndicator();
          }

          final docs = snapshot.data!.docs;
          int present = 0, absent = 0, late = 0;

          for (var doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            final isPresent = data['isPresent'] ?? false;
            final ts = data['check_in_time'] as Timestamp?;
            if (isPresent == true && ts != null) {
              final t = ts.toDate();
              if (t.hour > 8 || (t.hour == 8 && t.minute > 0)) {
                late++;
              } else {
                present++;
              }
            } else if (isPresent == false) {
              absent++;
            }
          }

          final total = present + absent + late;
          final rate = total > 0 ? (present / total) : 0.0;

          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, 0.05),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                )
              ],
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Monthly Attendance",
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _statTile("Present", present.toString(), primary),
                    const SizedBox(width: 8),
                    _statTile("Absent", absent.toString(), accent),
                    const SizedBox(width: 8),
                    _statTile("Late", late.toString(), secondary),
                  ],
                ),
                const SizedBox(height: 14),
                Text("Attendance Rate: ${(rate * 100).toStringAsFixed(1)}%",
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: rate,
                  minHeight: 8,
                  color: primary,
                  backgroundColor: const Color(0xFFE8F3EE),
                  borderRadius: BorderRadius.circular(20),
                ),
                const SizedBox(height: 6),
                Text("$present/$total days",
                    style: const TextStyle(color: Color(0xFF648772))),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _statTile(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(value,
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }

  // ==================== STAT CARDS ====================
  Widget _buildStatCards(String childId) {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('attendance')
            .where('childId', isEqualTo: childId)
            .where('check_in_time',
                isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
            .where('check_in_time',
                isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Row(
              children: [
                _StatCardPlaceholder(),
                SizedBox(width: 8),
                _StatCardPlaceholder(),
                SizedBox(width: 8),
                _StatCardPlaceholder(),
              ],
            );
          }

          final docs = snapshot.data!.docs;
          final present =
              docs.where((d) => (d.data() as Map)['isPresent'] == true).length;
          final absent =
              docs.where((d) => (d.data() as Map)['isPresent'] == false).length;
          final late = docs.where((d) {
            final ts = (d.data() as Map)['check_in_time'] as Timestamp?;
            if (ts == null) return false;
            final t = ts.toDate();
            return t.hour > 8 || (t.hour == 8 && t.minute > 0);
          }).length;

          return Row(
            children: [
              _statCard(present.toString(), 'Present'),
              const SizedBox(width: 8),
              _statCard(absent.toString(), 'Absent'),
              const SizedBox(width: 8),
              _statCard(late.toString(), 'Late'),
            ],
          );
        },
      ),
    );
  }

  Widget _statCard(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.05),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111714),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF648772),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== TEACHER NOTE ====================
  Widget _buildTeacherNote() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.05),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Teacher's Note",
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              '"$childName had a fantastic day! He was very engaged during story time and shared his toys with friends. Great job!"',
              style: const TextStyle(color: Color(0xFF648772), height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== PLACEHOLDER ====================
class _StatCardPlaceholder extends StatelessWidget {
  const _StatCardPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(height: 6),
            SizedBox(width: 40, height: 12, child: LinearProgressIndicator()),
          ],
        ),
      ),
    );
  }
}
