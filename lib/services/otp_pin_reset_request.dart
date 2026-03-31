import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class OtpPinResetRequest {
  static const _storage = FlutterSecureStorage();
  static const _kPendingOtpPhoneE164 = 'pending_otp_phone_e164';
  static const Duration _ttl = Duration(minutes: 2);

  /// Call this immediately BEFORE starting OTP sign-in.
  /// (We store by phone so AuthGate can reliably detect it without a uid race.)
  static Future<void> markPendingForPhone({required String phoneE164}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _storage.write(key: _kPendingOtpPhoneE164, value: '$phoneE164|$now');
  }

  /// Clears pending marker (best-effort).
  static Future<void> clear() async {
    await _storage.delete(key: _kPendingOtpPhoneE164);
  }

  /// Returns true once (and clears) if the pending phone matches the current user.
  static Future<bool> consumeIfMatchesPhone({required String phoneE164}) async {
    final pending = await _storage.read(key: _kPendingOtpPhoneE164);
    if (pending == null || pending.isEmpty) return false;

    final parts = pending.split('|');
    final pendingPhone = parts.isNotEmpty ? parts.first : '';
    final ts = (parts.length >= 2) ? int.tryParse(parts[1]) : null;

    // Backward compat: if older value had no timestamp.
    if (pendingPhone == phoneE164 && ts == null) {
      await clear();
      return true;
    }

    if (pendingPhone != phoneE164 || ts == null) return false;

    final ageMs = DateTime.now().millisecondsSinceEpoch - ts;
    if (ageMs < 0 || ageMs > _ttl.inMilliseconds) {
      await clear();
      return false;
    }

    await clear();
    return true;
  }
}
