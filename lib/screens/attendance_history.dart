import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AttendanceHistoryPage extends StatefulWidget {
  final String childId;
  final String childName;

  const AttendanceHistoryPage({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  State<AttendanceHistoryPage> createState() => _AttendanceHistoryPageState();
}

class _AttendanceHistoryPageState extends State<AttendanceHistoryPage> {
  String _selectedRecordFilter = 'All';

  static const Color primary = Color(0xFF7ACB9E);
  static const Color secondary = Color(0xFFFFC107);
  static const Color accent = Color(0xFFF44336);
  static const Color backgroundLight = Color(0xFFF8FBFA);

  String normalize(String s) =>
      s.replaceAll(RegExp(r'[\s\n\r\t]'), '').trim();

  bool _isAdminCorrected(Map<String, dynamic> data) {
    final sourceSummary = _sourceSummary(data);
    return _manualReason(data).isNotEmpty || sourceSummary.toLowerCase().contains('admin manual');
  }

  List<QueryDocumentSnapshot> _applyRecordFilter(List<QueryDocumentSnapshot> docs) {
    if (_selectedRecordFilter == 'Corrected Only') {
      return docs.where((doc) => _isAdminCorrected(doc.data() as Map<String, dynamic>)).toList();
    }
    return docs;
  }

  DateTime? _parseDateFromDocId(String docId) {
    // Common pattern in this project: YYYY-MM-DD_<childId>
    final m = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(docId);
    if (m == null) return null;
    return DateTime.tryParse(m.group(1)!);
  }

  DateTime _bestRecordDate(Map<String, dynamic> data, {String? docId}) {
    final checkIn = _readTimestamp(
      data,
      const ['checkInAt', 'check_in_time', 'checkInTime', 'check_in'],
    );
    if (checkIn != null) return checkIn;

    final rawDate = data['date'];
    if (rawDate is Timestamp) return rawDate.toDate();
    if (rawDate is DateTime) return rawDate;
    if (rawDate is String) {
      // Support ISO-8601 and YYYY-MM-DD. (Exports may include non-ISO strings.)
      final dt = DateTime.tryParse(rawDate);
      if (dt != null) return dt;
      final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(rawDate);
      if (m != null) {
        return DateTime(
          int.parse(m.group(1)!),
          int.parse(m.group(2)!),
          int.parse(m.group(3)!),
        );
      }
    }

    final fromId = docId != null ? _parseDateFromDocId(docId) : null;
    return fromId ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

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
    final inMethod = _methodLabel(
      _readString(data, const ['checkInMethod', 'checkin_method']),
      isCheckout: false,
    );
    final outMethod = _methodLabel(
      _readString(data, const ['checkOutMethod', 'checkout_method']),
      isCheckout: true,
    );
    final parts = <String>[];
    if (inMethod.isNotEmpty) parts.add('In: $inMethod');
    if (outMethod.isNotEmpty) parts.add('Out: $outMethod');
    return parts.isEmpty ? 'Source: not recorded' : parts.join(' • ');
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
    final normalizedChildId = normalize(widget.childId);
    final childRef = FirebaseFirestore.instance.collection('children').doc(normalizedChildId);
    final normalizedChildRef = '/children/$normalizedChildId';
    return Scaffold(
      backgroundColor: backgroundLight,
      appBar: AppBar(
        backgroundColor: backgroundLight,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "Attendance History",
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),

      // ✅ Hybrid Query (childRef first, fallback to childId)
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('attendance')
            // IMPORTANT: Parents cannot read the whole attendance collection.
            // Query only records for this child to satisfy Firestore rules.
            .where('childId', isEqualTo: normalizedChildId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: primary));
          }

          if (snapshot.hasError) {
            final msg = snapshot.error.toString();
            final lower = msg.toLowerCase();
            final isPermission = lower.contains('permission') || lower.contains('permission-denied');
            final isIndex = lower.contains('failed-precondition') || lower.contains('index');
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  isPermission
                      ? 'Permission denied to read attendance records.'
                      : isIndex
                          ? 'Query requires an index. Contact admin to create the Firestore index.'
                          : 'Error loading attendance history: $msg',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No attendance records found"));
          }

          // Most records should already match by childId due to the query.
          // Keep a small fallback check for legacy records that stored a childRef.
          final docs = snapshot.data!.docs;
          final normalizedDocs = docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            final id = normalize((data['childId'] ?? '').toString());
            if (id == normalizedChildId) return true;

            final rawRef = data['childRef'];
            if (rawRef is DocumentReference) return rawRef.path == childRef.path;
            final refStr = normalize((rawRef ?? '').toString());
            return refStr == normalizedChildRef;
          }).toList()
            ..sort((a, b) {
              final aData = a.data() as Map<String, dynamic>;
              final bData = b.data() as Map<String, dynamic>;
              final aTime = _bestRecordDate(aData, docId: a.id);
              final bTime = _bestRecordDate(bData, docId: b.id);
              return bTime.compareTo(aTime);
            });

          if (normalizedDocs.isEmpty) {
            return const Center(child: Text("No attendance found for this child"));
          }

          // === Summary counters ===
          int present = 0, absent = 0, late = 0;
          List<DateTime> checkinTimes = [];

          for (var doc in normalizedDocs) {
            final data = doc.data() as Map<String, dynamic>;
            final ts = _readTimestamp(
              data,
              const ['checkInAt', 'check_in_time', 'checkInTime', 'check_in'],
            );
            final outTs = _readTimestamp(
              data,
              const ['checkOutAt', 'check_out_time', 'checkOutTime', 'check_out'],
            );
            final presentFlag = ts != null || outTs != null || data['status'] == 'CHECKED_OUT';

            if (presentFlag == true) present++;
            if (presentFlag == false) absent++;
            if (ts != null) {
              final t = ts;
              checkinTimes.add(t);
              if (t.hour > 8 || (t.hour == 8 && t.minute > 0)) late++;
            }
          }

          final total = present + absent;
          final rate = total > 0 ? (present / total) : 0.0;

          // === Average check-in time ===
          String avgCheckIn = "-";
          if (checkinTimes.isNotEmpty) {
            final avg = checkinTimes
                    .map((t) => t.hour * 60 + t.minute)
                    .reduce((a, b) => a + b) /
                checkinTimes.length;
            final avgHour = (avg ~/ 60);
            final avgMin = (avg % 60).round();
            avgCheckIn = DateFormat('hh:mm a')
                .format(DateTime(0, 1, 1, avgHour, avgMin));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                widget.childName,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              _buildMonthlySummary(present, absent, late, rate),
              const SizedBox(height: 16),
              const Text("Daily Records",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: DropdownButton<String>(
                  value: _selectedRecordFilter,
                  items: const [
                    DropdownMenuItem(value: 'All', child: Text('All Records')),
                    DropdownMenuItem(value: 'Corrected Only', child: Text('Corrected Only')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectedRecordFilter = value);
                  },
                ),
              ),
              const SizedBox(height: 8),
              for (var doc in _applyRecordFilter(normalizedDocs)) ...[
                _recordCardFromFirestore(context, doc),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 16),
              const Text("Insights",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _insightCard(avgCheckIn, present),
            ],
          );
        },
      ),
    );
  }

  // ==================== SUMMARY ====================
  Widget _buildMonthlySummary(int present, int absent, int late, double rate) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.05),
              blurRadius: 6,
              offset: Offset(0, 2))
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Monthly Summary",
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
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
        ],
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

  // ==================== RECORD CARD ====================
  Widget _recordCardFromFirestore(BuildContext context, QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final checkInTs = _readTimestamp(
      data,
      const ['checkInAt', 'check_in_time', 'checkInTime', 'check_in'],
    );
    final checkOutTs = _readTimestamp(
      data,
      const ['checkOutAt', 'check_out_time', 'checkOutTime', 'check_out'],
    );
    final sourceSummary = _sourceSummary(data);
    final manualReason = _manualReason(data);
    final correctionActor = _correctionActor(data);

    final checkIn = checkInTs != null
        ? DateFormat('hh:mm a').format(checkInTs)
        : "-";
    final checkOut = checkOutTs != null
        ? DateFormat('hh:mm a').format(checkOutTs)
        : "-";

    final dateTime = _bestRecordDate(data, docId: doc.id);
    final date = DateFormat('EEE, dd MMM yyyy').format(dateTime);

    String status = "absent";
    if (checkOutTs != null) {
      status = "checked_out";
    } else if (checkInTs != null) {
      final t = checkInTs;
      if (t.hour > 8 || (t.hour == 8 && t.minute > 0)) {
        status = "late";
      } else {
        status = "present";
      }
    }

    String subtitle = checkInTs != null
        ? "Check-in: $checkIn   Check-out: $checkOut"
        : "Not checked in";

    subtitle = '$subtitle\n$sourceSummary';
    if (manualReason.isNotEmpty) {
      subtitle = '$subtitle\nManual reason: $manualReason';
    }
    if (correctionActor.isNotEmpty && (manualReason.isNotEmpty || sourceSummary.toLowerCase().contains('admin manual'))) {
      subtitle = '$subtitle\nUpdated by: $correctionActor';
    }

    return _recordCard(
      context,
      date,
      subtitle,
      status,
      attendanceId: doc.id,
      isAdminCorrected: _isAdminCorrected(data),
    );
  }

  Widget _recordCard(BuildContext context, String date, String subtitle, String status, {required String attendanceId, bool isAdminCorrected = false}) {
    Color bg;
    Color text;
    IconData icon;
    String label;

    switch (status) {
      case 'checked_out':
        bg = primary.withValues(alpha: 0.18);
        text = primary;
        icon = Icons.logout_rounded;
        label = "Checked Out";
        break;
      case 'late':
        bg = secondary.withValues(alpha: 0.18);
        text = secondary;
        icon = Icons.warning_rounded;
        label = "Late";
        break;
      case 'absent':
        bg = accent.withValues(alpha: 0.18);
        text = accent;
        icon = Icons.cancel;
        label = "Absent";
        break;
      default:
        bg = primary.withValues(alpha: 0.18);
        text = primary;
        icon = Icons.check_circle;
        label = "Present";
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.04),
              blurRadius: 6,
              offset: Offset(0, 2))
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(date,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                if (isAdminCorrected) ...[
                  const SizedBox(height: 6),
                  _adminCorrectedBadge(),
                ],
                const SizedBox(height: 4),
                Text(subtitle,
                    style: const TextStyle(color: Colors.grey, fontSize: 13)),
                if (isAdminCorrected) ...[
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => _openAuditDialog(
                      context: context,
                      attendanceId: attendanceId,
                      dateLabel: date,
                    ),
                    child: const Text('View audit history'),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(50),
            ),
            child: Row(
              children: [
                Icon(icon, color: text, size: 16),
                const SizedBox(width: 4),
                Text(label,
                    style: TextStyle(
                        color: text,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _insightCard(String avgCheckIn, int streak) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.04),
              blurRadius: 8,
              offset: Offset(0, 2))
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          _InsightRow("Average Check-in Time", avgCheckIn),
          const Divider(),
          _InsightRow("Longest Attendance Streak", "$streak Days"),
          const Divider(),
          _InsightRow("Most Late Day", "Tuesday"),
        ],
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  final String label;
  final String value;
  const _InsightRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: Colors.black87)),
        ],
      ),
    );
  }
}
