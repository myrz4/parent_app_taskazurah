import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app_taskazurah/screens/billing_invoice_presenter.dart';
import 'package:parent_app_taskazurah/screens/billing_payment_status.dart';

void main() {
  test('family invoice presentation surfaces linked children clearly', () {
    final presentation = BillingInvoicePresentation.fromInvoice({
      'childIds': ['child-a', 'child-b'],
      'childNames': ['Aisyah', 'Adam'],
      'billingMeta': {
        'invoiceScope': 'family',
        'policyNotes': ['Registration stacked with monthly fee'],
        'managementReviewRecommended': true,
      },
    }, parentNameFallback: 'Parent Example');

    expect(presentation.isFamily, isTrue);
    expect(presentation.displayName, 'Family Invoice');
    expect(presentation.supportingLabel, 'Children covered: Aisyah, Adam');
    expect(presentation.managementReviewRecommended, isTrue);
    expect(
      presentation.policySummary,
      'Management review recommended',
    );
  });

  test('payment status resolves overdue unpaid invoices without a session', () {
    final status = billingResolvePaymentStatus(
      invoice: {
        'status': 'unpaid',
        'dueDate': DateTime(2026, 4, 1),
      },
      now: DateTime(2026, 4, 5),
    );

    expect(status.key, 'overdue');
    expect(status.label, 'Overdue');
    expect(status.isSettled, isFalse);
    expect(status.action, BillingPaymentAction.start);
  });

  test('processing session asks the user to sync payment state', () {
    final status = billingResolvePaymentStatus(
      invoice: {
        'status': 'unpaid',
        'dueDate': DateTime(2026, 4, 7),
      },
      latestSession: BillingLatestSession(
        sessionId: 'session-1',
        status: 'processing',
        sessionState: 'processing',
        provider: 'dummy',
        mode: 'dummy',
        providerMode: '',
        currency: 'MYR',
        amountSen: 70000,
        method: 'FPX',
        bank: 'Maybank2u',
        receiptNo: '',
        paymentIntentId: '',
        cardBrand: '',
        cardLast4: '',
        expiresAt: DateTime(2026, 4, 5, 23, 59),
        createdAt: DateTime(2026, 4, 5, 10, 0),
        completedAt: null,
        lastSyncedAt: null,
      ),
      now: DateTime(2026, 4, 5, 10, 5),
    );

    expect(status.key, 'processing');
    expect(status.action, BillingPaymentAction.sync);
    expect(status.primaryActionLabel, 'Check Payment Status');
  });

  test('pending stripe payment sheet session stays actionable', () {
    final status = billingResolvePaymentStatus(
      invoice: {
        'status': 'unpaid',
        'dueDate': DateTime(2026, 4, 7),
      },
      latestSession: BillingLatestSession(
        sessionId: 'stripe-session-1',
        status: 'pending',
        sessionState: 'pending',
        provider: 'stripe',
        mode: 'payment_sheet',
        providerMode: 'test',
        currency: 'MYR',
        amountSen: 70000,
        method: 'Stripe Demo',
        bank: '',
        receiptNo: '',
        paymentIntentId: 'pi_test_123',
        cardBrand: '',
        cardLast4: '',
        expiresAt: null,
        createdAt: DateTime(2026, 4, 5, 10, 0),
        completedAt: null,
        lastSyncedAt: null,
      ),
      now: DateTime(2026, 4, 5, 10, 5),
    );

    expect(status.key, 'pending');
    expect(status.action, BillingPaymentAction.start);
    expect(status.primaryActionLabel, 'Continue Payment');
  });
}
