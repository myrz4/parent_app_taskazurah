// ✅ Firebase Functions v2 syntax
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();
const db = getFirestore();
const messaging = getMessaging();

// 🔔 Trigger bila attendance berubah (check-in / check-out)
exports.notifyParentOnAttendanceChange = onDocumentWritten("attendance/{recordId}", async (event) => {
  const after = event.data?.after?.data();
  const before = event.data?.before?.data();

  // ✅ Pastikan hanya trigger bila data berubah
  if (!after || JSON.stringify(after) === JSON.stringify(before)) return null;

  const childName = after.name || "Anak";
  const parentName = after.parentName || "Parent";
// ✅ Convert Firestore Timestamp + adjust timezone (UTC+8 Malaysia)
const checkIn = after.check_in_time
  ? new Date(after.check_in_time.seconds * 1000 + 8 * 60 * 60 * 1000)
  : null;
const checkOut = after.check_out_time
  ? new Date(after.check_out_time.seconds * 1000 + 8 * 60 * 60 * 1000)
  : null;

  const isPresent = after.isPresent ?? false;

  // 🧠 Tentukan mesej
  let title = "Attendance Update";
  let body = "";
 if (checkIn && !checkOut) {
  title = "👶 Anak Telah Check-In";
  body = `${childName} telah hadir ke Taska pada ${checkIn.toLocaleTimeString("ms-MY", { hour12: false })}.`;
} else if (checkOut) {
  title = "🚗 Anak Telah Check-Out";
  body = `${childName} telah pulang pada ${checkOut.toLocaleTimeString("ms-MY", { hour12: false })}.`;
} else if (!isPresent) {
  title = "❌ Anak Tidak Hadir";
  body = `${childName} tidak hadir hari ini.`;
}


  // 🔍 Cari parent dari Firestore
  const parentQuery = await db.collection("parents")
    .where("parentName", "==", parentName)
    .limit(1)
    .get();

  if (parentQuery.empty) {
    console.log("⚠️ Tiada parent ditemui untuk:", parentName);
    return null;
  }

  const parentDoc = parentQuery.docs[0];
  const fcmToken = parentDoc.data().fcm_token;

  if (!fcmToken) {
    console.log("⚠️ Parent tiada FCM token:", parentName);
    return null;
  }

  // 🔥 Hantar notifikasi
  const message = {
    token: fcmToken,
    notification: { title, body },
    data: {
      click_action: "FLUTTER_NOTIFICATION_CLICK",
      route: "/attendance_dashboard",
      childName: childName,
      parentName: parentName,
    },
  };

  try {
    await messaging.send(message);
    console.log(`✅ Notification sent to ${parentName}: ${title}`);
  } catch (error) {
    console.error("🔥 Error sending notification:", error);
  }

  return null;
});
