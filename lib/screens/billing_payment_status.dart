import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

enum BillingPaymentStatusTone {
  success,
  info,
  warning,
  danger,
  neutral,
}

enum BillingPaymentAction {
  none,
  start,
  resume,
  sync,
}

class BillingLatestSession {
  BillingLatestSession({
    required this.sessionId,
    required this.status,
    required this.sessionState,
    required this.provider,
    required this.mode,
    required this.currency,
    required this.amountSen,
    required this.method,
    required this.bank,
    required this.receiptNo,
    required this.expiresAt,
    required this.createdAt,
    required this.completedAt,
    required this.lastSyncedAt,
  });

  final String sessionId;
  final String status;
  final String sessionState;
  final String provider;
  final String mode;
  final String currency;
  final int amountSen;
  final String method;
  final String bank;
  final String receiptNo;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final DateTime? lastSyncedAt;

  String get effectiveState => sessionState.isNotEmpty ? sessionState : status;

  bool get supportsInAppDummyFlow => provider == 'dummy' && mode == 'dummy';

  factory BillingLatestSession.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    final providerPayload = data['providerPayload'];
    final providerPayloadMap = providerPayload is Map
        ? providerPayload.cast<Object?, Object?>()
        : null;
    final rawAmount = data['amountSen'];

    return BillingLatestSession(
      sessionId: snapshot.id,
      status: _normalizedText(data['status']),
      sessionState: _normalizedText(providerPayloadMap?['sessionState']),
      provider: _normalizedText(data['provider'], fallback: 'dummy'),
      mode: _normalizedText(data['mode'], fallback: 'dummy'),
      currency: _text(data['currency'], fallback: 'MYR'),
      amountSen: rawAmount is int
          ? rawAmount
          : (rawAmount is num ? rawAmount.toInt() : 0),
      method: _text(data['method']),
      bank: _text(data['bank']),
      receiptNo: _text(data['providerReceiptNo']),
      expiresAt: _dateFrom(data['expiresAt']),
      createdAt: _dateFrom(data['createdAt']),
      completedAt: _dateFrom(data['completedAt']),
      lastSyncedAt: _dateFrom(data['lastSyncedAt']),
    );
  }
}

class BillingPaymentStatus {
  BillingPaymentStatus({
    required this.key,
    required this.label,
    required this.detail,
    required this.tone,
    required this.action,
    required this.primaryActionLabel,
    required this.isSettled,
  });

  final String key;
  final String label;
  final String detail;
  final BillingPaymentStatusTone tone;
  final BillingPaymentAction action;
  final String primaryActionLabel;
  final bool isSettled;
}

Stream<QuerySnapshot<Map<String, dynamic>>> billingLatestSessionStream({
  required String parentId,
  required String invoiceId,
}) {
  return FirebaseFirestore.instance
      .collection('parents')
      .doc(parentId)
      .collection('invoices')
      .doc(invoiceId)
      .collection('sessions')
      .orderBy('createdAt', descending: true)
      .limit(1)
      .snapshots();
}

BillingLatestSession? billingLatestSessionFromQuery(
  QuerySnapshot<Map<String, dynamic>>? snapshot,
) {
  if (snapshot == null || snapshot.docs.isEmpty) {
    return null;
  }
  return BillingLatestSession.fromDocument(snapshot.docs.first);
}

