class BillingInvoicePresentation {
  BillingInvoicePresentation({
    required this.isFamily,
    required this.scopeLabel,
    required this.displayName,
    required this.supportingLabel,
    required this.childNames,
    required this.policyNotes,
    required this.managementReviewRecommended,
    required this.policySummary,
  });

  final bool isFamily;
  final String scopeLabel;
  final String displayName;
  final String supportingLabel;
  final List<String> childNames;
  final List<String> policyNotes;
  final bool managementReviewRecommended;
  final String policySummary;

  factory BillingInvoicePresentation.fromInvoice(
    Map<String, dynamic> invoice, {
    String parentNameFallback = '',
  }) {
    final childNames = _childNames(invoice);
    final invoiceScope = _invoiceScope(invoice);
    final childIds = _stringList(invoice['childIds']);
    final policyNotes = _policyNotes(invoice);
    final managementReviewRecommended = _managementReviewRecommended(invoice);
    final isFamily =
        invoiceScope == 'family' || childNames.length > 1 || childIds.length > 1;

    final displayName = isFamily
        ? 'Family Invoice'
        : (childNames.isNotEmpty
              ? childNames.first
              : (parentNameFallback.isNotEmpty
                    ? parentNameFallback
                    : 'Invoice'));

        final supportingLabel = childNames.isEmpty
        ? (isFamily
          ? 'Covers all linked children'
          : (parentNameFallback.isNotEmpty
            ? 'Parent account: $parentNameFallback'
            : 'Single-child billing'))
        : (isFamily
          ? 'Children covered: ${childNames.join(', ')}'
          : 'Child covered: ${childNames.first}');

    return BillingInvoicePresentation(
      isFamily: isFamily,
      scopeLabel: isFamily ? 'Family billing' : 'Single-child billing',
      displayName: displayName,
      supportingLabel: supportingLabel,
      childNames: childNames,
      policyNotes: policyNotes,
      managementReviewRecommended: managementReviewRecommended,
      policySummary: managementReviewRecommended
          ? 'Management review recommended'
          : (policyNotes.isNotEmpty ? policyNotes.first : ''),
    );
  }

  static String _invoiceScope(Map<String, dynamic> invoice) {
    final billingMeta = invoice['billingMeta'];
    if (billingMeta is Map) {
      final raw = billingMeta['invoiceScope'];
      if (raw != null) {
        return raw.toString().trim().toLowerCase();
      }
    }

    final raw = invoice['invoiceScope'];
    return raw == null ? '' : raw.toString().trim().toLowerCase();
  }

  static List<String> _childNames(Map<String, dynamic> invoice) {
    final values = <String>[];
    values.addAll(_stringList(invoice['childNames']));

    final singleChildName = (invoice['childName'] ?? '').toString().trim();
    if (singleChildName.isNotEmpty) {
      values.add(singleChildName);
    }

    final deduped = <String>[];
    for (final value in values) {
      if (!deduped.contains(value)) {
        deduped.add(value);
      }
    }
    return deduped;
  }

  static List<String> _stringList(Object? raw) {
    if (raw is! List) {
      return const [];
    }

    final values = <String>[];
    for (final item in raw) {
      final text = item?.toString().trim() ?? '';
      if (text.isNotEmpty) {
        values.add(text);
      }
    }
    return values;
  }

  static List<String> _policyNotes(Map<String, dynamic> invoice) {
    final billingMeta = invoice['billingMeta'];
    if (billingMeta is Map) {
      return _stringList(billingMeta['policyNotes']);
    }
    return const [];
  }

  static bool _managementReviewRecommended(Map<String, dynamic> invoice) {
    final billingMeta = invoice['billingMeta'];
    if (billingMeta is Map) {
      return billingMeta['managementReviewRecommended'] == true;
    }
    return false;
  }
}