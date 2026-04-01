// 📱 File: pickup_scanner.dart
// ✅ Teacher Scanner (MobileScanner)
// ✅ Single-use Token + Attendance Update + Pickup Log
// ✅ Stage 5 Enhancement: Offline Protection (Anti-Screenshot QR)

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';

class PickupScannerPage extends StatefulWidget {
  const PickupScannerPage({super.key});

  @override
  State<PickupScannerPage> createState() => _PickupScannerPageState();
}

class _PickupScannerPageState extends State<PickupScannerPage> {
  final MobileScannerController controller = MobileScannerController();

  bool _loading = false;
  bool _hasScanned = false;
  bool _torchOn = false; // ✅ Manual torch state tracking
  static const Color primary = Color(0xFF7ACB9E);

  String _reasonToMessage(String reason) {
    switch (reason) {
      case 'pickup-token-not-found':
        return 'QR tidak sah atau tiada dalam rekod.';
      case 'pickup-token-expired':
        return 'QR ini telah tamat tempoh.';
      case 'pickup-token-already-used':
        return 'QR ini sudah digunakan.';
      case 'attendance-not-found':
        return 'Rekod kehadiran tiada untuk hari ini.';
      case 'attendance-not-checked-in':
        return 'Kanak-kanak belum check-in.';
      case 'attendance-already-closed':
        return 'Attendance sudah ditutup.';
      case 'staff-only':
        return 'Hanya guru atau admin boleh sahkan pickup.';
      default:
        return 'Pengesahan QR gagal.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parent Pickup Verification'),
        backgroundColor: primary,
        actions: [
          // ✅ Flashlight toggle
          IconButton(
            icon: Icon(
              _torchOn ? Icons.flash_on : Icons.flash_off,
              color: Colors.white,
            ),
            onPressed: () async {
              try {
                await controller.toggleTorch();
                setState(() => _torchOn = !_torchOn);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Flashlight not available'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
          // ✅ Camera switch
          IconButton(
            icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
            onPressed: () => controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // ✅ Full-screen scanner
          MobileScanner(
            controller: controller,
            onDetect: (capture) {
              if (_hasScanned || _loading) return;
              final barcode = capture.barcodes.firstOrNull;
              if (barcode?.rawValue != null) {
                setState(() => _hasScanned = true);
                _processPickup(barcode!.rawValue!);
              }
            },
          ),

          // ✅ QR frame overlay
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: primary, width: 8),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          // ✅ Bottom loading text
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              color: Colors.black54,
              child: _loading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                      "Scan Parent QR Code to verify pickup",
                      style: TextStyle(color: Colors.white, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _processPickup(String qrCode) async {
    setState(() => _loading = true);

    try {
      // 🛡️ 0️⃣ OFFLINE PROTECTION – Elak penggunaan QR secara offline
      try {
        await FirebaseFirestore.instance
            .collection('__') // dummy query untuk test internet
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 3));
      } catch (e) {
        _showResult(false,
            "Peranti tiada sambungan internet. Sila sambung semula untuk sahkan QR.");
        setState(() {
          _loading = false;
          _hasScanned = false;
        });
        return;
      }

      final tokenValue = qrCode.replaceFirst("QR_", "").trim();
      final callable = FirebaseFunctions.instanceFor(region: 'asia-southeast1')
          .httpsCallable('attendanceCheckoutWithParentQr');
      final response = await callable.call<Map<String, dynamic>>({
        'qrToken': tokenValue,
        'teacherName': 'Teacher',
      });
      final result = Map<String, dynamic>.from(response.data ?? const <String, dynamic>{});
      if (result['ok'] != true) {
        _showResult(false, _reasonToMessage((result['reason'] ?? '').toString()));
        return;
      }

      final parentName = (result['parentName'] ?? 'Unknown').toString();
      final childName = (result['childName'] ?? 'Unknown').toString();
      final repName = (result['representativeName'] ?? '-').toString();
      final teacherName = 'Teacher';

      // 8️⃣ Papar kejayaan
      _showResult(
        true,
        "Pickup Disahkan\n"
        "Parent: $parentName\n"
        "Anak: $childName\n"
        "Wakil: $repName\n"
        "Guru: $teacherName\n"
        "Masa: ${DateFormat('hh:mm a').format(DateTime.now())}",
      );
    } catch (e) {
      _showResult(false, "Ralat: ${e.toString()}");
    } finally {
      setState(() {
        _loading = false;
        _hasScanned = false;
      });
    }
  }

  void _showResult(bool success, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          success ? "Berjaya" : "Gagal",
          style: TextStyle(
            color: success ? Colors.green : Colors.red,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              controller.start(); // Resume scanning
            },
            child: const Text("Tutup"),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