BillingPaymentStatus billingResolvePaymentStatus({
  required Map<String, dynamic> invoice,
  BillingLatestSession? latestSession,
  DateTime? now,
}) {
  final currentTime = now ?? DateTime.now();
  final invoiceStatus = _normalizedText(invoice['status'], fallback: 'unpaid');
  final dueDate = _dateFrom(invoice['dueDate']);
  final paidAt = _dateFrom(invoice['paidAt']);

  if (invoiceStatus == 'paid') {
    return BillingPaymentStatus(
      key: 'paid',
      label: 'Paid',
      detail: paidAt == null
          ? 'Payment completed successfully.'
          : 'Paid on ${_dateLabel(paidAt)}.',
      tone: BillingPaymentStatusTone.success,
      action: BillingPaymentAction.none,
      primaryActionLabel: '',
      isSettled: true,
    );
  }

  if (latestSession != null) {
    final sessionState = _normalizedText(
      latestSession.effectiveState,
      fallback: latestSession.status,
    );

    if (sessionState == 'succeeded' || sessionState == 'paid') {
      return BillingPaymentStatus(
        key: 'paid',
        label: 'Paid',
        detail: latestSession.completedAt == null
            ? 'Payment completed successfully.'
            : 'Paid on ${_dateLabel(latestSession.completedAt!)}.',
        tone: BillingPaymentStatusTone.success,
        action: BillingPaymentAction.none,
        primaryActionLabel: '',
        isSettled: true,
      );
    }

    if (sessionState == 'processing') {
      return BillingPaymentStatus(
        key: 'processing',
        label: 'Processing',
        detail:
            'Payment authorized. Waiting for confirmation from the demo gateway.',
        tone: BillingPaymentStatusTone.info,
        action: BillingPaymentAction.sync,
        primaryActionLabel: 'Check Demo Payment Status',
        isSettled: false,
      );
    }

    if (sessionState == 'pending') {
      final expiresAt = latestSession.expiresAt;
      if (expiresAt != null && !expiresAt.isAfter(currentTime)) {
        return BillingPaymentStatus(
          key: 'expired',
          label: 'Expired',
          detail:
              'The last payment session expired. Start a new demo payment session.',
          tone: BillingPaymentStatusTone.warning,
          action: BillingPaymentAction.start,
          primaryActionLabel: 'Start New Demo Payment',
          isSettled: false,
        );
      }

      return BillingPaymentStatus(
        key: 'pending',
        label: 'Awaiting Payment',
        detail: expiresAt == null
            ? 'Payment session is ready. Continue checkout to complete payment.'
            : 'Payment session is ready until ${_dateTimeLabel(expiresAt)}.',
        tone: BillingPaymentStatusTone.warning,
        action: latestSession.supportsInAppDummyFlow
            ? BillingPaymentAction.resume
            : BillingPaymentAction.none,
        primaryActionLabel:
            latestSession.supportsInAppDummyFlow ? 'Resume Demo Payment' : '',
        isSettled: false,
      );
    }

    if (sessionState == 'expired') {
      return BillingPaymentStatus(
        key: 'expired',
        label: 'Expired',
        detail:
            'The last payment session expired. Start a new demo payment session.',
        tone: BillingPaymentStatusTone.warning,
        action: BillingPaymentAction.start,
        primaryActionLabel: 'Start New Demo Payment',
        isSettled: false,
      );
    }

    if (sessionState == 'failed') {
      return BillingPaymentStatus(
        key: 'failed',
        label: 'Failed',
        detail:
            'The last payment attempt failed. Start a new demo payment session.',
        tone: BillingPaymentStatusTone.danger,
        action: BillingPaymentAction.start,
        primaryActionLabel: 'Start New Demo Payment',
        isSettled: false,
      );
    }

    if (sessionState == 'cancelled' || sessionState == 'canceled') {
      return BillingPaymentStatus(
        key: 'cancelled',
        label: 'Cancelled',
        detail:
            'The last payment session was cancelled. Start a new demo payment session.',
        tone: BillingPaymentStatusTone.neutral,
        action: BillingPaymentAction.start,
        primaryActionLabel: 'Start New Demo Payment',
        isSettled: false,
      );
    }
  }

  if (_isPastDue(dueDate, currentTime)) {
    return BillingPaymentStatus(
      key: 'overdue',
      label: 'Overdue',
      detail: dueDate == null
          ? 'Payment is overdue.'
          : 'Payment is overdue since ${_dateLabel(dueDate)}.',
      tone: BillingPaymentStatusTone.danger,
      action: BillingPaymentAction.start,
      primaryActionLabel: 'Run Demo Payment',
      isSettled: false,
    );
  }

  return BillingPaymentStatus(
    key: 'unpaid',
    label: 'Unpaid',
    detail: dueDate == null
        ? 'Payment is still outstanding.'
        : 'Payment due on ${_dateLabel(dueDate)}.',
    tone: BillingPaymentStatusTone.neutral,
    action: BillingPaymentAction.start,
    primaryActionLabel: 'Run Demo Payment',
    isSettled: false,
  );
}

String _text(Object? raw, {String fallback = ''}) {
  final text = raw?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

String _normalizedText(Object? raw, {String fallback = ''}) {
  return _text(raw, fallback: fallback).toLowerCase();
}

DateTime? _dateFrom(Object? raw) {
  if (raw is Timestamp) {
    return raw.toDate();
  }
  if (raw is DateTime) {
    return raw;
  }
  return null;
}

bool _isPastDue(DateTime? dueDate, DateTime now) {
  if (dueDate == null) {
    return false;
  }
  final today = DateTime(now.year, now.month, now.day);
  final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
  return dueDay.isBefore(today);
}

String _dateLabel(DateTime value) {
  return DateFormat('d MMM yyyy').format(value);
}

String _dateTimeLabel(DateTime value) {
  return DateFormat('d MMM yyyy, h:mm a').format(value);
}
