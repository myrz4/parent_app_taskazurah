import 'package:cloud_functions/cloud_functions.dart';

class BillingInvoiceStatusRepair {
  static final Set<String> _attemptedKeys = <String>{};

  static Future<void> maybeRepair({
    required String parentId,
    required String invoiceId,
    required Map<String, dynamic> invoice,
  }) async {
    final normalizedParentId = parentId.trim();
    final normalizedInvoiceId = invoiceId.trim();
    final status = (invoice['status'] ?? 'unpaid').toString().trim().toLowerCase();
    final period = (invoice['period'] ?? '').toString().trim();
    final childIds = _childIds(invoice);

    if (normalizedParentId.isEmpty ||
        normalizedInvoiceId.isEmpty ||
        status == 'paid' ||
        status == 'void' ||
        period.isEmpty ||
        childIds.isEmpty) {
      return;
    }

    final key = '$normalizedParentId::$normalizedInvoiceId::$period::${childIds.join('|')}';
    if (_attemptedKeys.contains(key)) {
      return;
    }
    _attemptedKeys.add(key);

    try {
      final fn = FirebaseFunctions.instanceFor(region: 'asia-southeast1')
          .httpsCallable('billingRepairInvoiceStatus');
      await fn.call({
        'parentId': normalizedParentId,
        'invoiceId': normalizedInvoiceId,
      });
    } catch (_) {
      // Best-effort repair only. The UI will continue showing the current snapshot.
    }
  }

  static List<String> _childIds(Map<String, dynamic> invoice) {
    final values = <String>[];
    final rawChildIds = invoice['childIds'];
    if (rawChildIds is List) {
      for (final item in rawChildIds) {
        final text = item?.toString().trim() ?? '';
        if (text.isNotEmpty && !values.contains(text)) {
          values.add(text);
        }
      }
    }

    final singleChildId = (invoice['childId'] ?? '').toString().trim();
    if (singleChildId.isNotEmpty && !values.contains(singleChildId)) {
      values.add(singleChildId);
    }

    values.sort();
    return values;
  }
}