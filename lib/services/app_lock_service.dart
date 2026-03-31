import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class AppLockService {
  static const _storage = FlutterSecureStorage();
  static const _kEnabled = 'app_lock_enabled';
  static const _kPinHash = 'app_lock_pin_hash_sha256';
  static const _kUseBiometrics = 'app_lock_use_biometrics';

  static String _hashPin(String pin) {
    final bytes = utf8.encode(pin);
    return sha256.convert(bytes).toString();
  }

  Future<bool> isEnabled() async {
    final v = await _storage.read(key: _kEnabled);
    return v == 'true';
  }

  Future<bool> hasPin() async {
    final v = await _storage.read(key: _kPinHash);
    return v != null && v.isNotEmpty;
  }

  Future<bool> useBiometrics() async {
    final v = await _storage.read(key: _kUseBiometrics);
    return v == 'true';
  }

  Future<void> setUseBiometrics(bool v) async {
    await _storage.write(key: _kUseBiometrics, value: v ? 'true' : 'false');
  }

  Future<void> enableWithPin({required String pin, bool enableBiometrics = false}) async {
    await _storage.write(key: _kPinHash, value: _hashPin(pin));
    await _storage.write(key: _kEnabled, value: 'true');
    await _storage.write(key: _kUseBiometrics, value: enableBiometrics ? 'true' : 'false');
  }

  Future<void> disable() async {
    await _storage.write(key: _kEnabled, value: 'false');
    await _storage.write(key: _kUseBiometrics, value: 'false');
  }

  Future<bool> verifyPin(String pin) async {
    final stored = await _storage.read(key: _kPinHash);
    if (stored == null || stored.isEmpty) return false;
    return stored == _hashPin(pin);
  }

  Future<bool> changePin({required String currentPin, required String newPin}) async {
    final ok = await verifyPin(currentPin);
    if (!ok) return false;
    await _storage.write(key: _kPinHash, value: _hashPin(newPin));
    return true;
  }

  Future<bool> biometricsAvailable() async {
    final auth = LocalAuthentication();
    final canCheck = await auth.canCheckBiometrics;
    final isSupported = await auth.isDeviceSupported();
    return canCheck && isSupported;
  }

  Future<bool> authenticateWithBiometrics({String reason = 'Unlock Taska Zurah'}) async {
    final auth = LocalAuthentication();
    try {
      return await auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
