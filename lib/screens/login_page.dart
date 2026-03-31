import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../services/otp_pin_reset_request.dart';

import '../services/app_lock_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController pinController = TextEditingController();
  final TextEditingController otpController = TextEditingController();
  bool isLoading = false;

  final _appLock = AppLockService();

  String? _verificationId;
  bool _codeSent = false;
  bool _otpMode = false;

  DateTime? _lastOtpRequestAt;
  static const Duration _otpCooldown = Duration(seconds: 60);

  @override
  void dispose() {
    phoneController.dispose();
    pinController.dispose();
    otpController.dispose();
    super.dispose();
  }

  // ===== LOGIN (PIN FIRST) =====
  Future<void> _loginWithPin() async {
    final rawPhone = phoneController.text.trim();
    final phoneE164 = _normalizePhoneToE164(rawPhone);
    if (phoneE164 == null) {
      _showSnackBar("Please enter a valid phone number (e.g. +6011...) ");
      return;
    }

    final pin = pinController.text.trim();
    if (pin.length != 6 || !RegExp(r'^[0-9]{6}$').hasMatch(pin)) {
      _showSnackBar("PIN must be exactly 6 digits");
      return;
    }

    setState(() => isLoading = true);
    _showSnackBar("Signing in...", duration: 1);

    try {
      final emails = _candidateDerivedEmails(rawPhone: rawPhone, phoneE164: phoneE164);
      FirebaseAuthException? lastAuthError;

      var signedIn = false;
      for (final email in emails) {
        try {
          await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: pin);
          signedIn = true;
          break;
        } on FirebaseAuthException catch (e) {
          lastAuthError = e;
          // Try next candidate for common auth failures.
          if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential') {
            continue;
          }
          rethrow;
        }
      }

      if (!signedIn) {
        throw lastAuthError ?? FirebaseAuthException(code: 'invalid-credential');
      }

      // Keep local app-lock PIN in sync on this device.
      final useBio = await _appLock.useBiometrics();
      await _appLock.enableWithPin(pin: pin, enableBiometrics: useBio);
      _showSnackBar('Signed in.', color: Colors.green);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential') {
        _showSnackBar("PIN not set or incorrect. Use OTP login.");
        setState(() {
          _otpMode = true;
          _codeSent = false;
          _verificationId = null;
        });
      } else {
        _showSnackBar(e.message ?? "Login failed");
      }
    } catch (e) {
      _showSnackBar("Error: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ===== OTP MODE (LOGIN) =====
  Future<void> _sendOtpForOtpLogin() async {
    if (isLoading) return;
    final rawPhone = phoneController.text.trim();
    final phoneE164OrNull = _normalizePhoneToE164(rawPhone);
    if (phoneE164OrNull == null) {
      _showSnackBar("Please enter a valid phone number (e.g. +6011...) ");
      return;
    }

    final phoneE164 = phoneE164OrNull;

    await _sendOtp(phoneE164);
  }

  Future<void> _verifyOtpAndLogin() async {
    final rawPhone = phoneController.text.trim();
    final phoneE164 = _normalizePhoneToE164(rawPhone);
    if (phoneE164 == null) {
      _showSnackBar("Please enter a valid phone number (e.g. +6011...) ");
      return;
    }

    final otp = otpController.text.trim();
    if (otp.length != 6 || !RegExp(r'^[0-9]{6}$').hasMatch(otp)) {
      _showSnackBar("OTP must be 6 digits");
      return;
    }

    if (_verificationId == null || !_codeSent) {
      _showSnackBar("Please send OTP first");
      return;
    }

    setState(() => isLoading = true);
    _showSnackBar("Verifying OTP...", duration: 1);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: otp,
      );

      // Mark OTP session BEFORE sign-in so AuthGate can deterministically detect it.
      await OtpPinResetRequest.markPendingForPhone(phoneE164: phoneE164);
      await FirebaseAuth.instance.signInWithCredential(credential);

      // Routing + PIN setup is handled by ParentAuthGate.
      _showSnackBar("Signed in. Continue...", color: Colors.green);
    } on FirebaseAuthException catch (e) {
      _showSnackBar(e.message ?? "Verification failed");
      await OtpPinResetRequest.clear();
    } catch (e) {
      _showSnackBar("Error: $e");
      await OtpPinResetRequest.clear();
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _sendOtp(String phoneE164) async {
    final now = DateTime.now();
    final last = _lastOtpRequestAt;
    if (last != null) {
      final elapsed = now.difference(last);
      if (elapsed < _otpCooldown) {
        final remaining = (_otpCooldown - elapsed).inSeconds;
        _showSnackBar("Please wait $remaining seconds before requesting OTP again.");
        return;
      }
    }

    setState(() => isLoading = true);
    _showSnackBar("Sending code...", duration: 1);

    // Gate SMS cost: only send OTP if this phone is registered as a parent.
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-southeast1').httpsCallable('canRequestOtp');
      final res = await callable.call({
        'phone': phoneE164,
        'kind': 'parent',
      });
      final data = (res.data is Map) ? (res.data as Map) : <dynamic, dynamic>{};
      final allowed = data['allowed'] == true;
      if (!allowed) {
        final reason = (data['reason'] ?? '').toString();
        if (reason == 'not-registered') {
          _showSnackBar('Number not registered. Contact admin.');
        } else {
          _showSnackBar('Unable to verify registration ($reason). Try again later.');
        }
        if (mounted) setState(() => isLoading = false);
        return;
      }
    } catch (_) {
      _showSnackBar('Unable to verify registration. Try again later.');
      if (mounted) setState(() => isLoading = false);
      return;
    }

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phoneE164,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          // Mark OTP session BEFORE sign-in so AuthGate can deterministically detect it.
          await OtpPinResetRequest.markPendingForPhone(phoneE164: phoneE164);
          await FirebaseAuth.instance.signInWithCredential(credential);

          // PIN setup + routing is handled by ParentAuthGate.
          _showSnackBar("Signed in. Continue...", color: Colors.green);
        } catch (e) {
          await OtpPinResetRequest.clear();
          _showSnackBar("Auto verification failed: $e");
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        if (mounted) setState(() => isLoading = false);
        _showSnackBar(_friendlyAuthErrorMessage(e));
      },
      codeSent: (String verificationId, int? resendToken) {
        setState(() {
          _verificationId = verificationId;
          _codeSent = true;
          isLoading = false;
          _lastOtpRequestAt = DateTime.now();
        });
        _showSnackBar("Code sent. Please enter the 6-digit code.");
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
    );
  }

  String _friendlyAuthErrorMessage(FirebaseAuthException e) {
    final rawMsg = (e.message ?? '').toUpperCase();
    if (rawMsg.contains('BILLING_NOT_ENABLED')) {
      return 'Phone OTP requires Google Cloud Billing for this Firebase project. Enable Billing (Blaze) or use Firebase Test Phone Numbers.';
    }
    switch (e.code) {
      case 'billing-not-enabled':
        return 'Phone OTP requires Google Cloud Billing for this Firebase project. Enable Billing (Blaze) or use Firebase Test Phone Numbers.';
      case 'too-many-requests':
        return 'We have blocked OTP requests due to unusual activity. Please wait and try again, or use a Firebase test phone number.';
      case 'invalid-phone-number':
        return 'Invalid phone number format. Use +6011...';
      case 'captcha-check-failed':
        return 'reCAPTCHA / Play Integrity check failed. Try again on a real device with Google Play services.';
      case 'app-not-authorized':
      case 'invalid-app-credential':
      case 'missing-client-identifier':
        return 'App verification failed. Make sure the Firebase Android app package + SHA-1/SHA-256 match the APK you installed.';
      default:
        final m = e.message;
        if (m != null && m.trim().isNotEmpty) return m;
        return 'Verification failed (${e.code}).';
    }
  }

  Future<bool> _ensurePinIsSetAfterOtp({required String phoneE164}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    var pinSaved = false;
    var pinAlreadyExists = false;

    final hasPasswordProvider = user.providerData.any((p) => p.providerId == 'password');
    final title = hasPasswordProvider ? 'Reset PIN' : 'Create PIN';
    final subtitle = hasPasswordProvider
        ? 'You logged in using OTP. Set a new PIN to login next time.'
        : 'PIN is mandatory. Create a PIN to login next time.';

    final pin1 = TextEditingController();
    final pin2 = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
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
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Logout'),
            ),
            ElevatedButton(
              onPressed: () async {
                final a = pin1.text.trim();
                final b = pin2.text.trim();
                if (a.length != 6 || !RegExp(r'^[0-9]{6}$').hasMatch(a)) {
                  _showSnackBar('PIN must be exactly 6 digits');
                  return;
                }
                if (a != b) {
                  _showSnackBar('PIN does not match');
                  return;
                }

                final email = _emailFromPhone(phoneE164);

                try {
                  if (!hasPasswordProvider) {
                    await user.linkWithCredential(EmailAuthProvider.credential(email: email, password: a));
                  } else {
                    await user.updatePassword(a);
                  }
                  pinSaved = true;
                  await _appLock.enableWithPin(pin: a, enableBiometrics: false);
                  if (!context.mounted) return;
                  Navigator.of(context).pop(true);
                } on FirebaseAuthException catch (e) {
                  if (!context.mounted) return;
                  if (e.code == 'email-already-in-use' || e.code == 'credential-already-in-use') {
                    // This usually means a derived-email account already exists for this phone.
                    // OTP login can continue, but we can't reset that password without knowing it.
                    pinAlreadyExists = true;
                    _showSnackBar('PIN already exists for this number. Continue with OTP, or use PIN login next time.');
                    Navigator.of(context).pop(true);
                    return;
                  }
                  _showSnackBar(e.message ?? 'Failed to create PIN');
                } catch (_) {
                  if (!context.mounted) return;
                  _showSnackBar('Failed to create PIN');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
              ),
              child: const Text('Save PIN'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      if (pinSaved) {
        _showSnackBar(hasPasswordProvider ? 'PIN updated' : 'PIN created', color: Colors.green);
      } else if (pinAlreadyExists) {
        _showSnackBar('PIN already exists (not changed).', color: Colors.green);
      }
      return true;
    }

    await FirebaseAuth.instance.signOut();
    _showSnackBar('PIN is required to continue');
    return false;
  }

  String _digitsOnly(String input) => input.replaceAll(RegExp(r'[^0-9]'), '');

  // Firestore stores phones like 011..., not +60....
  // Canonicalize any input (raw or E164) to local digits (0xxxxxxxxx).
  String _phoneLocalDigitsFromAny(String phone) {
    final digits = _digitsOnly(phone);
    if (digits.isEmpty) return '';
    if (digits.startsWith('60') && digits.length > 2) return '0${digits.substring(2)}';
    if (digits.startsWith('0')) return digits;
    // If user typed 11... without leading 0, assume Malaysia mobile and prefix 0.
    if (digits.startsWith('1')) return '0$digits';
    return digits;
  }

  List<String> _candidateDerivedEmails({required String rawPhone, required String phoneE164}) {
    final emails = <String>{};

    final local = _phoneLocalDigitsFromAny(rawPhone.isNotEmpty ? rawPhone : phoneE164);
    if (local.isNotEmpty) emails.add('p_$local@taskazurah.local');

    // Legacy variants (older builds may have used +60 digits).
    final e164Digits = _digitsOnly(phoneE164);
    if (e164Digits.isNotEmpty) emails.add('p_$e164Digits@taskazurah.local');
    final rawDigits = _digitsOnly(rawPhone);
    if (rawDigits.isNotEmpty) emails.add('p_$rawDigits@taskazurah.local');

    return emails.toList();
  }

  String _emailFromPhone(String phoneE164) {
    final local = _phoneLocalDigitsFromAny(phoneE164);
    return 'p_$local@taskazurah.local';
  }

  String? _phoneFromEmail(String? email) {
    if (email == null) return null;
    final e = email.trim().toLowerCase();
    if (!e.startsWith('p_') || !e.endsWith('@taskazurah.local')) return null;
    final at = e.indexOf('@');
    if (at <= 2) return null;
    final digits = e.substring(2, at);
    if (digits.isEmpty) return null;
    if (digits.startsWith('60') && digits.length > 2) return '0${digits.substring(2)}';
    return digits;
  }

  String? _normalizePhoneToE164(String input) {
    var v = input.trim().replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (v.isEmpty) return null;

    if (v.startsWith('+')) {
      // Basic sanity check
      final digits = _digitsOnly(v);
      if (digits.length < 10) return null;
      return '+$digits';
    }

    // Common Malaysia formats: 011..., 01..., 60...
    final digits = _digitsOnly(v);
    if (digits.startsWith('60')) {
      if (digits.length < 11) return null;
      return '+$digits';
    }
    if (digits.startsWith('0')) {
      final rest = digits.substring(1);
      if (rest.length < 9) return null;
      return '+60$rest';
    }

    // If user entered without 0/+60, we can't safely guess.
    return null;
  }

  void _showSnackBar(String message, {Color? color, int duration = 3}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: color ?? const Color(0xFF81C784),
        duration: Duration(seconds: duration),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ===== HEADER =====
            Container(
              height: 380,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF81C784), Color(0xFF66BB6A)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(60),
                  bottomRight: Radius.circular(60),
                ),
              ),
              child: Center(
                child: FadeInDown(
                  duration: const Duration(milliseconds: 1000),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 80),
                      const Text(
                        "TASKA ZURAH",
                        style: TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Parenting is not about perfection, it’s about connection.",
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white.withOpacity(0.9),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 30),

            // ===== LOGIN FORM =====
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: FadeInUp(
                duration: const Duration(milliseconds: 1200),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _buildTextField(
                        controller: phoneController,
                        hint: "Enter Your Number",
                        icon: Icons.phone,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 16),
                      if (_otpMode && _codeSent)
                        _buildTextField(
                          controller: otpController,
                          hint: "Enter 6-digit OTP",
                          icon: Icons.sms,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          obscureText: false,
                        )
                      else if (!_otpMode)
                        _buildTextField(
                          controller: pinController,
                          hint: "Enter PIN (4–6 digits)",
                          icon: Icons.lock_outline,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          obscureText: true,
                        )
                      else
                        const SizedBox.shrink(),
                      const SizedBox(height: 25),
                      GestureDetector(
                        onTap: isLoading
                            ? null
                            : (_otpMode
                                ? (_codeSent ? _verifyOtpAndLogin : _sendOtpForOtpLogin)
                                : _loginWithPin),
                        child: Container(
                          height: 55,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(15),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF66BB6A), Color(0xFF4CAF50)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.withOpacity(0.4),
                                blurRadius: 10,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Center(
                            child: isLoading
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Text(
                                    _otpMode
                                    ? (_codeSent ? "Verify OTP & Login" : "Send OTP")
                                        : "Login",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: isLoading
                            ? null
                            : () {
                                setState(() {
                                  _otpMode = !_otpMode;
                                  _codeSent = false;
                                  _verificationId = null;
                                });
                              },
                        child: Text(
                          _otpMode ? 'Use PIN login' : 'Forgot PIN? Use OTP',
                          style: const TextStyle(color: Color(0xFF2F5F4A)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 30),
            Text(
              "OTP is only for first-time setup / forgot PIN",
              style: TextStyle(color: Colors.grey[700], fontSize: 13),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ===== TEXT FIELD =====
  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
    bool obscureText = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLength: maxLength,
      obscureText: obscureText,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(
        counterText: "",
        prefixIcon: Icon(icon, color: const Color(0xFF66BB6A)),
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[500]),
        filled: true,
        fillColor: const Color(0xFFF1F8E9),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF66BB6A), width: 2),
        ),
      ),
    );
  }
}
