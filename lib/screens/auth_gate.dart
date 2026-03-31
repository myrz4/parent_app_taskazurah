import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'login_page.dart';
import '../services/otp_pin_reset_request.dart';

// Internal dialog return values.
// (Avoid signing out while the dialog is still mounted.)
enum _PinDialogResult {
  saved,
  logout,
  mustUsePinLogin,
}

class ParentAuthGate extends StatelessWidget {
  const ParentAuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _GateLoadingScaffold();
        }

        final user = snapshot.data;
        if (user == null) return const LoginPage();

        return _ParentBootstrapper(user: user);
      },
    );
  }
}

class _GateLoadingScaffold extends StatelessWidget {
  const _GateLoadingScaffold();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(
          height: 28,
          width: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}

class _ParentBootstrapper extends StatefulWidget {
  const _ParentBootstrapper({required this.user});

  final User user;

  @override
  State<_ParentBootstrapper> createState() => _ParentBootstrapperState();
}

class _ParentBootstrapperState extends State<_ParentBootstrapper> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrap();
    });
  }

  Future<void> _bootstrap() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final phone = user.phoneNumber;
      if (phone != null && phone.isNotEmpty) {
        // IMPORTANT:
        // A parent account can have BOTH phone + password providers.
        // We only want to show Reset PIN when the user has just logged in via OTP.
        final shouldForceReset = await OtpPinResetRequest.consumeIfMatchesPhone(phoneE164: phone);
        if (shouldForceReset) {
          final ok = await _forceResetPinForOtpSession(phoneE164: phone);
          if (!ok) return;
          // Let the dialog route fully dispose before we navigate.
          await Future<void>.delayed(Duration.zero);
        }
        await _completeLoginAfterAuth(rawPhone: phone, phoneE164: phone);
        return;
      }

      final derived = _phonesFromParentEmail(user.email);
      if (derived.isNotEmpty) {
        await _completeLoginAfterCandidates(derived);
        return;
      }

      // If using real email, try mapping by email field.
      final email = user.email?.trim();
      if (email != null && email.isNotEmpty) {
        final q = await FirebaseFirestore.instance
            .collection('parents')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();

        if (q.docs.isEmpty) {
          await _failAndSignOut('Email not registered. Contact admin.');
          return;
        }

        final parentDoc = q.docs.first;
        final data = parentDoc.data();

        final parentId = parentDoc.id;
        final parentName = data['parentName'] ?? 'Parent';
        final childName = data['childName'] ?? 'Anak';

        await _saveParentFcmToken(parentId);

        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed(
          '/dashboard',
          arguments: {
            'parentId': parentId,
            'parentName': parentName,
            'childName': childName,
          },
        );
        return;
      }

      await _failAndSignOut('Unable to restore session. Please login again.');
    } on FirebaseException catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('ParentAuthGate bootstrap FirebaseException: ${e.code} ${e.message}');
      }
      final msg = (e.code == 'permission-denied')
          ? 'Permission denied. Please login again.'
          : 'Failed to auto-login. Please login again.';
      await _failAndSignOut(msg);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('ParentAuthGate bootstrap error: $e');
      }
      await _failAndSignOut('Failed to auto-login. Please login again.');
    }
  }

  Future<void> _failAndSignOut(String message) async {
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await Future.delayed(const Duration(milliseconds: 350));
    }
    await FirebaseAuth.instance.signOut();
  }

  Future<bool> _forceResetPinForOtpSession({required String phoneE164}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final gateContext = context;

    // OTP session → require PIN setup/reset BEFORE navigating away from the gate.
    // This avoids the previous race where LoginPage showed the dialog but the gate
    // immediately replaced the UI after authStateChanges().
    final hasPasswordProvider = user.providerData.any((p) => p.providerId == 'password');
    final title = hasPasswordProvider ? 'Reset PIN' : 'Create PIN';
    final subtitle = hasPasswordProvider
        ? 'You logged in using OTP. Set a new PIN to login next time.'
        : 'PIN is mandatory. Create a PIN to login next time.';

    final pin1 = TextEditingController();
    final pin2 = TextEditingController();

    final result = await showDialog<_PinDialogResult>(
      context: gateContext,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(subtitle),
              const SizedBox(height: 12),
              TextField(
                controller: pin1,
                keyboardType: TextInputType.number,
                maxLength: 6,
                obscureText: true,
                decoration: const InputDecoration(counterText: '', labelText: 'PIN (6 digits)'),
              ),
              TextField(
                controller: pin2,
                keyboardType: TextInputType.number,
                maxLength: 6,
                obscureText: true,
                decoration: const InputDecoration(counterText: '', labelText: 'Confirm PIN'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(_PinDialogResult.logout),
              child: const Text('Logout'),
            ),
            ElevatedButton(
              onPressed: () async {
                final a = pin1.text.trim();
                final b = pin2.text.trim();
                if (a.length != 6 || !RegExp(r'^[0-9]{6}$').hasMatch(a)) {
                  ScaffoldMessenger.of(gateContext).showSnackBar(
                    const SnackBar(content: Text('PIN must be exactly 6 digits')),
                  );
                  return;
                }
                if (a != b) {
                  ScaffoldMessenger.of(gateContext).showSnackBar(
                    const SnackBar(content: Text('PIN does not match')),
                  );
                  return;
                }

                try {
                  final email = _derivedParentEmailFromPhone(phoneE164);

                  if (!hasPasswordProvider) {
                    await user.linkWithCredential(
                      EmailAuthProvider.credential(email: email, password: a),
                    );
                  } else {
                    await user.updatePassword(a);
                  }

                  if (!dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop(_PinDialogResult.saved);
                } on FirebaseAuthException catch (e) {
                  // If a derived-email already exists, we cannot link during OTP.
                  // Enforce the UX requirement: cannot proceed without a valid PIN setup.
                  if (e.code == 'email-already-in-use' || e.code == 'credential-already-in-use') {
                    if (!dialogContext.mounted) return;
                    Navigator.of(dialogContext).pop(_PinDialogResult.mustUsePinLogin);
                    return;
                  }
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(gateContext).showSnackBar(
                    SnackBar(content: Text(e.message ?? 'Failed to save PIN')),
                  );
                } catch (_) {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(gateContext).showSnackBar(
                    const SnackBar(content: Text('Failed to save PIN')),
                  );
                }
              },
              child: const Text('Save PIN'),
            ),
          ],
        );
      },
    );

    pin1.dispose();
    pin2.dispose();

    switch (result) {
      case _PinDialogResult.saved:
        return true;
      case _PinDialogResult.mustUsePinLogin:
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PIN already exists for this number. Please login using PIN.')),
          );
          await Future.delayed(const Duration(milliseconds: 300));
        }
        await FirebaseAuth.instance.signOut();
        return false;
      case _PinDialogResult.logout:
      default:
        await FirebaseAuth.instance.signOut();
        return false;
    }
  }

  String _derivedParentEmailFromPhone(String phoneE164) {
    final local = _phoneLocalDigitsFromAny(phoneE164);
    return 'p_$local@taskazurah.local';
  }

  String _digitsOnly(String input) => input.replaceAll(RegExp(r'[^0-9]'), '');

  String _myTail(String phoneAny) {
    var d = _digitsOnly(phoneAny);
    if (d.isEmpty) return '';
    if (d.startsWith('60') && d.length > 2) d = d.substring(2);
    if (d.startsWith('0') && d.length > 1) d = d.substring(1);
    return d;
  }

  String _phoneLocalDigitsFromAny(String phone) {
    final digits = _digitsOnly(phone);
    if (digits.isEmpty) return '';
    if (digits.startsWith('60') && digits.length > 2) return '0${digits.substring(2)}';
    if (digits.startsWith('0')) return digits;
    if (digits.startsWith('1')) return '0$digits';
    return digits;
  }

  List<String> _phonesFromParentEmail(String? email) {
    if (email == null) return const <String>[];
    final e = email.trim().toLowerCase();
    if (!e.startsWith('p_') || !e.endsWith('@taskazurah.local')) return const <String>[];
    final at = e.indexOf('@');
    if (at <= 2) return const <String>[];

    final raw = e.substring(2, at).trim();
    final digits = _digitsOnly(raw);
    if (digits.isEmpty) return const <String>[];

    final out = <String>{};
    out.add(digits);
    if (digits.startsWith('60') && digits.length > 2) {
      out.add('0${digits.substring(2)}');
    }
    if (digits.startsWith('0') && digits.length > 1) {
      out.add('60${digits.substring(1)}');
    }
    return out.toList();
  }

  Future<void> _saveParentFcmToken(String parentId) async {
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken == null) return;

      await FirebaseFirestore.instance
          .collection('parents')
          .doc(parentId)
          .set({'fcm_token': fcmToken}, SetOptions(merge: true));
    } catch (_) {
      // Best effort.
    }
  }

  Future<void> _completeLoginAfterCandidates(List<String> rawCandidates) async {
    final candidates = <String>[];

    for (final c in rawCandidates) {
      final v = c.trim();
      if (v.isEmpty) continue;
      candidates.add(v);
      candidates.add(_phoneLocalDigitsFromAny(v));
      candidates.add(_digitsOnly(v));
    }

    final deduped = <String>[];
    final seen = <String>{};
    for (final c in candidates) {
      final v = c.trim();
      if (v.isEmpty) continue;
      if (seen.add(v)) deduped.add(v);
    }

    // PIN/email sessions can be resolved via phoneTail as well (after the rules update).
    // If rules are not deployed yet, permission-denied on phoneTail lookup is handled
    // by falling back to phone == ...
    await _completeLoginAfterAuthWithCandidates(deduped, allowTailLookup: true);
  }

  Future<void> _completeLoginAfterAuth({required String rawPhone, required String phoneE164}) async {
    final candidates = <String>[];
    for (final c in <String>[rawPhone, phoneE164]) {
      final v = c.trim();
      if (v.isEmpty) continue;
      candidates.add(v);
      candidates.add(_phoneLocalDigitsFromAny(v));
      candidates.add(_digitsOnly(v));
    }

    final deduped = <String>[];
    final seen = <String>{};
    for (final c in candidates) {
      final v = c.trim();
      if (v.isEmpty) continue;
      if (seen.add(v)) deduped.add(v);
    }

    // OTP/phone sessions have request.auth.token.phone_number, so phoneTail lookup is safe.
    await _completeLoginAfterAuthWithCandidates(
      deduped,
      allowTailLookup: true,
      expectedPhoneE164: phoneE164,
    );
  }

  String? _maybeE164FromAny(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return null;

    // If the user typed +6011..., preserve the +.
    if (raw.startsWith('+')) {
      final d = _digitsOnly(raw);
      return d.isEmpty ? null : '+$d';
    }

    final d = _digitsOnly(raw);
    if (d.isEmpty) return null;

    // Malaysia-centric normalization.
    if (d.startsWith('60') && d.length > 2) return '+$d';
    if (d.startsWith('0') && d.length > 1) return '+60${d.substring(1)}';
    if (d.startsWith('1') && d.length >= 9) return '+60$d';
    return null;
  }

  bool _docMatchesAnyCandidate(Map<String, dynamic> data, Set<String> candidates) {
    final p = data['phone']?.toString().trim();
    final e164 = data['phoneE164']?.toString().trim();
    if (e164 != null && e164.isNotEmpty && candidates.contains(e164)) return true;
    if (p != null && p.isNotEmpty && candidates.contains(p)) return true;
    return false;
  }

  Future<void> _completeLoginAfterAuthWithCandidates(
    List<String> candidates, {
    required bool allowTailLookup,
    String? expectedPhoneE164,
  }) async {
    QueryDocumentSnapshot<Map<String, dynamic>>? parentDoc;

    final candidateSet = <String>{};
    for (final c in candidates) {
      final v = c.trim();
      if (v.isEmpty) continue;
      candidateSet.add(v);
      final e164 = _maybeE164FromAny(v);
      if (e164 != null) candidateSet.add(e164);
    }
    if (expectedPhoneE164 != null && expectedPhoneE164.trim().isNotEmpty) {
      candidateSet.add(expectedPhoneE164.trim());
    }

    // 0) SAFEST: exact phoneE164 match first.
    for (final c in candidateSet) {
      if (!c.startsWith('+')) continue;
      final q = await FirebaseFirestore.instance
          .collection('parents')
          .where('phoneE164', isEqualTo: c)
          .limit(2)
          .get();
      if (q.docs.length == 1) {
        parentDoc = q.docs.first;
        break;
      }
      if (q.docs.length > 1) {
        await _failAndSignOut('Multiple parent records matched this phone. Please contact admin.');
        return;
      }
    }

    // 1) Try phoneTail lookup (align with canRequestOtp).
    if (allowTailLookup) {
      for (final c in candidates) {
        final tail = _myTail(c);
        if (tail.isEmpty) continue;
        try {
          final q = await FirebaseFirestore.instance
              .collection('parents')
              .where('phoneTail', isEqualTo: tail)
              .limit(2)
              .get();
          if (q.docs.length == 1) {
            final doc = q.docs.first;
            if (_docMatchesAnyCandidate(doc.data(), candidateSet)) {
              parentDoc = doc;
              break;
            }
          }
          if (q.docs.length > 1) {
            await _failAndSignOut('Multiple parent records matched this phone. Please contact admin.');
            return;
          }
        } on FirebaseException catch (e) {
          // If rules deny list by phoneTail for some reason, fall back to phone == ...
          if (e.code == 'permission-denied') {
            break;
          }
          rethrow;
        }
      }
    }

    // 2) Fallback: exact phone equality (legacy).
    if (parentDoc == null) {
      for (final phone in candidates) {
        final query = await FirebaseFirestore.instance
            .collection('parents')
            .where('phone', isEqualTo: phone)
            .limit(2)
            .get();
        if (query.docs.length == 1) {
          final doc = query.docs.first;
          if (_docMatchesAnyCandidate(doc.data(), candidateSet)) {
            parentDoc = doc;
            break;
          }
        }
        if (query.docs.length > 1) {
          await _failAndSignOut('Multiple parent records matched this phone. Please contact admin.');
          return;
        }
      }
    }

    if (parentDoc == null) {
      await _failAndSignOut('Account not found (maybe deleted). Please login again or contact admin.');
      return;
    }

    // Final guard: never attach to a doc that doesn't match our phone candidates.
    final data = parentDoc.data();
    if (!_docMatchesAnyCandidate(data, candidateSet)) {
      await _failAndSignOut('Account mismatch. Please login again or contact admin.');
      return;
    }

    final parentId = parentDoc.id;
    final parentName = data['parentName'] ?? 'Parent';
    final childName = data['childName'] ?? 'Anak';

    await _saveParentFcmToken(parentId);

    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(
      '/dashboard',
      arguments: {
        'parentId': parentId,
        'parentName': parentName,
        'childName': childName,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return const _GateLoadingScaffold();
  }
}
