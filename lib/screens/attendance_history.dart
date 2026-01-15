import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AttendanceHistoryPage extends StatelessWidget {
  final String childId;
  final String childName;
  final String className;

  const AttendanceHistoryPage({
    super.key,
    required this.childId,
    required this.childName,
    required this.className,
  });

  static const Color primary = Color(0xFF7ACB9E);
  static const Color secondary = Color(0xFFFFC107);
  static const Color accent = Color(0xFFF44336);
  static const Color backgroundLight = Color(0xFFF8FBFA);

  String normalize(String s) =>
      s.replaceAll(RegExp(r'[\s\n\r\t]'), '').trim();

  @override
  Widget build(BuildContext context) {
    final normalizedChildRef = '/children/${normalize(childId)}';
    print("🧩 DEBUG: childId=$childId | childRef=$normalizedChildRef");

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
            .orderBy('date', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          print("🔥 hasData=${snapshot.hasData} | count=${snapshot.data?.docs.length ?? 0}");

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: primary));
          }

          if (snapshot.hasError) {
            return const Center(child: Text("Error loading attendance history"));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No attendance records found"));
          }

          final docs = snapshot.data!.docs;
          final normalizedDocs = docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            final ref = normalize((data['childRef'] ?? '').toString());
            final id = normalize((data['childId'] ?? '').toString());
            return ref == normalizedChildRef || id == normalize(childId);
          }).toList();

          if (normalizedDocs.isEmpty) {
            print("❌ No match for $normalizedChildRef");
            return const Center(child: Text("No attendance found for this child"));
          }

          print("✅ Found ${normalizedDocs.length} matched attendance records");

          // === Summary counters ===
          int present = 0, absent = 0, late = 0;
          List<DateTime> checkinTimes = [];

          for (var doc in normalizedDocs) {
            final data = doc.data() as Map<String, dynamic>;
            final ts = data['check_in_time'] as Timestamp?;
            final presentFlag = data['isPresent'] ?? false;

            if (presentFlag == true) present++;
            if (presentFlag == false) absent++;
            if (ts != null) {
              final t = ts.toDate();
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
                "$childName — $className",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              _buildMonthlySummary(present, absent, late, rate),
              const SizedBox(height: 16),
              const Text("Daily Records",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (var doc in normalizedDocs) ...[
                _recordCardFromFirestore(doc.data() as Map<String, dynamic>),
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
          color: color.withOpacity(0.15),
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
  Widget _recordCardFromFirestore(Map<String, dynamic> data) {
    final checkInTs = data['check_in_time'] as Timestamp?;
    final checkOutTs = data['check_out_time'] as Timestamp?;
    final isPresent = data['isPresent'] ?? false;

    final checkIn = checkInTs != null
        ? DateFormat('hh:mm a').format(checkInTs.toDate())
        : "-";
    final checkOut = checkOutTs != null
        ? DateFormat('hh:mm a').format(checkOutTs.toDate())
        : "-";

    final dateTs = data['date'];
    DateTime? dateTime;
    if (dateTs is Timestamp) {
      dateTime = dateTs.toDate();
    } else {
      try {
        dateTime = DateTime.parse(dateTs.toString());
      } catch (_) {
        dateTime = null;
      }
    }

    final date = dateTime != null
        ? DateFormat('EEE, dd MMM yyyy').format(dateTime)
        : "Unknown Date";

    String status = "absent";
    if (isPresent == true) {
      final t = checkInTs?.toDate();
      if (t != null && (t.hour > 8 || (t.hour == 8 && t.minute > 0))) {
        status = "late";
      } else {
        status = "present";
      }
    }

    String subtitle = isPresent
        ? "Check-in: $checkIn   Check-out: $checkOut"
        : "Not checked in";

    return _recordCard(date, subtitle, status);
  }

  Widget _recordCard(String date, String subtitle, String status) {
    Color bg;
    Color text;
    IconData icon;
    String label;

    switch (status) {
      case 'late':
        bg = secondary.withOpacity(0.18);
        text = secondary;
        icon = Icons.warning_rounded;
        label = "Late";
        break;
      case 'absent':
        bg = accent.withOpacity(0.18);
        text = accent;
        icon = Icons.cancel;
        label = "Absent";
        break;
      default:
        bg = primary.withOpacity(0.18);
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
                const SizedBox(height: 4),
                Text(subtitle,
                    style: const TextStyle(color: Colors.grey, fontSize: 13)),
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
          _insightRow("Average Check-in Time", avgCheckIn),
          const Divider(),
          _insightRow("Longest Attendance Streak", "$streak Days"),
          const Divider(),
          _insightRow("Most Late Day", "Tuesday"),
        ],
      ),
    );
  }
}

class _insightRow extends StatelessWidget {
  final String label;
  final String value;
  const _insightRow(this.label, this.value, {super.key});

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
