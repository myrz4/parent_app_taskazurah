import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class RedirectCheckoutPage extends StatefulWidget {
  final String parentId;
  final String invoiceId;
  final String sessionId;
  final int amountSen;
  final String currency;
  final String provider;
  final String checkoutUrl;

  const RedirectCheckoutPage({
    super.key,
    required this.parentId,
    required this.invoiceId,
    required this.sessionId,
    required this.amountSen,
    required this.currency,
    required this.provider,
    required this.checkoutUrl,
  });

  static const Color primary = Color(0xFF7ACB9E);

  @override
  State<RedirectCheckoutPage> createState() => _RedirectCheckoutPageState();
}

class _RedirectCheckoutPageState extends State<RedirectCheckoutPage> {
  static final _money = NumberFormat.currency(locale: 'ms_MY', symbol: 'RM');

  bool _isLaunching = false;
  bool _isChecking = false;
  String? _error;
  String _status = 'pending';

  String _formatSen(int sen) => _money.format(sen / 100.0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openCheckout();
    });
  }

  Future<void> _openCheckout() async {
    setState(() {
      _error = null;
      _isLaunching = true;
    });

    try {
      final uri = Uri.tryParse(widget.checkoutUrl);
      if (uri == null) {
        throw Exception('Invalid checkout URL');
      }
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        throw Exception('Unable to open payment page');
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to open payment page. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLaunching = false;
        });
      }
    }
  }

  Future<void> _checkPaymentStatus() async {
    setState(() {
      _error = null;
      _isChecking = true;
    });

    try {
      final fn = FirebaseFunctions.instanceFor(region: 'asia-southeast1')
          .httpsCallable('billingSyncCheckoutSession');

      final res = await fn.call({
        'parentId': widget.parentId,
        'invoiceId': widget.invoiceId,
        'sessionId': widget.sessionId,
      });

      final data = (res.data as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      if (data['ok'] != true) {
        setState(() {
          _error = 'Payment check failed (${data['reason'] ?? 'unknown'}).';
          _status = 'error';
        });
        return;
      }

      final status = (data['status'] ?? 'pending').toString().toLowerCase();
      final paid = data['paid'] == true || status == 'succeeded';
      setState(() {
        _status = status;
      });

      if (paid && mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _error = 'Unable to verify payment yet. Please try again.';
        _status = 'error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? Colors.grey[900] : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF111714);
    final muted = isDark ? Colors.grey[400] : Colors.grey[600];

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: (_isLaunching || _isChecking) ? null : () => Navigator.maybePop(context),
                  icon: Icon(Icons.arrow_back, color: textColor),
                ),
                const Expanded(
                  child: Center(
                    child: Text(
                      'Secure Payment Checkout',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 40),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Color.fromRGBO(0, 0, 0, 0.06),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Provider', style: TextStyle(color: muted)),
                  const SizedBox(height: 4),
                  Text(widget.provider.toUpperCase(), style: TextStyle(color: textColor, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Text('Amount', style: TextStyle(color: muted)),
                  const SizedBox(height: 4),
                  Text(
                    _formatSen(widget.amountSen),
                    style: TextStyle(color: textColor, fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Status: ${_status.toUpperCase()}',
                    style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Complete the payment in the external browser, then return here and tap Check Payment Status.',
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isLaunching ? null : _openCheckout,
                style: ElevatedButton.styleFrom(
                  backgroundColor: RedirectCheckoutPage.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLaunching
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Open Payment Page Again',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: _isChecking ? null : _checkPaymentStatus,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: RedirectCheckoutPage.primary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isChecking
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: RedirectCheckoutPage.primary),
                      )
                    : const Text(
                        'Check Payment Status',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: RedirectCheckoutPage.primary),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}