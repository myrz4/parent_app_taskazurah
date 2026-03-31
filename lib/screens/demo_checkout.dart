import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

enum _DemoCheckoutStage {
  bank,
  credentials,
  otp,
  processing,
}

class DemoCheckoutPage extends StatefulWidget {
  final String parentId;
  final String invoiceId;
  final String sessionId;
  final int amountSen;
  final String currency;

  const DemoCheckoutPage({
    super.key,
    required this.parentId,
    required this.invoiceId,
    required this.sessionId,
    required this.amountSen,
    required this.currency,
  });

  static const Color primary = Color(0xFF7ACB9E);

  @override
  State<DemoCheckoutPage> createState() => _DemoCheckoutPageState();
}

class _DemoCheckoutPageState extends State<DemoCheckoutPage> {
  static final _money = NumberFormat.currency(locale: 'ms_MY', symbol: 'RM');

  final List<String> _banks = const [
    'Maybank2u',
    'CIMB Clicks',
    'Bank Islam',
    'RHB Now',
    'Public Bank',
    'Hong Leong Bank',
  ];

  String? _selectedBank;
  final _bankUserIdController = TextEditingController();
  final _bankPasswordController = TextEditingController();
  final _otpController = TextEditingController();

  _DemoCheckoutStage _stage = _DemoCheckoutStage.bank;
  bool _isPaying = false;
  String? _error;

  String _formatSen(int sen) {
    final v = (sen / 100.0);
    return _money.format(v);
  }

