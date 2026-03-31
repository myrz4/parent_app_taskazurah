// 📱 File: pickup_scanner.dart
// ✅ Teacher Scanner (MobileScanner)
// ✅ Single-use Token + Attendance Update + Pickup Log
// ✅ Stage 5 Enhancement: Offline Protection (Anti-Screenshot QR)

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

      // 🔑 Extract token daripada "QR_XXXXXX"
      final tokenValue = qrCode.replaceFirst("QR_", "").trim();

      // 1️⃣ Cari parent pemilik token semasa
      final parentSnap = await FirebaseFirestore.instance
          .collection('parents')
          .where('dailyQrToken', isEqualTo: tokenValue)
          .limit(1)
          .get();

      if (parentSnap.docs.isEmpty) {
        _showResult(false, "QR tidak sah atau tiada dalam rekod.");
        return;
      }

      final parentDoc = parentSnap.docs.first;
      final parentData = parentDoc.data();
      final parentRef = parentDoc.reference;

      // Ambil maklumat paparan
      final parentName = parentData['parentName'] ?? 'Unknown';
        // No designated teacher per parent/child.
        final teacherName = 'Teacher';
      final repName = parentData['representativeName'] ?? '-';

      // 2️⃣ Dapatkan dokumen token sebenar
      final tokenRef = parentRef.collection('tokens').doc(tokenValue);
      final tokenSnap = await tokenRef.get();

      if (!tokenSnap.exists) {
        _showResult(false, "Token tidak wujud atau sudah dipadam.");
        return;
      }

      final tokenData = tokenSnap.data()!;
      final bool used = tokenData['used'] ?? false;
      final Timestamp? expiredAtTs = tokenData['expiredAt'];
      final DateTime? expiredAt = expiredAtTs?.toDate();

        final String childId = (tokenData['childId'] ?? parentData['childId'] ?? '').toString().trim();
        final String childName =
          (tokenData['childName'] ?? parentData['childName'] ?? 'Unknown').toString().trim();

      // 3️⃣ Semak status token
      if (used) {
        _showResult(false, "QR ini sudah digunakan.");
        return;
      }
      if (expiredAt != null && DateTime.now().isAfter(expiredAt)) {
        _showResult(false, "QR ini telah tamat tempoh.");
        return;
      }

      // 4️⃣ Cari attendance hari ini (ikut childId)
      final todayStart = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );
      final todayEnd = todayStart.add(const Duration(days: 1));

      final attendanceSnap = await FirebaseFirestore.instance
          .collection('attendance')
          .where('childId', isEqualTo: childId)
          .where('checkIn',
              isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
          .where('checkIn', isLessThan: Timestamp.fromDate(todayEnd))
          .limit(1)
          .get();

      if (attendanceSnap.docs.isEmpty) {
        _showResult(false, "Rekod kehadiran tiada untuk hari ini.");
        return;
      }

      final attRef = attendanceSnap.docs.first.reference;

      // 5️⃣ Update attendance (checkout)
      await attRef.update({
        'checkOut': FieldValue.serverTimestamp(),
        'manualCheckout': true,
        'pickupBy': repName,
        'verifiedBy': teacherName,
        'pickupAt': FieldValue.serverTimestamp(),
      });

      // 6️⃣ Tambah pickup log
      final pickupLog = await attRef.collection('pickup_logs').add({
        'timestamp': FieldValue.serverTimestamp(),
        'parentName': parentName,
        'representative': repName,
        'teacher': teacherName,
        'childName': childName,
      });

      // 7️⃣ Tandakan token digunakan (single-use)
      await tokenRef.update({
        'used': true,
        'usedAt': FieldValue.serverTimestamp(),
        'pickupLogId': pickupLog.id,
      });

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
