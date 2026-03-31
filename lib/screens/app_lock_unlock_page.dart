import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/app_lock_service.dart';

class AppLockUnlockPage extends StatefulWidget {
  const AppLockUnlockPage({super.key});

  @override
  State<AppLockUnlockPage> createState() => _AppLockUnlockPageState();

  static const Color primary = Color(0xFF7ACB9E);
  static const Color background = Color(0xFFF6F8F7);
}

class _AppLockUnlockPageState extends State<AppLockUnlockPage> {
  final _svc = AppLockService();
  final _pinController = TextEditingController();

  bool _loading = true;
  bool _biometricsAvailable = false;
  bool _useBiometrics = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final available = await _svc.biometricsAvailable();
    final useBio = await _svc.useBiometrics();

    if (!mounted) return;
    setState(() {
      _biometricsAvailable = available;
      _useBiometrics = available && useBio;
      _loading = false;
    });

    // Attempt biometric unlock first if enabled.
    if (_useBiometrics) {
      await _unlockWithBiometrics();
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _unlockWithBiometrics() async {
    final ok = await _svc.authenticateWithBiometrics(reason: 'Unlock Parent App');
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      _snack('Biometric unlock failed. Use PIN instead.');
    }
  }

  Future<void> _unlockWithPin() async {
    final pin = _pinController.text.trim();
    if (pin.length < 4 || pin.length > 6 || !RegExp(r'^[0-9]+$').hasMatch(pin)) {
      _snack('PIN must be 4–6 digits');
      return;
    }

    final ok = await _svc.verifyPin(pin);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      _snack('Wrong PIN');
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppLockUnlockPage.background,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: AppLockUnlockPage.background,
          elevation: 0,
          title: Text('App Locked', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          centerTitle: true,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppLockUnlockPage.primary))
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock, size: 84, color: AppLockUnlockPage.primary),
                    const SizedBox(height: 12),
                    Text(
                      'Unlock to continue',
                      style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 24),
                    if (_biometricsAvailable)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _unlockWithBiometrics,
                          icon: const Icon(Icons.fingerprint),
                          label: const Text('Unlock with Biometrics'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppLockUnlockPage.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                    if (_biometricsAvailable) const SizedBox(height: 16),
                    TextField(
                      controller: _pinController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      obscureText: true,
                      decoration: InputDecoration(
                        counterText: '',
                        labelText: 'PIN (4–6 digits)',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _unlockWithPin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2F5F4A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Unlock with PIN'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _logout,
                      child: const Text('Logout'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