  @override
  void dispose() {
    _bankUserIdController.dispose();
    _bankPasswordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _syncPaymentStatus() async {
    final fn = FirebaseFunctions.instanceFor(region: 'asia-southeast1')
        .httpsCallable('billingSyncCheckoutSession');
    final res = await fn.call({
      'parentId': widget.parentId,
      'invoiceId': widget.invoiceId,
      'sessionId': widget.sessionId,
    });
    return (res.data as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
  }

  Future<bool> _pollUntilSettled() async {
    for (var attempt = 0; attempt < 8; attempt++) {
      final data = await _syncPaymentStatus();
      final status = (data['status'] ?? 'pending').toString().toLowerCase();
      final paid = data['paid'] == true || status == 'succeeded';
      if (paid) return true;
      if (status == 'expired' || status == 'failed' || status == 'cancelled') {
        setState(() {
          _error = 'Payment $status. Please start again.';
          _stage = _DemoCheckoutStage.bank;
        });
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    return false;
  }

  Future<void> _submitPayment() async {
    setState(() {
      _error = null;
      _isPaying = true;
      _stage = _DemoCheckoutStage.processing;
    });

    try {
      final fn = FirebaseFunctions.instanceFor(region: 'asia-southeast1')
          .httpsCallable('billingCompleteCheckoutSession');

      final res = await fn.call({
        'parentId': widget.parentId,
        'invoiceId': widget.invoiceId,
        'sessionId': widget.sessionId,
        'method': 'FPX',
        'bank': _selectedBank,
      });

      final data = (res.data as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      final ok = data['ok'] == true;
      if (!ok) {
        setState(() {
          _error = 'Payment failed (${data['reason'] ?? 'unknown'}).';
          _stage = _DemoCheckoutStage.bank;
          _isPaying = false;
        });
        return;
      }

      final settled = await _pollUntilSettled();
      if (!mounted) return;
      if (settled) {
        Navigator.of(context).pop(true);
        return;
      }

      setState(() {
        _error ??= 'Payment is still processing. Check status again in a moment.';
      });
    } catch (e) {
      setState(() {
        _error = 'Payment failed. Please try again.';
        _stage = _DemoCheckoutStage.bank;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isPaying = false;
        });
      }
    }
  }

  Future<void> _handlePrimaryAction() async {
    if (_stage == _DemoCheckoutStage.bank) {
      if (_selectedBank == null || _selectedBank!.trim().isEmpty) {
        setState(() => _error = 'Select a bank first.');
        return;
      }
      setState(() {
        _error = null;
        _stage = _DemoCheckoutStage.credentials;
      });
      return;
    }

    if (_stage == _DemoCheckoutStage.credentials) {
      if (_bankUserIdController.text.trim().isEmpty || _bankPasswordController.text.isEmpty) {
        setState(() => _error = 'Enter your simulated bank login details.');
        return;
      }
      setState(() {
        _error = null;
        _stage = _DemoCheckoutStage.otp;
      });
      return;
    }

    if (_stage == _DemoCheckoutStage.otp) {
      if (_otpController.text.trim().length != 6) {
        setState(() => _error = 'Enter the 6-digit TAC code.');
        return;
      }
      await _submitPayment();
      return;
    }

    setState(() {
      _error = null;
      _isPaying = true;
    });
    try {
      final settled = await _pollUntilSettled();
      if (!mounted) return;
      if (settled) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _error ??= 'Payment is still processing. Please try again shortly.';
      });
    } catch (e) {
      setState(() {
        _error = 'Unable to verify payment yet. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isPaying = false;
        });
      }
    }
  }

  String _primaryLabel() {
    switch (_stage) {
      case _DemoCheckoutStage.bank:
        return 'Continue to Bank Login';
      case _DemoCheckoutStage.credentials:
        return 'Request TAC';
      case _DemoCheckoutStage.otp:
        return 'Authorize Payment';
      case _DemoCheckoutStage.processing:
        return 'Check Payment Status';
    }
  }

  Widget _buildStageCard({
    required Color? cardBg,
    required Color textColor,
    required Color muted,
  }) {
    if (_stage == _DemoCheckoutStage.bank) {
      return Container(
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
          children: _banks
              .map(
                (b) {
                  final isSelected = _selectedBank == b;
                  return ListTile(
                    enabled: !_isPaying,
                    onTap: _isPaying ? null : () => setState(() => _selectedBank = b),
                    leading: Icon(
                      isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: isSelected ? DemoCheckoutPage.primary : muted,
                    ),
                    title: Text(b, style: TextStyle(color: textColor)),
                    subtitle: const Text('FPX online banking'),
                  );
                },
              )
              .toList(),
        ),
      );
    }

    if (_stage == _DemoCheckoutStage.credentials) {
      return Container(
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
            Text('$_selectedBank Secure Login', style: TextStyle(color: textColor, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: _bankUserIdController,
              enabled: !_isPaying,
              decoration: const InputDecoration(labelText: 'User ID'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bankPasswordController,
              enabled: !_isPaying,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 12),
            Text(
              'This simulator does not store real credentials. Use any values to continue.',
              style: TextStyle(color: muted, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_stage == _DemoCheckoutStage.otp) {
      return Container(
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
            Text('Transaction Authorization Code', style: TextStyle(color: textColor, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text(
              'Enter any 6-digit TAC to simulate the final bank authorization step.',
              style: TextStyle(color: muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _otpController,
              enabled: !_isPaying,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 6,
              decoration: const InputDecoration(labelText: '6-digit TAC'),
            ),
          ],
        ),
      );
    }

    return Container(
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
          Text('Payment Processing', style: TextStyle(color: textColor, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: DemoCheckoutPage.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Your simulated bank authorization was submitted. Settlement now follows the same async session pattern as a real provider.',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color cardBg = isDark ? Colors.grey.shade900 : Colors.white;
    final Color textColor = isDark ? Colors.white : const Color(0xFF111714);
    final Color muted = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: _isPaying ? null : () => Navigator.maybePop(context),
                  icon: Icon(Icons.arrow_back, color: textColor),
                ),
                const Expanded(
                  child: Center(
                    child: Text(
                      'Secure Payment Simulator',
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
                  Text('Amount', style: TextStyle(color: muted)),
                  const SizedBox(height: 6),
                  Text(
                    _formatSen(widget.amountSen),
                    style: TextStyle(
                      color: textColor,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Dummy provider only. The checkout steps and async settlement are simulated to match a future real gateway flow.',
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Invoice ${widget.invoiceId}  •  Session ${widget.sessionId}',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Text(
              'Payment Flow',
              style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),

            Text(
              _stage == _DemoCheckoutStage.bank
                  ? '1. Select bank'
                  : _stage == _DemoCheckoutStage.credentials
                      ? '2. Simulate bank login'
                      : _stage == _DemoCheckoutStage.otp
                          ? '3. Confirm TAC'
                          : '4. Wait for settlement',
              style: TextStyle(color: muted, fontSize: 13),
            ),
            const SizedBox(height: 8),

            _buildStageCard(cardBg: cardBg, textColor: textColor, muted: muted),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
            ],

            const SizedBox(height: 16),

            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isPaying ? null : _handlePrimaryAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: DemoCheckoutPage.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 6,
                ),
                child: _isPaying
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        _primaryLabel(),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white),
                      ),
              ),
            ),

            if (_stage != _DemoCheckoutStage.bank) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: _isPaying
                      ? null
                      : () {
                          setState(() {
                            _error = null;
                            if (_stage == _DemoCheckoutStage.credentials) {
                              _stage = _DemoCheckoutStage.bank;
                            } else if (_stage == _DemoCheckoutStage.otp) {
                              _stage = _DemoCheckoutStage.credentials;
                            } else {
                              _stage = _DemoCheckoutStage.otp;
                            }
                          });
                        },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: DemoCheckoutPage.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'Back',
                    style: TextStyle(fontWeight: FontWeight.w700, color: DemoCheckoutPage.primary),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}