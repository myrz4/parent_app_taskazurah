import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';

final Map<String, Stream<List<QueryDocumentSnapshot>>> _attendanceChildStreamCache =
    <String, Stream<List<QueryDocumentSnapshot>>>{};
final Map<String, Stream<ResolvedTodayAttendanceStatus>>
    _resolvedTodayAttendanceStatusCache =
    <String, Stream<ResolvedTodayAttendanceStatus>>{};

class ResolvedTodayAttendanceStatus {
  final Map<String, dynamic>? attendance;
  final bool pickupAllowed;
  final String reason;
  final String message;

  const ResolvedTodayAttendanceStatus({
    required this.attendance,
    required this.pickupAllowed,
    required this.reason,
    required this.message,
  });

  const ResolvedTodayAttendanceStatus.empty()
      : attendance = null,
        pickupAllowed = false,
        reason = '',
        message = '';
}

Stream<ResolvedTodayAttendanceStatus> attendanceWatchResolvedTodayStatus({
  required String parentId,
  required String childId,
  required String childRefPath,
  Duration refreshInterval = const Duration(seconds: 3),
}) {
  final normalizedParentId = parentId.trim();
  final normalizedChildId = childId.trim();
  final normalizedChildRefPath = childRefPath.trim();

  if (normalizedParentId.isEmpty ||
      (normalizedChildId.isEmpty && normalizedChildRefPath.isEmpty)) {
    return Stream<ResolvedTodayAttendanceStatus>.value(
      const ResolvedTodayAttendanceStatus.empty(),
    );
  }

  final cacheKey =
      '$normalizedParentId::$normalizedChildId::$normalizedChildRefPath';

  return _resolvedTodayAttendanceStatusCache.putIfAbsent(cacheKey, () {
    final callable = FirebaseFunctions.instanceFor(region: 'asia-southeast1')
        .httpsCallable('attendanceParentPickupEligibility');

    Timer? refreshTimer;
    var hasEmitted = false;
    var lastValue = const ResolvedTodayAttendanceStatus.empty();
    late final StreamController<ResolvedTodayAttendanceStatus> controller;

    Future<void> emitResolvedStatus() async {
      try {
        final response = await callable.call(<String, dynamic>{
          'parentId': normalizedParentId,
          'childId': normalizedChildId,
          'childRef': normalizedChildRefPath,
        });
        final raw = response.data;
        final data = raw is Map
            ? Map<String, dynamic>.from(raw)
            : const <String, dynamic>{};
        final attendanceRaw = data['attendance'];
        final attendance = attendanceRaw is Map
            ? Map<String, dynamic>.from(attendanceRaw)
            : null;

        lastValue = ResolvedTodayAttendanceStatus(
          attendance: attendance,
          pickupAllowed: data['allowed'] == true,
          reason: (data['reason'] ?? '').toString().trim(),
          message: (data['message'] ?? '').toString().trim(),
        );
        hasEmitted = true;
        if (!controller.isClosed) {
          controller.add(lastValue);
        }
      } catch (_) {
        if (!controller.isClosed && !hasEmitted) {
          controller.add(lastValue);
        }
      }
    }

    controller = StreamController<ResolvedTodayAttendanceStatus>.broadcast(
      onListen: () {
        refreshTimer ??= Timer.periodic(refreshInterval, (_) {
          unawaited(emitResolvedStatus());
        });
        unawaited(emitResolvedStatus());
      },
      onCancel: () {
        refreshTimer?.cancel();
        refreshTimer = null;
      },
    );

    return controller.stream;
  });
}

