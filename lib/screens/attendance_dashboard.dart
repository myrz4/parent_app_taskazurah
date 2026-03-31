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
                  print("🔥 FIRESTORE QUERY ERROR: ${snapshot.error}");
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
                    shadowColor: primary.withOpacity(0.3),
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
    final checkInRaw = data['check_in_time'];
    final checkOutRaw = data['check_out_time'];
    final teacher = data['teacher'] ?? 'Unknown Teacher';
    final bool isPresent = (data['isPresent'] ?? false) as bool;

    DateTime? checkInTime;
    DateTime? checkOutTime;

    if (checkInRaw is Timestamp) {
      checkInTime = checkInRaw.toDate();
    } else if (checkInRaw is String) {
      checkInTime = DateTime.tryParse(checkInRaw);
    }

    if (checkOutRaw is Timestamp) {
      checkOutTime = checkOutRaw.toDate();
    } else if (checkOutRaw is String) {
      checkOutTime = DateTime.tryParse(checkOutRaw);
    }

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
                  isPresent ? 'Checked In' : 'Absent',
                  style: const TextStyle(
                    color: primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
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
  const _StatCardPlaceholder({super.key});

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
