import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // ✅ NEW

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController codeController = TextEditingController();
  bool isLoading = false;

  @override
  void dispose() {
    phoneController.dispose();
    codeController.dispose();
    super.dispose();
  }

  // ===== LOGIN FUNCTION =====
  Future<void> _loginParent() async {
    final phone = phoneController.text.trim();
    final code = codeController.text.trim();

    if (phone.isEmpty || code.isEmpty) {
      _showSnackBar("Please fill in all fields");
      return;
    }

    if (code.length != 6 || !RegExp(r'^[0-9]{6}$').hasMatch(code)) {
      _showSnackBar("Passcode must be 6 digits");
      return;
    }

    setState(() => isLoading = true);
    _showSnackBar("Loading...", duration: 1);

    try {
      final query = await FirebaseFirestore.instance
          .collection('parents')
          .where('phone', isEqualTo: phone)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        _showSnackBar("Number not registered. Contact admin.");
        setState(() => isLoading = false);
        return;
      }

      final doc = query.docs.first;
      final data = doc.data();
      final storedPasscode = data['passcode']?.toString().trim();
      final expiryTimestamp = data['passcode_expiry'] as Timestamp?;

      // Semak passcode
      if (storedPasscode == null || storedPasscode.isEmpty) {
        _showSnackBar("No passcode found. Contact admin.");
        setState(() => isLoading = false);
        return;
      }

      // Semak tarikh luput
      if (expiryTimestamp != null) {
        final expiry = expiryTimestamp.toDate();
        if (DateTime.now().isAfter(expiry)) {
          _showSnackBar("Passcode expired. Contact admin.");
          setState(() => isLoading = false);
          return;
        }
      }

      // Bandingkan passcode
      if (storedPasscode == code) {
        _showSnackBar("Login Success!", color: Colors.green);
        await Future.delayed(const Duration(milliseconds: 800));

        final parentId = doc.id;
        final parentName = data['parentName'] ?? 'Parent';
        final childName = data['childName'] ?? 'Anak';

        // ✅ SIMPAN TOKEN PARENT
        await _saveParentFcmToken(parentId);

        Navigator.of(context).pushReplacementNamed(
          '/dashboard',
          arguments: {
            'parentId': parentId,
            'parentName': parentName,
            'childName': childName,
          },
        );
      } else {
        _showSnackBar("Wrong passcode, please try again");
      }
    } catch (e) {
      _showSnackBar("Error: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  // ✅ FUNGSI BARU — SIMPAN FCM TOKEN
  Future<void> _saveParentFcmToken(String parentId) async {
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();

      if (fcmToken == null) {
        print('⚠️ FCM token is null — maybe permission not granted');
        return;
      }

      await FirebaseFirestore.instance
          .collection('parents')
          .doc(parentId)
          .set({'fcm_token': fcmToken}, SetOptions(merge: true));

      print('✅ FCM token saved for $parentId → $fcmToken');
    } catch (e) {
      print('🔥 Error saving FCM token: $e');
    }
  }

  void _showSnackBar(String message, {Color? color, int duration = 3}) {
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
                      _buildTextField(
                        controller: codeController,
                        hint: "Enter 6-digit passcode",
                        icon: Icons.lock_outline,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        obscureText: true,
                      ),
                      const SizedBox(height: 25),
                      GestureDetector(
                        onTap: isLoading ? null : _loginParent,
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
                                : const Text(
                                    "Login",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 30),
            Text(
              "Contact admin if you forgot your password",
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
