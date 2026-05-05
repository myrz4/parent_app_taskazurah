import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'attendance_history.dart';
import 'app_lock_settings_page.dart';
import 'child_details_page.dart';
import 'parent_linked_children.dart';

class _ResolvedNfcInfo {
  const _ResolvedNfcInfo({required this.tag, this.lastUsedRaw});

  final String tag;
  final dynamic lastUsedRaw;
}

class ParentProfilePage extends StatelessWidget {
  const ParentProfilePage({super.key, required this.parentId});

  final String parentId;

  static const Color primary = Color(0xFF7ACB9E);
  static const Color background = Color(0xFFF6F8F7);
  static const double _cardRadius = 16.0;
  static const double _cardElevation = 2.0;
  static const EdgeInsets _cardPadding = EdgeInsets.all(16.0);
  static const List<double> _spacing = [4.0, 8.0, 12.0, 16.0, 20.0, 24.0];

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

  String _formatDateTime(dynamic timestamp) {
    if (timestamp == null) {
      return 'Never used';
    }

    DateTime? date;
    if (timestamp is Timestamp) {
      date = timestamp.toDate().toLocal();
    } else if (timestamp is String && timestamp.isNotEmpty) {
      date = DateTime.tryParse(timestamp)?.toLocal();
      if (date == null) {
        return timestamp;
      }
    }

    if (date == null) {
      return 'Never used';
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final inputDay = DateTime(date.year, date.month, date.day);
    if (inputDay == today) {
      final hh = date.hour.toString().padLeft(2, '0');
      final mm = date.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    }

    return '${date.day} ${_shortMonth(date.month)} ${date.year}';
  }

  String _shortMonth(int month) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(title, style: _subheading),
      ),
    );
  }

  Widget _avatar(String? photoUrl, {double size = 70, bool circular = false}) {
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.15),
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular ? null : BorderRadius.circular(12),
      ),
      child: Icon(
        circular ? Icons.person : Icons.child_care,
        size: size * 0.5,
        color: primary,
      ),
    );

    if (photoUrl == null || photoUrl.trim().isEmpty) {
      return fallback;
    }

    if (circular) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: primary.withValues(alpha: 0.15),
        child: ClipOval(
          child: Image.network(
            photoUrl,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => fallback,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        photoUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }

  Widget _infoLabel(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _label),
        SizedBox(height: _spacing[0]),
        Text(value, style: _value),
      ],
    );
  }

  String _firstNonBlank(List<dynamic> values, {String fallback = ''}) {
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

  String _readChildNfcTag(Map<String, dynamic> data) {
    final nfcMap = _asMap(data['nfc']);
    return _firstNonBlank(
      [nfcMap['tagUid'], nfcMap['uid'], data['nfc_uid'], data['nfcUid']],
      fallback: '',
    ).toUpperCase();
  }

  dynamic _readChildNfcLastUsed(Map<String, dynamic> data) {
    final nfcMap = _asMap(data['nfc']);
    return nfcMap['lastUsed'] ?? data['nfcLastUsed'] ?? data['lastUsed'];
  }

  _ResolvedNfcInfo _fallbackNfcInfo(Map<String, dynamic> parentData) {
    final nfcMap = _asMap(parentData['nfc']);
    final tag = _firstNonBlank(
      [nfcMap['tagUid'], nfcMap['uid'], parentData['nfc_uid'], parentData['nfcUid']],
      fallback: 'Not linked',
    ).toUpperCase();
    final lastUsedRaw =
        nfcMap['lastUsed'] ?? parentData['nfcLastUsed'] ?? parentData['qrExpiry'];
    return _ResolvedNfcInfo(tag: tag, lastUsedRaw: lastUsedRaw);
  }

  Future<_ResolvedNfcInfo> _resolveDisplayedNfcInfo(
    Map<String, dynamic> parentData,
    List<ParentLinkedChild> linkedChildren,
  ) async {
    final fallback = _fallbackNfcInfo(parentData);
    if (linkedChildren.isEmpty) {
      return fallback;
    }

    final tags = <String>[];
    dynamic lastUsedRaw = fallback.lastUsedRaw;

    for (final linkedChild in linkedChildren) {
      try {
        final snapshot = await linkedChild.childRef.get();
        if (!snapshot.exists) {
          continue;
        }
        final data = snapshot.data() ?? <String, dynamic>{};
        final tag = _readChildNfcTag(data);
        if (tag.isNotEmpty && !tags.contains(tag)) {
          tags.add(tag);
        }
        lastUsedRaw ??= _readChildNfcLastUsed(data);
      } catch (_) {
        continue;
      }
    }

    if (tags.isEmpty) {
      return fallback;
    }

    final tag = tags.length == 1
        ? tags.first
        : '${tags.first} (+${tags.length - 1} more)';
    return _ResolvedNfcInfo(tag: tag, lastUsedRaw: lastUsedRaw);
  }

  Future<void> _openAttendanceHistory(
    BuildContext context,
    List<ParentLinkedChild> linkedChildren,
  ) async {
    if (linkedChildren.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No linked child available yet.')),
      );
      return;
    }

    ParentLinkedChild? selectedChild;
    if (linkedChildren.length == 1) {
      selectedChild = linkedChildren.first;
    } else {
      selectedChild = await showModalBottomSheet<ParentLinkedChild>(
        context: context,
        showDragHandle: true,
        builder: (context) {
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Text(
                    'Choose a child to view attendance history',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ...linkedChildren.map(
                  (child) => ListTile(
                    leading: const Icon(Icons.child_care_outlined),
                    title: Text(child.childName, style: _value),
                    subtitle: Text(child.childId, style: _label),
                    onTap: () => Navigator.of(context).pop(child),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    final chosenChild = selectedChild;
    if (!context.mounted || chosenChild == null) {
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AttendanceHistoryPage(
          childId: chosenChild.childId,
          childName: chosenChild.childName,
        ),
      ),
    );
  }

  Future<void> _openInvoicesAndReceipts(
    BuildContext context, {
    required String parentName,
  }) async {
    await Navigator.pushNamed(
      context,
      '/fee_ledger',
      arguments: {
        'parentId': parentId,
        'parentName': parentName,
      },
    );
  }

  Future<void> _confirmAndLogout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (shouldLogout != true) {
      return;
    }

    await FirebaseAuth.instance.signOut();
    if (!context.mounted) {
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  Widget _skeletonCard() {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
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
  }

  Widget _errorCard(String message) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      elevation: _cardElevation,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: _cardPadding,
        child: Text(message, style: TextStyle(color: Colors.red[700])),
      ),
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
        title: Text(
          'Profile',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: parentRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: primary),
            );
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('Parent data not found'));
          }

          final data = snapshot.data!.data() ?? <String, dynamic>{};
          final parentName = (data['parentName'] ?? 'N/A').toString();
          final phone = (data['phone'] ?? 'N/A').toString();
          final photoUrl = data['photoUrl']?.toString();
          final linkedChildren = extractParentLinkedChildren(data);
          final settingsData = data['settings'];
          final settingsMap = settingsData is Map
              ? Map<String, dynamic>.from(settingsData)
              : <String, dynamic>{};
          final notificationsData = settingsMap['notifications'];
          final notifications = notificationsData is Map
              ? Map<String, dynamic>.from(notificationsData)
              : <String, dynamic>{};

          return SingleChildScrollView(
            padding: EdgeInsets.all(_spacing[3]),
            child: Column(
              children: [
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(_cardRadius),
                  ),
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
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const AppLockSettingsPage(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.lock_outline, color: primary),
                            label: Text(
                              'App Lock',
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700,
                                color: primary,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: primary),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: EdgeInsets.symmetric(vertical: _spacing[2]),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _sectionTitle('My Children'),
                if (linkedChildren.isEmpty)
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(_cardRadius),
                    ),
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
                  ...linkedChildren.map((linkedChild) {
                    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      future: linkedChild.childRef.get(),
                      builder: (context, childSnapshot) {
                        if (childSnapshot.connectionState == ConnectionState.waiting) {
                          return _skeletonCard();
                        }

                        if (!childSnapshot.hasData || !childSnapshot.data!.exists) {
                          return _errorCard('Failed to load ${linkedChild.childName}');
                        }

                        final childData = childSnapshot.data!.data() ?? <String, dynamic>{};
                        final childName =
                            (childData['name'] ?? linkedChild.childName).toString();
                        final childPhoto = childData['photoUrl']?.toString();

                        return Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(_cardRadius),
                          ),
                          elevation: _cardElevation,
                          margin: const EdgeInsets.only(bottom: 12, top: 4),
                          child: Padding(
                            padding: _cardPadding,
                            child: Row(
                              children: [
                                _avatar(childPhoto, size: 70),
                                SizedBox(width: _spacing[3]),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        childName,
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      SizedBox(height: _spacing[0]),
                                      Text(linkedChild.childId, style: _label),
                                    ],
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => ChildDetailsPage(
                                          childId: linkedChild.childId,
                                          childNameFallback: childName,
                                        ),
                                      ),
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(
                                    'View Details',
                                    style: GoogleFonts.plusJakartaSans(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  }),
                if (data['linkedGuardians'] is List &&
                    (data['linkedGuardians'] as List).isNotEmpty) ...[
                  _sectionTitle('Linked Guardians'),
                  ...(data['linkedGuardians'] as List)
                      .whereType<Map>()
                      .map((guardian) => Map<String, dynamic>.from(guardian))
                      .map((guardian) {
                    final guardianName =
                        (guardian['name'] ?? 'Unknown').toString();
                    final relationship =
                        (guardian['relationship'] ?? 'Unknown').toString();
                    final guardianPhone =
                        (guardian['phone'] ?? 'Not provided').toString();
                    return Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(_cardRadius),
                      ),
                      elevation: _cardElevation,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text(guardianName, style: _value),
                        subtitle: Text(
                          '$relationship - $guardianPhone',
                          style: _body,
                        ),
                      ),
                    );
                  }),
                ],
                _sectionTitle('NFC Tag Information'),
                FutureBuilder<_ResolvedNfcInfo>(
                  future: _resolveDisplayedNfcInfo(data, linkedChildren),
                  builder: (context, nfcSnapshot) {
                    final resolved = nfcSnapshot.data ?? _fallbackNfcInfo(data);
                    return Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(_cardRadius),
                      ),
                      elevation: _cardElevation,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: _cardPadding,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.nfc, color: primary, size: 28),
                                SizedBox(width: _spacing[2]),
                                _infoLabel('Tag UID', resolved.tag),
                              ],
                            ),
                            _infoLabel(
                              'Last Used',
                              _formatDateTime(resolved.lastUsedRaw),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                _sectionTitle('Notifications'),
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(_cardRadius),
                  ),
                  elevation: _cardElevation,
                  child: _NotificationPreferencesCard(
                    parentRef: parentRef,
                    settings: notifications,
                  ),
                ),
                _sectionTitle('Documents'),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            _openAttendanceHistory(context, linkedChildren),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: primary),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: EdgeInsets.symmetric(vertical: _spacing[3]),
                        ),
                        child: Text(
                          'Attendance History',
                          style: GoogleFonts.plusJakartaSans(color: primary),
                        ),
                      ),
                    ),
                    SizedBox(width: _spacing[2]),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _openInvoicesAndReceipts(
                          context,
                          parentName: parentName,
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: primary),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: EdgeInsets.symmetric(vertical: _spacing[3]),
                        ),
                        child: Text(
                          'Invoices & Receipts',
                          style: GoogleFonts.plusJakartaSans(color: primary),
                        ),
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
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _confirmAndLogout(context),
              icon: const Icon(Icons.logout),
              label: Text(
                'Logout',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationPreferencesCard extends StatefulWidget {
  const _NotificationPreferencesCard({
    required this.parentRef,
    required this.settings,
  });

  final DocumentReference<Map<String, dynamic>> parentRef;
  final Map<String, dynamic> settings;

  @override
  State<_NotificationPreferencesCard> createState() =>
      _NotificationPreferencesCardState();
}

class _NotificationPreferencesCardState extends State<_NotificationPreferencesCard> {
  final Map<String, bool> _overrides = <String, bool>{};
  final Set<String> _savingFields = <String>{};
  Timer? _savedIndicatorTimer;
  String? _recentlySavedField;

  @override
  void dispose() {
    _savedIndicatorTimer?.cancel();
    super.dispose();
  }

  bool _valueFor(String field, bool fallback) {
    return _overrides[field] ?? fallback;
  }

  String _defaultSubtitle(String field) {
    switch (field) {
      case 'attendance':
        return 'Check-in and check-out alerts for your child.';
      case 'activity':
        return 'Memory updates and classroom activity posts.';
      case 'fees':
        return 'Invoice reminders and payment follow-ups.';
      case 'emergency':
        return 'Important urgent notices from the taska.';
      default:
        return 'Notification preference';
    }
  }

  Future<void> _updateField(String field, bool value, bool fallback) async {
    final previousValue = _valueFor(field, fallback);

    setState(() {
      _overrides[field] = value;
      _savingFields.add(field);
      if (_recentlySavedField == field) {
        _recentlySavedField = null;
      }
    });

    try {
      await widget.parentRef.set(
        {
          'settings.notifications.$field': value,
        },
        SetOptions(merge: true),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _savingFields.remove(field);
        _recentlySavedField = field;
      });

      _savedIndicatorTimer?.cancel();
      _savedIndicatorTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted || _recentlySavedField != field) {
          return;
        }
        setState(() {
          _recentlySavedField = null;
        });
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _overrides[field] = previousValue;
        _savingFields.remove(field);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to save notification preference.')),
      );
    }
  }

  Widget _buildTile({
    required String field,
    required String title,
    required bool fallback,
    bool showDivider = true,
  }) {
    final currentValue = _valueFor(field, fallback);
    final subtitle = _savingFields.contains(field)
        ? 'Saving...'
        : _recentlySavedField == field
            ? 'Saved'
            : _defaultSubtitle(field);

    return Column(
      children: [
        SwitchListTile.adaptive(
          title: Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 15)),
          subtitle: Text(
            subtitle,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: _savingFields.contains(field)
                  ? ParentProfilePage.primary
                  : Colors.grey[600],
              fontWeight: _savingFields.contains(field) ||
                      _recentlySavedField == field
                  ? FontWeight.w700
                  : FontWeight.w500,
            ),
          ),
          value: currentValue,
          activeThumbColor: ParentProfilePage.primary,
          onChanged: (newValue) => _updateField(field, newValue, fallback),
        ),
        if (showDivider) const Divider(height: 1),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildTile(
          field: 'attendance',
          title: 'Attendance Alerts',
          fallback: (widget.settings['attendance'] as bool?) ?? true,
        ),
        _buildTile(
          field: 'activity',
          title: 'Activity Updates',
          fallback: (widget.settings['activity'] as bool?) ?? true,
        ),
        _buildTile(
          field: 'fees',
          title: 'Billing Reminders',
          fallback: (widget.settings['fees'] as bool?) ?? false,
        ),
        _buildTile(
          field: 'emergency',
          title: 'Emergency Alerts',
          fallback: (widget.settings['emergency'] as bool?) ?? true,
          showDivider: false,
        ),
      ],
    );
  }
}