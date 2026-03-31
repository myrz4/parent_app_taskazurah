import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/app_lock_service.dart';

class AppLockSettingsPage extends StatefulWidget {
  const AppLockSettingsPage({super.key});

  @override
  State<AppLockSettingsPage> createState() => _AppLockSettingsPageState();

  static const Color primary = Color(0xFF7ACB9E);
  static const Color background = Color(0xFFF6F8F7);
}

class _AppLockSettingsPageState extends State<AppLockSettingsPage> {
  final _svc = AppLockService();

  bool _loading = true;
  bool _hasPin = false;
  bool _biometricsAvailable = false;
  bool _useBiometrics = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await _svc.isEnabled();
    final hasPin = await _svc.hasPin();
    final available = await _svc.biometricsAvailable();
    final useBio = await _svc.useBiometrics();

    if (!mounted) return;
    setState(() {
      _hasPin = hasPin;
      _biometricsAvailable = available;
      _useBiometrics = available && useBio;
      _loading = false;
    });

    // If user previously disabled App Lock but still has a PIN, keep UI consistent.
    // (We intentionally avoid calling disable() anywhere going forward.)
    if (enabled == false && hasPin && mounted) {
      _snack('PIN is mandatory and cannot be disabled.');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _digitsOnly(String input) => input.replaceAll(RegExp(r'[^0-9]'), '');

  String _emailFromPhoneE164(String phoneE164) {
    final digits = _digitsOnly(phoneE164);
    return 'p_$digits@taskazurah.local';
  }

  String? _phoneFromEmail(String? email) {
    if (email == null) return null;
    final e = email.trim().toLowerCase();
    if (!e.startsWith('p_') || !e.endsWith('@taskazurah.local')) return null;
    final at = e.indexOf('@');
    if (at <= 2) return null;
    final digits = e.substring(2, at);
    if (digits.isEmpty) return null;
    return digits.startsWith('60') ? '+$digits' : digits;
  }

  Future<void> _syncFirebasePin(String newPin) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final phoneE164 = user.phoneNumber ?? _phoneFromEmail(user.email);
    if (phoneE164 == null || phoneE164.isEmpty) {
      _snack('Unable to link PIN to account. Please login using OTP first.');
      return;
    }

    final email = _emailFromPhoneE164(phoneE164);

    try {
      final hasPasswordProvider = user.providerData.any((p) => p.providerId == 'password');
      if (!hasPasswordProvider) {
        await user.linkWithCredential(EmailAuthProvider.credential(email: email, password: newPin));
      } else {
        // Updates the email/password PIN login password.
        await user.updatePassword(newPin);
      }
      _snack('PIN linked for login successfully');
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        _snack('Please login again (OTP) then change PIN.');
        return;
      }
      if (e.code == 'credential-already-in-use' || e.code == 'email-already-in-use') {
        _snack('This PIN login email is already used. Delete the old PIN user in Firebase Auth then set PIN again.');
        return;
      }
      _snack(e.message ?? 'Failed to link PIN for login');
    } catch (_) {
      _snack('Failed to link PIN for login');
    }
  }

  Future<bool> _showCreatePinDialog() async {
    final pin1 = TextEditingController();
    final pin2 = TextEditingController();
    bool enableBio = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text('Enable App Lock', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pin1,
                keyboardType: TextInputType.number,
                maxLength: 6,
                obscureText: true,
                decoration: const InputDecoration(counterText: '', labelText: 'Create PIN (4–6 digits)'),
              ),
              TextField(
                controller: pin2,
                keyboardType: TextInputType.number,
                maxLength: 6,
                obscureText: true,
                decoration: const InputDecoration(counterText: '', labelText: 'Confirm PIN'),
              ),
              if (_biometricsAvailable)
                StatefulBuilder(
                  builder: (context, setState) {
                    return SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Use biometrics'),
                      value: enableBio,
                      activeThumbColor: AppLockSettingsPage.primary,
                      onChanged: (v) => setState(() => enableBio = v),
                    );
                  },
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final a = pin1.text.trim();
                final b = pin2.text.trim();
                if (a.length < 4 || a.length > 6 || !RegExp(r'^[0-9]+$').hasMatch(a)) {
                  _snack('PIN must be 4–6 digits');
                  return;
                }
                if (a != b) {
                  _snack('PIN does not match');
                  return;
                }

                await _svc.enableWithPin(pin: a, enableBiometrics: enableBio);
                await _syncFirebasePin(a);
                if (!context.mounted) return;
                Navigator.of(context).pop(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppLockSettingsPage.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Enable'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      await _load();
      _snack('App Lock enabled');
      return true;
    }

    return false;
  }

  Future<void> _changePin() async {
    final current = TextEditingController();
    final next1 = TextEditingController();
    final next2 = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text('Change PIN', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: current,
                keyboardType: TextInputType.number,
                maxLength: 6,
                obscureText: true,
                decoration: const InputDecoration(counterText: '', labelText: 'Current PIN'),
              ),
              TextField(
                controller: next1,
                keyboardType: TextInputType.number,
                maxLength: 6,
                obscureText: true,
                decoration: const InputDecoration(counterText: '', labelText: 'New PIN (4–6 digits)'),
              ),
              TextField(
                controller: next2,
                keyboardType: TextInputType.number,
                maxLength: 6,
                obscureText: true,
                decoration: const InputDecoration(counterText: '', labelText: 'Confirm New PIN'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final c = current.text.trim();
                final a = next1.text.trim();
                final b = next2.text.trim();

                if (a.length < 4 || a.length > 6 || !RegExp(r'^[0-9]+$').hasMatch(a)) {
                  _snack('New PIN must be 4–6 digits');
                  return;
                }
                if (a != b) {
                  _snack('PIN does not match');
                  return;
                }

                final changed = await _svc.changePin(currentPin: c, newPin: a);
                if (!context.mounted) return;
                if (!changed) {
                  _snack('Current PIN is wrong');
                  return;
                }

                final navigator = Navigator.of(context);
                await _syncFirebasePin(a);
                if (!context.mounted) return;
                navigator.pop(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppLockSettingsPage.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (ok == true) {
      _snack('PIN updated');
    }
  }

  Future<void> _toggleBiometrics(bool v) async {
    await _svc.setUseBiometrics(v);
    await _load();
    _snack(v ? 'Biometrics enabled' : 'Biometrics disabled');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppLockSettingsPage.background,
      appBar: AppBar(
        backgroundColor: AppLockSettingsPage.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF2F5F4A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('App Lock', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppLockSettingsPage.primary))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.pin),
                          title: Text(
                            _hasPin ? 'Change PIN' : 'Create PIN',
                            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            _hasPin ? 'PIN is set' : 'No PIN set',
                            style: GoogleFonts.plusJakartaSans(fontSize: 13),
                          ),
                          onTap: _hasPin ? _changePin : _showCreatePinDialog,
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          title: Text('Use biometrics', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            _biometricsAvailable
                                ? 'Use fingerprint/face to unlock.'
                                : 'Biometrics not available on this device.',
                            style: GoogleFonts.plusJakartaSans(fontSize: 13),
                          ),
                          value: _useBiometrics,
                          activeThumbColor: AppLockSettingsPage.primary,
                          onChanged: _biometricsAvailable ? _toggleBiometrics : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