Stream<List<QueryDocumentSnapshot>> attendanceWatchChildDocs(
  String childId, {
  Duration refreshInterval = const Duration(seconds: 3),
}) {
  final normalizedChildId = childId.trim();
  if (normalizedChildId.isEmpty) {
    return Stream<List<QueryDocumentSnapshot>>.value(const <QueryDocumentSnapshot>[]);
  }

  return _attendanceChildStreamCache.putIfAbsent(normalizedChildId, () {
    final query = FirebaseFirestore.instance
        .collection('attendance')
        .where('childId', isEqualTo: normalizedChildId);

    StreamSubscription<QuerySnapshot>? liveSubscription;
    Timer? refreshTimer;
    late final StreamController<List<QueryDocumentSnapshot>> controller;

    Future<void> emitServerSnapshot() async {
      try {
        final snapshot = await query.get(const GetOptions(source: Source.server));
        if (!controller.isClosed) {
          controller.add(List<QueryDocumentSnapshot>.from(snapshot.docs));
        }
      } catch (_) {
        // Keep the live listener authoritative if the fallback server refresh misses.
      }
    }

    controller = StreamController<List<QueryDocumentSnapshot>>.broadcast(
      onListen: () {
        liveSubscription ??= query
            .snapshots(includeMetadataChanges: true)
            .listen(
              (snapshot) {
                if (!controller.isClosed) {
                  controller.add(List<QueryDocumentSnapshot>.from(snapshot.docs));
                }
              },
              onError: (Object error, StackTrace stackTrace) {
                if (!controller.isClosed) {
                  controller.addError(error, stackTrace);
                }
              },
            );
        refreshTimer ??= Timer.periodic(refreshInterval, (_) {
          unawaited(emitServerSnapshot());
        });
        unawaited(emitServerSnapshot());
      },
      onCancel: () async {
        await liveSubscription?.cancel();
        liveSubscription = null;
        refreshTimer?.cancel();
        refreshTimer = null;
      },
    );

    return controller.stream;
  });
}

DateTime? attendanceReadTimestamp(Map<String, dynamic> data, List<String> keys) {
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

String attendanceReadString(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = (data[key] ?? '').toString().trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}

DateTime? attendanceCheckInTime(Map<String, dynamic> data) {
  return attendanceReadTimestamp(
    data,
    const ['checkInAt', 'check_in_time', 'checkInTime', 'check_in'],
  );
}

DateTime? attendanceCheckOutTime(Map<String, dynamic> data) {
  return attendanceReadTimestamp(
    data,
    const ['checkOutAt', 'check_out_time', 'checkOutTime', 'check_out'],
  );
}

DateTime? _parseDateFromDocId(String docId) {
  final match = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(docId);
  if (match == null) return null;
  return DateTime.tryParse(match.group(1)!);
}

DateTime? _readRawDate(Map<String, dynamic> data) {
  final rawDate = data['date'];
  if (rawDate is Timestamp) return rawDate.toDate();
  if (rawDate is DateTime) return rawDate;
  if (rawDate is String) {
    final parsed = DateTime.tryParse(rawDate);
    if (parsed != null) return parsed;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(rawDate);
    if (match != null) {
      return DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
      );
    }
  }
  return null;
}

DateTime attendanceBestRecordDate(Map<String, dynamic> data, {String? docId}) {
  final updatedAt = attendanceReadTimestamp(data, const ['updatedAt']);
  if (updatedAt != null) return updatedAt;

  final checkOut = attendanceCheckOutTime(data);
  if (checkOut != null) return checkOut;

  final checkIn = attendanceCheckInTime(data);
  if (checkIn != null) return checkIn;

  final createdAt = attendanceReadTimestamp(data, const ['createdAt']);
  if (createdAt != null) return createdAt;

  final dateKey = attendanceReadString(data, const ['dateKey']);
  if (dateKey.isNotEmpty) {
    final parsed = DateTime.tryParse(dateKey);
    if (parsed != null) return parsed;
  }

  final rawDate = _readRawDate(data);
  if (rawDate != null) return rawDate;

  final fromId = docId == null ? null : _parseDateFromDocId(docId);
  return fromId ?? DateTime.fromMillisecondsSinceEpoch(0);
}

String attendanceDayKey(Map<String, dynamic> data, {String? docId}) {
  final dateKey = attendanceReadString(data, const ['dateKey']);
  if (dateKey.isNotEmpty) {
    final match = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(dateKey);
    if (match != null) return match.group(1)!;
  }

  final rawDate = _readRawDate(data);
  if (rawDate != null) {
    return DateFormat('yyyy-MM-dd').format(rawDate);
  }

  final fromId = docId == null ? null : _parseDateFromDocId(docId);
  if (fromId != null) {
    return DateFormat('yyyy-MM-dd').format(fromId);
  }

  final bestDate = attendanceBestRecordDate(data, docId: docId);
  return DateFormat('yyyy-MM-dd').format(bestDate);
}

