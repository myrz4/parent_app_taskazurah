import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class ChildDetailsPage extends StatelessWidget {
  const ChildDetailsPage({
    super.key,
    required this.childId,
    this.childNameFallback,
  });

  final String childId;
  final String? childNameFallback;

  static const Color primary = Color(0xFF7ACB9E);
  static const Color background = Color(0xFFF6F8F7);

  DateTime? _readDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  String _firstNonBlank(List<dynamic> values, {String fallback = 'Not provided'}) {
    for (final value in values) {
      final text = (value ?? '').toString().trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return fallback;
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const <String, dynamic>{};
  }

  String _readChildNfcUid(Map<String, dynamic> data) {
    final nfcMap = _asMap(data['nfc']);
    return _firstNonBlank(
      [nfcMap['tagUid'], nfcMap['uid'], data['nfc_uid'], data['nfcUid']],
      fallback: '',
    );
  }

  String _formatBirthDate(dynamic value) {
    final date = _readDate(value);
    if (date == null) {
      return 'Not provided';
    }
    return DateFormat('d MMM yyyy').format(date);
  }

  String _ageSummary(dynamic value) {
    final birthDate = _readDate(value);
    if (birthDate == null) {
      return 'Unknown age';
    }

    final today = DateTime.now();
    var years = today.year - birthDate.year;
    var months = today.month - birthDate.month;

    if (today.day < birthDate.day) {
      months -= 1;
    }
    if (months < 0) {
      years -= 1;
      months += 12;
    }
    if (years <= 0) {
      return '$months month${months == 1 ? '' : 's'}';
    }
    if (months == 0) {
      return '$years year${years == 1 ? '' : 's'}';
    }
    return '$years year${years == 1 ? '' : 's'} $months month${months == 1 ? '' : 's'}';
  }

  String _feePlanLabel(Map<String, dynamic> data) {
    final careType = (data['careType'] ?? '').toString().trim().toLowerCase();
    switch (careType) {
      case 'fulltime':
        return 'Monthly Full-Time';
      case 'transit':
        return 'Transit Monthly';
      case 'transit_halfday_month':
        return 'Transit Half Day';
      case 'transit_2h_month':
        return 'Transit 2 Hours';
      case 'transit_schoolholiday_month':
        return 'Transit School Holiday';
      case 'transit_1day':
        return 'Transit 1 Day';
      case 'transit_1week':
        return 'Transit 1 Week';
      case 'transit_1hour':
        return 'Transit 1 Hour';
    }

    final feePlan = (data['feePlan'] ?? '').toString().trim().toLowerCase();
    if (feePlan == 'transit') {
      return 'Transit Monthly';
    }
    return 'Monthly Full-Time';
  }

  String _billingDueDay(dynamic value) {
    final day = value is int
        ? value
        : value is num
            ? value.toInt()
            : int.tryParse((value ?? '').toString());
    if (day == null) {
      return 'Every month';
    }
    return 'Due on day $day each month';
  }

  String _maskUid(String rawUid) {
    final uid = rawUid.trim().toUpperCase();
    if (uid.isEmpty) {
      return 'Not linked yet';
    }
    if (uid.length <= 8) {
      return uid;
    }
    return '${uid.substring(0, 4)} •••• ${uid.substring(uid.length - 4)}';
  }

  Widget _summaryChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _detailCard({
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    color: Colors.black87,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final childRef =
        FirebaseFirestore.instance.collection('children').doc(childId.trim());

    return Scaffold(
      backgroundColor: background,
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: childRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: primary),
            );
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('Child profile not found.'));
          }

          final data = snapshot.data!.data() ?? <String, dynamic>{};
          final childName = _firstNonBlank(
            [data['name'], childNameFallback, childId],
            fallback: childId,
          );
          final photoUrl = _firstNonBlank(
            [data['photoUrl'], data['image']],
            fallback: '',
          );
          final status = _firstNonBlank([data['status']], fallback: 'Active');
          final birthDate = data['birthDate'];
          final age = _ageSummary(birthDate);
          final identifier = _firstNonBlank(
            [data['childIcNo'], data['icNo'], childId],
            fallback: childId,
          );
          final parentName = _firstNonBlank(
            [data['parentName'], data['guardianName']],
          );
          final parentContact = _firstNonBlank(
            [data['parentContact'], data['parentPhone'], data['phone']],
          );
          final classGroup = _firstNonBlank(
            [
              data['className'],
              data['groupName'],
              data['class'],
              data['group'],
              data['programme'],
            ],
            fallback: '',
          );
          final transportEnabled = data['transportFromTadika'] == true;
          final billingPlan = _feePlanLabel(data);
          final dueDayLabel = _billingDueDay(data['billingDueDay']);
          final nfcUid = _maskUid(_readChildNfcUid(data));

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 280,
                backgroundColor: primary,
                foregroundColor: Colors.white,
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF7ACB9E), Color(0xFF4F9D77)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 44,
                              backgroundColor: Colors.white.withValues(alpha: 0.18),
                              backgroundImage:
                                  photoUrl.isEmpty ? null : NetworkImage(photoUrl),
                              child: photoUrl.isEmpty
                                  ? Text(
                                      childName.substring(0, 1).toUpperCase(),
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              childName,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              identifier,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                color: Colors.white.withValues(alpha: 0.84),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _summaryChip(status),
                                _summaryChip(age),
                                _summaryChip(billingPlan),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _detailCard(
                      title: 'Profile',
                      children: [
                        _detailRow(Icons.badge_outlined, 'Child ID', identifier),
                        _detailRow(
                          Icons.cake_outlined,
                          'Date of Birth',
                          _formatBirthDate(birthDate),
                        ),
                        _detailRow(Icons.timelapse_outlined, 'Current Age', age),
                        if (classGroup.isNotEmpty)
                          _detailRow(Icons.groups_outlined, 'Class / Group', classGroup),
                      ],
                    ),
                    _detailCard(
                      title: 'Billing & Access',
                      children: [
                        _detailRow(Icons.payments_outlined, 'Billing Plan', billingPlan),
                        _detailRow(Icons.event_outlined, 'Payment Schedule', dueDayLabel),
                        _detailRow(
                          Icons.directions_bus_outlined,
                          'Transport from Tadika',
                          transportEnabled ? 'Enabled' : 'Not enabled',
                        ),
                        _detailRow(Icons.nfc_outlined, 'NFC Tag', nfcUid),
                      ],
                    ),
                    _detailCard(
                      title: 'Guardian Contact',
                      children: [
                        _detailRow(Icons.person_outline, 'Parent / Guardian', parentName),
                        _detailRow(Icons.phone_outlined, 'Contact Number', parentContact),
                      ],
                    ),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}