bool attendanceIsAdminCorrected(Map<String, dynamic> data) {
  final manualReason = attendanceReadString(
    data,
    const ['manualEditReason', 'manual_edit_reason', 'reason'],
  );
  if (manualReason.isNotEmpty) return true;

  final checkInMethod = attendanceReadString(
    data,
    const ['checkInMethod', 'checkin_method'],
  ).toUpperCase();
  final checkOutMethod = attendanceReadString(
    data,
    const ['checkOutMethod', 'checkout_method'],
  ).toUpperCase();
  return checkInMethod.contains('ADMIN_MANUAL') ||
      checkOutMethod.contains('ADMIN_MANUAL');
}

int attendanceSortEpoch(Map<String, dynamic> data, {String? docId}) {
  return attendanceBestRecordDate(data, docId: docId).millisecondsSinceEpoch;
}

bool attendanceShouldPreferDoc(
  QueryDocumentSnapshot candidate,
  QueryDocumentSnapshot? current,
) {
  if (current == null) return true;

  final candidateData = Map<String, dynamic>.from(candidate.data() as Map);
  final currentData = Map<String, dynamic>.from(current.data() as Map);

  final candidateEpoch = attendanceSortEpoch(candidateData, docId: candidate.id);
  final currentEpoch = attendanceSortEpoch(currentData, docId: current.id);
  if (candidateEpoch != currentEpoch) {
    return candidateEpoch > currentEpoch;
  }

  final candidateCorrected = attendanceIsAdminCorrected(candidateData);
  final currentCorrected = attendanceIsAdminCorrected(currentData);
  if (candidateCorrected != currentCorrected) {
    return candidateCorrected;
  }

  final candidateHasCheckOut = attendanceCheckOutTime(candidateData) != null;
  final currentHasCheckOut = attendanceCheckOutTime(currentData) != null;
  if (candidateHasCheckOut != currentHasCheckOut) {
    return candidateHasCheckOut;
  }

  final candidateHasCheckIn = attendanceCheckInTime(candidateData) != null;
  final currentHasCheckIn = attendanceCheckInTime(currentData) != null;
  if (candidateHasCheckIn != currentHasCheckIn) {
    return candidateHasCheckIn;
  }

  return candidate.id.compareTo(current.id) > 0;
}

List<QueryDocumentSnapshot> collapseAttendanceDocsByDay(
  Iterable<QueryDocumentSnapshot> docs,
) {
  final effectiveDocsByDay = <String, QueryDocumentSnapshot>{};

  for (final doc in docs) {
    final data = Map<String, dynamic>.from(doc.data() as Map);
    final dayKey = attendanceDayKey(data, docId: doc.id);
    final current = effectiveDocsByDay[dayKey];
    if (attendanceShouldPreferDoc(doc, current)) {
      effectiveDocsByDay[dayKey] = doc;
    }
  }

  final collapsed = effectiveDocsByDay.values.toList(growable: false);
  collapsed.sort((left, right) {
    final leftData = Map<String, dynamic>.from(left.data() as Map);
    final rightData = Map<String, dynamic>.from(right.data() as Map);
    final leftEpoch = attendanceSortEpoch(leftData, docId: left.id);
    final rightEpoch = attendanceSortEpoch(rightData, docId: right.id);
    return rightEpoch.compareTo(leftEpoch);
  });
  return collapsed;
}

QueryDocumentSnapshot? resolveAttendanceDocForDay(
  Iterable<QueryDocumentSnapshot> docs,
  DateTime day,
) {
  final targetDayKey = DateFormat('yyyy-MM-dd').format(day);
  QueryDocumentSnapshot? best;

  for (final doc in docs) {
    final data = Map<String, dynamic>.from(doc.data() as Map);
    if (attendanceDayKey(data, docId: doc.id) != targetDayKey) {
      continue;
    }
    if (attendanceShouldPreferDoc(doc, best)) {
      best = doc;
    }
  }

  return best;
}

List<QueryDocumentSnapshot> attendanceDocsForMonth(
  Iterable<QueryDocumentSnapshot> docs,
  DateTime month,
) {
  final collapsed = collapseAttendanceDocsByDay(docs);
  return collapsed.where((doc) {
    final data = Map<String, dynamic>.from(doc.data() as Map);
    final recordDate = attendanceBestRecordDate(data, docId: doc.id);
    return recordDate.year == month.year && recordDate.month == month.month;
  }).toList(growable: false);
}