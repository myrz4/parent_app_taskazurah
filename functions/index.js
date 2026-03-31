// ✅ Firebase Functions v2 syntax
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onCall } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();
const db = getFirestore();
const messaging = getMessaging();
const auth = getAuth();

function digitsOnly(input) {
  return String(input || "").replace(/[^0-9]/g, "");
}

function myTail(phoneAny) {
  let d = digitsOnly(phoneAny);
  if (!d) return "";
  if (d.startsWith("60") && d.length > 2) d = d.slice(2);
  if (d.startsWith("0") && d.length > 1) d = d.slice(1);
  return d;
}

async function findTeacherByPhone(phoneE164) {
  const tail = myTail(phoneE164);
  const local = tail ? `0${tail}` : "";

  if (phoneE164) {
    const byE164 = await db.collection("teachers").where("phoneE164", "==", phoneE164).limit(1).get();
    if (!byE164.empty) return { found: true, tail };
  }
  if (tail) {
    const byTail = await db.collection("teachers").where("phoneTail", "==", tail).limit(1).get();
    if (!byTail.empty) return { found: true, tail };
  }
  if (local) {
    const byLocal = await db.collection("teachers").where("phone", "==", local).limit(1).get();
    if (!byLocal.empty) return { found: true, tail };
  }
  return { found: false, tail };
}

// Callable: gate OTP requests BEFORE sending SMS.
// data: { phone: string, kind: 'teacher' | 'parent' }
exports.canRequestOtp = onCall({ region: "asia-southeast1" }, async (req) => {
  const phone = (req.data && req.data.phone) ? String(req.data.phone).trim() : "";
  const kind = (req.data && req.data.kind) ? String(req.data.kind).trim().toLowerCase() : "";
  if (!phone) return { allowed: false, reason: "missing-phone" };
  if (kind !== "teacher" && kind !== "parent") return { allowed: false, reason: "invalid-kind" };

  // Optional hardening (recommended): enforce App Check once enabled in apps.
  // if (!req.app) return { allowed: false, reason: 'app-check-required' };

  const tail = myTail(phone);
  if (!tail) return { allowed: false, reason: "invalid-phone" };
  const local = `0${tail}`;
  const col = kind === "teacher" ? "teachers" : "parents";

  try {
    let snap = await db.collection(col).where("phoneTail", "==", tail).limit(1).get();
    if (snap.empty) {
      snap = await db.collection(col).where("phone", "==", local).limit(1).get();
    }
    return snap.empty ? { allowed: false, reason: "not-registered" } : { allowed: true };
  } catch (e) {
    console.error("canRequestOtp failed", e);
    return { allowed: false, reason: "server-error" };
  }
});

// Callable: after OTP sign-in, auto-assign teacher role if registered.
exports.claimTeacherRole = onCall({ region: "asia-southeast1" }, async (req) => {
  if (!req.auth) return { ok: false, reason: "unauthenticated" };

  try {
    const uid = req.auth.uid;
    let phoneE164 = (req.auth.token && req.auth.token.phone_number)
      ? String(req.auth.token.phone_number)
      : "";

    if (!phoneE164) {
      const u = await auth.getUser(uid);
      phoneE164 = u.phoneNumber ? String(u.phoneNumber) : "";
    }

    if (!phoneE164) return { ok: false, reason: "missing-phone" };

    const reg = await findTeacherByPhone(phoneE164);

    const u = await auth.getUser(uid);
    const existing = u.customClaims || {};
    const role = existing.role;

    if (!reg.found) {
      if (role === "teacher") {
        const nextClaims = { ...existing };
        delete nextClaims.role;
        await auth.setCustomUserClaims(uid, nextClaims);
        return { ok: false, reason: "not-registered", cleared: true };
      }
      return { ok: false, reason: "not-registered" };
    }

    if (role === "teacher" || role === "admin") return { ok: true, already: true, role };

    await auth.setCustomUserClaims(uid, { ...existing, role: "teacher" });
    return { ok: true, set: true };
  } catch (e) {
    console.error("claimTeacherRole failed", e);
    return { ok: false, reason: "server-error" };
  }
});

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

// ------------------ Billing / Payments (demo path on dummy provider now, real-ready later) ------------------

function requireAuth(req) {
  if (!req.auth) {
    const err = new Error("unauthenticated");
    err.code = "unauthenticated";
    throw err;
  }
}

function normalizePayerType(raw) {
  const v = String(raw || "").trim().toLowerCase();
  return v === "staff" ? "staff" : "nonstaff";
}

function moneySenToMYR(amountSen) {
  const n = Number(amountSen || 0);
  return Math.max(0, Math.round(n));
}

function monthKey(d = new Date()) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  return `${y}-${m}`;
}

function uniqueSortedIds(values) {
  return Array.from(new Set(
    (Array.isArray(values) ? values : [])
      .map((value) => String(value || "").trim())
      .filter(Boolean),
  )).sort();
}

function invoiceChildIds(invoice) {
  const ids = [];
  if (invoice && Array.isArray(invoice.childIds)) ids.push(...invoice.childIds);
  if (invoice && invoice.childId) ids.push(invoice.childId);
  return uniqueSortedIds(ids);
}

function childCoverageKey(period, childIds) {
  const normalizedPeriod = String(period || "").trim();
  const normalizedChildIds = uniqueSortedIds(childIds);
  if (!normalizedPeriod || !normalizedChildIds.length) return "";
  return `${normalizedPeriod}::${normalizedChildIds.join("|")}`;
}

function invoiceChildCoverageKey(invoice) {
  const existing = String(invoice && invoice.childCoverageKey ? invoice.childCoverageKey : "").trim();
  if (existing) return existing;
  return childCoverageKey(invoice && invoice.period, invoiceChildIds(invoice));
}

function timestampMillis(raw) {
  if (!raw) return "";
  if (typeof raw.toMillis === "function") return String(raw.toMillis());
  if (typeof raw.seconds === "number") {
    return String((raw.seconds * 1000) + Math.floor(Number(raw.nanoseconds || 0) / 1000000));
  }
  const parsed = Date.parse(String(raw));
  return Number.isNaN(parsed) ? "" : String(parsed);
}

function invoicePaymentFingerprint(invoice) {
  return JSON.stringify({
    status: String(invoice && invoice.status ? invoice.status : "").toLowerCase(),
    paidReceiptNo: String(invoice && invoice.paidReceiptNo ? invoice.paidReceiptNo : ""),
    paidPaymentId: String(invoice && invoice.paidPaymentId ? invoice.paidPaymentId : ""),
    paidMethod: String(invoice && invoice.paidMethod ? invoice.paidMethod : ""),
    paidBank: String(invoice && invoice.paidBank ? invoice.paidBank : ""),
    paidAmountSen: Number(invoice && invoice.paidAmountSen ? invoice.paidAmountSen : 0),
    paidProvider: String(invoice && invoice.paidProvider ? invoice.paidProvider : ""),
    paidAt: timestampMillis(invoice && invoice.paidAt),
    childCoverageKey: invoiceChildCoverageKey(invoice),
  });
}

function buildPaidInvoiceSyncPatch(sourceInvoice, sourcePath) {
  const patch = {
    status: "paid",
    childCoverageKey: invoiceChildCoverageKey(sourceInvoice),
    updatedAt: FieldValue.serverTimestamp(),
    sharedPaymentSourcePath: String(sourcePath || ""),
    sharedPaymentSyncedAt: FieldValue.serverTimestamp(),
  };

  const mirroredFields = [
    "paidAt",
    "paidMethod",
    "paidBank",
    "paidAmountSen",
    "paidReceiptNo",
    "paidPaymentId",
    "paidProvider",
  ];
  for (const field of mirroredFields) {
    if (sourceInvoice && Object.prototype.hasOwnProperty.call(sourceInvoice, field)) {
      patch[field] = sourceInvoice[field];
    }
  }
  return patch;
}

async function findEquivalentPaidInvoice({ period, childIds, excludePath = "" }) {
  const normalizedPeriod = String(period || "").trim();
  const coverageKey = childCoverageKey(normalizedPeriod, childIds);
  if (!normalizedPeriod || !coverageKey) return null;

  const snap = await db.collectionGroup("invoices").where("period", "==", normalizedPeriod).get();
  for (const doc of snap.docs) {
    if (excludePath && doc.ref.path === excludePath) continue;
    const data = doc.data() || {};
    if (String(data.status || "").toLowerCase() !== "paid") continue;
    if (invoiceChildCoverageKey(data) !== coverageKey) continue;
    return { ref: doc.ref, data };
  }
  return null;
}

async function repairInvoiceFromEquivalentPaidCopy({ invoiceRef, invoiceData }) {
  const match = await findEquivalentPaidInvoice({
    period: invoiceData && invoiceData.period,
    childIds: invoiceChildIds(invoiceData),
    excludePath: invoiceRef.path,
  });
  if (!match) {
    return { repaired: false, invoiceData };
  }

  if (invoicePaymentFingerprint(invoiceData) === invoicePaymentFingerprint(match.data)) {
    return {
      repaired: false,
      invoiceData: {
        ...invoiceData,
        childCoverageKey: invoiceChildCoverageKey(match.data),
      },
    };
  }

  await invoiceRef.set(buildPaidInvoiceSyncPatch(match.data, match.ref.path), { merge: true });
  return {
    repaired: true,
    invoiceData: {
      ...invoiceData,
      ...match.data,
      status: "paid",
      childCoverageKey: invoiceChildCoverageKey(match.data),
    },
  };
}

async function syncEquivalentPaidInvoicesFromSource({ sourceRef, sourceInvoice }) {
  const normalizedPeriod = String(sourceInvoice && sourceInvoice.period ? sourceInvoice.period : "").trim();
  const coverageKey = invoiceChildCoverageKey(sourceInvoice);
  if (!normalizedPeriod || !coverageKey || String(sourceInvoice && sourceInvoice.status ? sourceInvoice.status : "").toLowerCase() !== "paid") {
    return 0;
  }

  const sourceFingerprint = invoicePaymentFingerprint(sourceInvoice);
  const snap = await db.collectionGroup("invoices").where("period", "==", normalizedPeriod).get();
  const batch = db.batch();
  let updates = 0;

  for (const doc of snap.docs) {
    if (doc.ref.path === sourceRef.path) continue;
    const data = doc.data() || {};
    if (invoiceChildCoverageKey(data) !== coverageKey) continue;
    if (invoicePaymentFingerprint(data) === sourceFingerprint) continue;
    batch.set(doc.ref, buildPaidInvoiceSyncPatch(sourceInvoice, sourceRef.path), { merge: true });
    updates += 1;
  }

  if (updates > 0) {
    await batch.commit();
  }
  return updates;
}

function parseIsoDateOnly(s) {
  const v = String(s || "").trim();
  if (!v) return null;
  // yyyy-MM-dd
  const m = v.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!m) return null;
  const dt = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  return Number.isNaN(dt.getTime()) ? null : dt;
}

function ageInMonths(at, birthDate) {
  const a = new Date(at.getFullYear(), at.getMonth(), 1);
  const b = new Date(birthDate.getFullYear(), birthDate.getMonth(), 1);
  return (a.getFullYear() - b.getFullYear()) * 12 + (a.getMonth() - b.getMonth());
}

function resolveAgeProfile(months) {
  if (!Number.isFinite(Number(months))) {
    return {
      ageBand: "2y_4y",
      ageOutOfPolicy: true,
      agePolicyReason: "missing_birth_date",
    };
  }

  const ageMonths = Number(months);
  if (ageMonths < 3) {
    return {
      ageBand: "3m_2y",
      ageOutOfPolicy: true,
      agePolicyReason: "under_3_months",
    };
  }
  if (ageMonths < 24) {
    return {
      ageBand: "3m_2y",
      ageOutOfPolicy: false,
      agePolicyReason: "in_range",
    };
  }
  if (ageMonths < 60) {
    return {
      ageBand: "2y_4y",
      ageOutOfPolicy: false,
      agePolicyReason: "in_range",
    };
  }
  return {
    ageBand: "2y_4y",
    ageOutOfPolicy: true,
    agePolicyReason: "age_4y_or_above",
  };
}

function registrationChargeRequired(child, periodKey) {
  if (!child) return false;

  const appliedPeriod = String(child.registrationFeeAppliedPeriod || "").trim();
  if (appliedPeriod) return false;

  const registrationDate = child.registeredAt && typeof child.registeredAt.toDate === "function"
    ? child.registeredAt.toDate()
    : (child.registeredAt ? new Date(child.registeredAt) : null);
  if (!registrationDate || Number.isNaN(registrationDate.getTime())) {
    return false;
  }

  const registrationPeriod = monthKey(registrationDate);
  return !periodKey || registrationPeriod <= periodKey;
}

function resolveBillingAgePolicy({ months, baseCode }) {
  const defaultProfile = resolveAgeProfile(months);
  const normalizedBaseCode = String(baseCode || "").trim().toLowerCase();

  if (!normalizedBaseCode.startsWith("transit_")) {
    return defaultProfile;
  }

  if (normalizedBaseCode === "transit_schoolholiday_month") {
    if (!Number.isFinite(Number(months))) {
      return {
        ageBand: defaultProfile.ageBand,
        ageOutOfPolicy: true,
        agePolicyReason: "school_holiday_requires_known_age",
      };
    }
    if (Number(months) < 48) {
      return {
        ageBand: defaultProfile.ageBand,
        ageOutOfPolicy: true,
        agePolicyReason: "school_holiday_requires_age_4_plus",
      };
    }
  }

  return {
    ageBand: defaultProfile.ageBand,
    ageOutOfPolicy: false,
    agePolicyReason: "transit_all_ages_allowed",
  };
}

async function assertParentOwnerByPhone({ parentId, authToken }) {
  const phone = authToken && authToken.phone_number ? String(authToken.phone_number) : "";
  if (!phone) {
    const err = new Error("missing-phone");
    err.code = "failed-precondition";
    throw err;
  }

  const snap = await db.collection("parents").doc(parentId).get();
  if (!snap.exists) {
    const err = new Error("parent-not-found");
    err.code = "not-found";
    throw err;
  }

  const p = snap.data() || {};
  const phoneE164 = String(p.phoneE164 || "").trim();
  const phoneTail = String(p.phoneTail || "").trim();
  const phoneLocal = String(p.phone || "").trim();

  const tail = myTail(phone);
  const ok = (phoneE164 && phoneE164 === phone)
    || (phoneTail && tail && phone.endsWith(phoneTail))
    || (phoneLocal && tail && myTail(phoneLocal) === tail);

  if (!ok) {
    const err = new Error("forbidden");
    err.code = "permission-denied";
    throw err;
  }

  return { parentSnap: snap, parentData: p, phoneE164: phone, tail };
}

function feeTableFromPdf() {
  // Prices in sen (MYR * 100), sourced from Kadar Bayaran TPPM.pdf.
  return {
    version: "pdf-2026-03-18",
    monthly_fulltime_3m_2y: { staff: 35000, nonstaff: 40000 },
    monthly_fulltime_2y_4y: { staff: 30000, nonstaff: 35000 },
    transit_halfday_month: { staff: 15000, nonstaff: 25000 },
    transit_2h_month: { staff: 10000, nonstaff: 18000 },
    transit_schoolholiday_month: { staff: 25000, nonstaff: 30000 },
    transit_1day: { staff: 1500, nonstaff: 2000 },
    transit_1week: { staff: 7000, nonstaff: 10000 },
    transit_1hour: { staff: 350, nonstaff: 400 },
    overtime_after_530: { staff: 500, nonstaff: 600 },
    overtime_8pm_12am: { staff: 1000, nonstaff: 1300 },
    overtime_12am_7am: { staff: 700, nonstaff: 1000 },
    transport_tadika_month: { staff: 15000, nonstaff: 15000 },
    registration_fulltime_oneoff: { staff: 10000, nonstaff: 10000 },
    registration_transit_oneoff: { staff: 5000, nonstaff: 5000 },
    annual_fee_yearly: { staff: 10000, nonstaff: 10000 },
    comms_book_4months: { staff: 1500, nonstaff: 1500 },
    insurance_yearly_age2plus: { staff: 2000, nonstaff: 2000 },
  };
}

function priceFor({ table, code, payerType }) {
  const row = table[code];
  if (!row) return null;
  const k = payerType === "staff" ? "staff" : "nonstaff";
  return moneySenToMYR(row[k]);
}

exports.billingGetFeeCatalog = onCall({ region: "asia-southeast1" }, async (req) => {
  requireAuth(req);
  const table = feeTableFromPdf();
  return {
    ok: true,
    version: table.version,
    currency: "MYR",
    table,
    policy: {
      dueDayOptions: [5, 7],
      absenceDiscountPercent: 10,
      absenceDiscountMinDaysWithLetter: 14,
      annualFeeMonth: 1,
      commsBookMonths: [1, 5, 9],
      insuranceMinAgeMonths: 24,
      notes: [
        "Yuran pendaftaran dikira sebagai yuran bulan pendaftaran.",
        "Yuran bulan berikutnya perlu dibayar sebelum 5hb atau 7hb.",
        "Potongan 10% jika tidak hadir >14 hari dengan surat.",
      ],
    },
  };
});

function startOfMonth(d) {
  return new Date(d.getFullYear(), d.getMonth(), 1, 0, 0, 0, 0);
}

function endOfMonth(d) {
  return new Date(d.getFullYear(), d.getMonth() + 1, 0, 23, 59, 59, 999);
}

function monthNumberFromPeriod(period) {
  const m = String(period || "").match(/^\d{4}-(\d{2})$/);
  if (!m) return null;
  const n = Number(m[1]);
  return Number.isFinite(n) ? n : null;
}

function isSamePeriod(tsOrDate, period) {
  if (!tsOrDate || !period) return false;
  const d = tsOrDate.toDate ? tsOrDate.toDate() : new Date(tsOrDate);
  if (Number.isNaN(d.getTime())) return false;
  return monthKey(d) === period;
}

function childAbsenceAdjustmentForPeriod(child, period, reqData) {
  const req = reqData && typeof reqData === "object" ? reqData : {};
  const periodKey = String(period || "").trim();

  const directHasLetter = Boolean(req.hasAbsenceLetter);
  const directAbsenceDays = Number(req.absenceDaysWithLetter || 0);
  if (directHasLetter || directAbsenceDays > 0) {
    return {
      hasAbsenceLetter: directHasLetter,
      absenceDaysWithLetter: Number.isFinite(directAbsenceDays) ? Math.max(0, Math.round(directAbsenceDays)) : 0,
      source: "request",
    };
  }

  const byChild = req.absenceAdjustmentsByChild && typeof req.absenceAdjustmentsByChild === "object"
    ? req.absenceAdjustmentsByChild
    : null;
  const childId = child && child.id ? String(child.id).trim() : "";
  if (byChild && childId && byChild[childId] && typeof byChild[childId] === "object") {
    const childReq = byChild[childId];
    const childHasLetter = Boolean(childReq.hasAbsenceLetter);
    const childAbsenceDays = Number(childReq.absenceDaysWithLetter || 0);
    return {
      hasAbsenceLetter: childHasLetter,
      absenceDaysWithLetter: Number.isFinite(childAbsenceDays) ? Math.max(0, Math.round(childAbsenceDays)) : 0,
      source: "request-child",
    };
  }

  const childData = child && typeof child === "object" ? child : {};
  const childPeriod = String(childData.absenceLetterPeriod || "").trim();
  const childHasLetter = Boolean(childData.absenceLetterApproved);
  const childAbsenceDays = Number(childData.absenceLetterDays || 0);
  if (childHasLetter && childPeriod && childPeriod === periodKey) {
    return {
      hasAbsenceLetter: true,
      absenceDaysWithLetter: Number.isFinite(childAbsenceDays) ? Math.max(0, Math.round(childAbsenceDays)) : 0,
      source: "child-profile",
    };
  }

  return {
    hasAbsenceLetter: false,
    absenceDaysWithLetter: 0,
    source: "none",
  };
}

function linkedChildIdsFromParent(parentData, fallbackChildId) {
  const ids = [];

  const addId = (raw) => {
    const v = String(raw || "").trim();
    if (!v || ids.includes(v)) return;
    ids.push(v);
  };

  const childIds = parentData && Array.isArray(parentData.childIds) ? parentData.childIds : [];
  for (const raw of childIds) addId(raw);

  const childRefs = parentData && Array.isArray(parentData.childRefs) ? parentData.childRefs : [];
  for (const raw of childRefs) {
    const ref = String(raw || "").trim();
    if (!ref) continue;
    const parts = ref.split("/");
    addId(parts[parts.length - 1]);
  }

  addId(parentData && parentData.childId);
  addId(fallbackChildId);
  return ids;
}

function effectivePayerTypeFromParent(parentData) {
  return normalizePayerType(
    parentData && (parentData.payerType || parentData.payer_category || parentData.isStaff)
      ? "staff"
      : "nonstaff",
  );
}

async function buildFamilyInvoiceFromPdfPolicy({ parentId, parentData, period, reqData, fallbackChildId }) {
  const childIds = linkedChildIdsFromParent(parentData, fallbackChildId);
  if (!childIds.length) {
    return { ok: false, reason: "no-linked-children", childIds: [] };
  }

  const payerType = effectivePayerTypeFromParent(parentData || {});
  const invoiceItems = [];
  const childSummaries = [];
  const appliedRegistrationChildIds = [];
  const appliedUniformChildIds = [];
  const managementReviewChildIds = [];
  const childNames = [];
  let totalSen = 0;
  let subTotalSen = 0;
  let dueDate = null;
  let dueDay = null;
  let pricingVersion = "";

  for (const childId of childIds) {
    const calc = await buildInvoiceItemsFromPdfPolicy({
      parentId,
      childId,
      period,
      reqData,
      payerType,
    });

    if (!calc || !Array.isArray(calc.items) || !calc.items.length) {
      continue;
    }

    const childLabel = String(calc.childName || childId).trim() || childId;
    if (!childNames.includes(childLabel)) {
      childNames.push(childLabel);
    }

    const isMultiChild = childIds.length > 1;
    for (const item of calc.items) {
      invoiceItems.push({
        ...item,
        childId,
        childName: childLabel,
        description: isMultiChild ? `${childLabel} - ${String(item.description || item.code || "Item")}` : item.description,
      });
    }

    totalSen += moneySenToMYR(calc.totalSen);
    subTotalSen += moneySenToMYR(calc.subTotalSen);
    pricingVersion = pricingVersion || String(calc.table && calc.table.version ? calc.table.version : "");
    if (!dueDate || (calc.dueDate && calc.dueDate.getTime() < dueDate.getTime())) {
      dueDate = calc.dueDate;
      dueDay = calc.dueDay;
    }

    childSummaries.push({
      childId,
      childName: childLabel,
      totalSen: moneySenToMYR(calc.totalSen),
      subTotalSen: moneySenToMYR(calc.subTotalSen),
      dueDay: Number(calc.dueDay || 7),
      billingMeta: calc.meta || {},
      itemCount: calc.items.length,
    });

    if (calc.meta && calc.meta.registrationMonth) {
      appliedRegistrationChildIds.push(childId);
    }
    if (calc.meta && calc.meta.uniformCharged) {
      appliedUniformChildIds.push(childId);
    }
    if (calc.meta && calc.meta.managementReviewRecommended) {
      managementReviewChildIds.push(childId);
    }
  }

  if (!invoiceItems.length) {
    return {
      ok: false,
      reason: "no-billable-items",
      childIds,
      childNames,
    };
  }

  const policyNotes = dedupePolicyNotes([
    `Bayaran bulan berikutnya hendaklah dijelaskan sebelum ${dueDay === 5 ? 5 : 7}hb.`,
    "Yuran bulanan dibayar penuh jika tidak hadir tanpa notis bertulis.",
    "Resit bayaran dikeluarkan selepas pembayaran diterima.",
    ...childSummaries.flatMap((summary) => {
      const notes = Array.isArray(summary.billingMeta && summary.billingMeta.policyNotes)
        ? summary.billingMeta.policyNotes
        : [];
      if (childIds.length <= 1) return notes;
      return notes.map((note) => `${summary.childName}: ${note}`);
    }),
  ]);

  return {
    ok: true,
    parentId,
    period,
    payerType,
    childIds,
    childNames,
    childNameSummary: childNames.join(", "),
    childSummaries,
    items: invoiceItems,
    subTotalSen: moneySenToMYR(subTotalSen),
    totalSen: moneySenToMYR(totalSen),
    dueDate,
    dueDay: dueDay === 5 ? 5 : 7,
    pricingVersion,
    registrationFeeChildIds: appliedRegistrationChildIds,
    uniformFeeChildIds: appliedUniformChildIds,
    billingMeta: {
      invoiceScope: "family",
      childCount: childSummaries.length,
      children: childSummaries,
      policyNotes,
      managementReviewRecommended: managementReviewChildIds.length > 0,
      managementReviewChildIds,
    },
  };
}

async function createParentInvoiceForPeriod({ req, parentId, parentData, period, reqData, createdByKind, fallbackChildId }) {
  const invoiceCol = db.collection("parents").doc(parentId).collection("invoices");
  const existing = await invoiceCol.where("period", "==", period).limit(1).get();
  if (!existing.empty) {
    const doc = existing.docs[0];
    const existingData = doc.data() || {};
    if (String(existingData.status || "").toLowerCase() !== "paid") {
      await repairInvoiceFromEquivalentPaidCopy({ invoiceRef: doc.ref, invoiceData: existingData });
    }
    return { ok: true, already: true, invoiceId: doc.id, reason: "already-exists" };
  }

  const calc = await buildFamilyInvoiceFromPdfPolicy({
    parentId,
    parentData,
    period,
    reqData,
    fallbackChildId,
  });
  if (!calc.ok) {
    return calc;
  }

  const equivalentPaid = await findEquivalentPaidInvoice({
    period,
    childIds: calc.childIds,
  });

  const ref = invoiceCol.doc();
  const invoiceData = {
    period,
    currency: "MYR",
    status: equivalentPaid ? "paid" : "unpaid",
    payerType: calc.payerType,
    childId: calc.childIds.length === 1 ? calc.childIds[0] : null,
    childName: calc.childNameSummary || null,
    childIds: calc.childIds,
    childCoverageKey: childCoverageKey(period, calc.childIds),
    childNames: calc.childNames,
    items: calc.items,
    subTotalSen: calc.subTotalSen,
    totalSen: calc.totalSen,
    pricingVersion: calc.pricingVersion,
    dueDate: calc.dueDate,
    billingMeta: calc.billingMeta,
    createdAt: FieldValue.serverTimestamp(),
    createdBy: { uid: req.auth.uid, kind: createdByKind || "billing" },
  };
  if (equivalentPaid) {
    Object.assign(invoiceData, buildPaidInvoiceSyncPatch(equivalentPaid.data, equivalentPaid.ref.path));
  }

  await ref.set(invoiceData, { merge: false });

  if (calc.registrationFeeChildIds && calc.registrationFeeChildIds.length) {
    await Promise.all(calc.registrationFeeChildIds.map(async (childId) => {
      try {
        await db.collection("children").doc(childId).set({
          registrationFeeAppliedPeriod: period,
        }, { merge: true });
      } catch (e) {
        console.error("registration-period-mark-failed", { childId, period, error: String(e && e.message ? e.message : e) });
      }
    }));
  }

  if (calc.uniformFeeChildIds && calc.uniformFeeChildIds.length) {
    await Promise.all(calc.uniformFeeChildIds.map(async (childId) => {
      try {
        await db.collection("children").doc(childId).set({
          uniformFeeAppliedPeriod: period,
        }, { merge: true });
      } catch (e) {
        console.error("uniform-period-mark-failed", { childId, period, error: String(e && e.message ? e.message : e) });
      }
    }));
  }

  return {
    ok: true,
    invoiceId: ref.id,
    childIds: calc.childIds,
    childNames: calc.childNames,
    totalSen: calc.totalSen,
  };
}

function careTypeToCode({ careType, feePlan, ageBand }) {
  const v = String(careType || "").trim().toLowerCase();
  const fp = String(feePlan || "").trim().toLowerCase();
  if (v === "fulltime") {
    return ageBand === "3m_2y" ? "monthly_fulltime_3m_2y" : "monthly_fulltime_2y_4y";
  }
  if (v === "transit") return "transit_2h_month";
  if (v === "transit_halfday_month") return "transit_halfday_month";
  if (v === "transit_2h_month") return "transit_2h_month";
  if (v === "transit_schoolholiday_month") return "transit_schoolholiday_month";
  if (v === "transit_1day") return "transit_1day";
  if (v === "transit_1week") return "transit_1week";
  if (v === "transit_1hour") return "transit_1hour";
  if (fp === "transit") return "transit_2h_month";
  if (fp === "monthly") return ageBand === "3m_2y" ? "monthly_fulltime_3m_2y" : "monthly_fulltime_2y_4y";
  return ageBand === "3m_2y" ? "monthly_fulltime_3m_2y" : "monthly_fulltime_2y_4y";
}

function numericHoursOrNull(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) return null;
  return parsed;
}

function billingHintsForChild(child, reqData) {
  const req = reqData && typeof reqData === "object" ? reqData : {};
  const childId = child && child.id ? String(child.id).trim() : "";
  const byChild = req.billingHintsByChild && typeof req.billingHintsByChild === "object"
    ? req.billingHintsByChild
    : null;

  if (byChild && childId && byChild[childId] && typeof byChild[childId] === "object") {
    return byChild[childId];
  }
  return req;
}

function attendanceTimestampToDate(raw) {
  if (!raw) return null;
  const dt = raw.toDate ? raw.toDate() : new Date(raw);
  return Number.isNaN(dt.getTime()) ? null : dt;
}

function attendanceDateKey(dt) {
  return `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, "0")}-${String(dt.getDate()).padStart(2, "0")}`;
}

function attendanceIsoWeekKey(dt) {
  const utc = new Date(Date.UTC(dt.getFullYear(), dt.getMonth(), dt.getDate()));
  const day = utc.getUTCDay() || 7;
  utc.setUTCDate(utc.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(utc.getUTCFullYear(), 0, 1));
  const weekNo = Math.ceil((((utc - yearStart) / 86400000) + 1) / 7);
  return `${utc.getUTCFullYear()}-W${String(weekNo).padStart(2, "0")}`;
}

function transitUsageFromAttendanceRows(rows) {
  const dayKeys = new Set();
  const weekKeys = new Set();
  const hoursByDay = new Map();
  let totalHours = 0;

  for (const r of rows || []) {
    const inRaw = r.check_in_time || r.checkInTime || r.checkinTime || null;
    const outRaw = r.check_out_time || r.checkOutTime || r.checkoutTime || null;
    const checkIn = attendanceTimestampToDate(inRaw);
    const checkOut = attendanceTimestampToDate(outRaw);
    const anchor = checkIn || checkOut;

    if (anchor) {
      dayKeys.add(attendanceDateKey(anchor));
      weekKeys.add(attendanceIsoWeekKey(anchor));
    }

    if (checkIn && checkOut) {
      const rawHours = (checkOut.getTime() - checkIn.getTime()) / (60 * 60 * 1000);
      if (Number.isFinite(rawHours) && rawHours > 0) {
        totalHours += rawHours;
        const dayKey = attendanceDateKey(anchor || checkIn);
        hoursByDay.set(dayKey, Number(hoursByDay.get(dayKey) || 0) + rawHours);
      }
    }
  }

  const distinctAttendanceDays = dayKeys.size;
  const averageDailyHours = distinctAttendanceDays > 0 ? totalHours / distinctAttendanceDays : 0;
  let maxDailyHours = 0;
  for (const value of hoursByDay.values()) {
    if (Number.isFinite(value) && value > maxDailyHours) {
      maxDailyHours = value;
    }
  }

  return {
    dayCount: dayKeys.size,
    weekCount: weekKeys.size,
    hourCount: Math.max(0, Math.ceil(totalHours)),
    totalHours,
    averageDailyHours,
    maxDailyHours,
  };
}

function resolveTransitDurationCode({ child, reqData, transitUsage }) {
  const hints = billingHintsForChild(child, reqData);
  const explicitDurationHours = numericHoursOrNull(
    hints.careDurationHours
    || hints.transitDurationHours
    || (child && (child.careDurationHours || child.transitDurationHours || child.dailyCareHours))
  );
  const attendanceDurationHours = numericHoursOrNull(transitUsage && transitUsage.averageDailyHours);
  const resolvedDurationHours = explicitDurationHours != null ? explicitDurationHours : attendanceDurationHours;

  if (resolvedDurationHours != null) {
    return resolvedDurationHours <= 2.25 ? "transit_2h_month" : "transit_halfday_month";
  }

  return "transit_2h_month";
}

function resolveTransitMonthlyCode({ child, reqData, transitUsage, months }) {
  const hints = billingHintsForChild(child, reqData);
  const requestedSchoolHoliday = Boolean(
    hints.schoolHolidayTransit
    || hints.isSchoolHolidayTransit
    || (child && (child.schoolHolidayTransit || child.isSchoolHolidayTransit || child.transitSchoolHoliday))
  );
  if (requestedSchoolHoliday && Number.isFinite(Number(months)) && Number(months) >= 48) {
    return "transit_schoolholiday_month";
  }

  return resolveTransitDurationCode({ child, reqData, transitUsage });
}

function resolveBillingBaseCode({ child, feePlan, careType, ageBand, transitUsage, reqData, months }) {
  const normalizedCareType = String(careType || "").trim().toLowerCase();
  const normalizedFeePlan = String(feePlan || "").trim().toLowerCase();

  if ([
    "transit_halfday_month",
    "transit_2h_month",
    "transit_1day",
    "transit_1week",
    "transit_1hour",
  ].includes(normalizedCareType)) {
    return normalizedCareType;
  }

  if ("transit_schoolholiday_month" === normalizedCareType) {
    return Number.isFinite(Number(months)) && Number(months) >= 48
      ? normalizedCareType
      : resolveTransitDurationCode({ child, reqData, transitUsage });
  }

  if (normalizedCareType === "fulltime" || normalizedFeePlan === "monthly") {
    return ageBand === "3m_2y" ? "monthly_fulltime_3m_2y" : "monthly_fulltime_2y_4y";
  }

  if (normalizedCareType === "transit"
      || normalizedFeePlan === "transit") {
    return resolveTransitMonthlyCode({ child, reqData, transitUsage, months });
  }

  return careTypeToCode({ careType: normalizedCareType, feePlan: normalizedFeePlan, ageBand });
}

function buildBaseFeeItem({ baseCode, unitPriceSen, transitUsage }) {
  if (unitPriceSen == null) return null;

  if (baseCode === "transit_1day") {
    const qty = Number(transitUsage && transitUsage.dayCount ? transitUsage.dayCount : 0);
    if (qty <= 0) return null;
    return {
      code: baseCode,
      description: "Transit 1 Hari",
      qty,
      unit: "day",
      unitPriceSen,
      amountSen: unitPriceSen * qty,
    };
  }

  if (baseCode === "transit_1week") {
    const qty = Number(transitUsage && transitUsage.weekCount ? transitUsage.weekCount : 0);
    if (qty <= 0) return null;
    return {
      code: baseCode,
      description: "Transit 1 Minggu",
      qty,
      unit: "week",
      unitPriceSen,
      amountSen: unitPriceSen * qty,
    };
  }

  if (baseCode === "transit_1hour") {
    const qty = Number(transitUsage && transitUsage.hourCount ? transitUsage.hourCount : 0);
    if (qty <= 0) return null;
    return {
      code: baseCode,
      description: "Transit 1 Jam",
      qty,
      unit: "hour",
      unitPriceSen,
      amountSen: unitPriceSen * qty,
    };
  }

  return {
    code: baseCode,
    description: baseCode.startsWith("transit_") ? "Yuran Transit" : "Yuran Asas Bulanan",
    qty: 1,
    unit: "month",
    unitPriceSen,
    amountSen: unitPriceSen,
  };
}

function uniformItemForPeriod({ child, months, periodKey, isRegistrationMonth }) {
  if (!child) return null;

  const uniformFeeSen = moneySenToMYR(child.uniformFeeSen);
  if (uniformFeeSen <= 0) return null;

  if (months == null || months < 36 || months >= 60) return null;

  const configuredPeriod = String(child.uniformChargePeriod || "").trim();
  const appliedPeriod = String(child.uniformFeeAppliedPeriod || "").trim();
  const shouldCharge = configuredPeriod ? configuredPeriod === periodKey : isRegistrationMonth;
  if (!shouldCharge || appliedPeriod === periodKey) return null;

  return {
    code: "uniform_current_price",
    description: String(child.uniformFeeDescription || "").trim() || "Uniform Taska (3 & 4 tahun)",
    qty: 1,
    unit: "oneoff",
    unitPriceSen: uniformFeeSen,
    amountSen: uniformFeeSen,
  };
}

function dedupePolicyNotes(notes) {
  const seen = new Set();
  const out = [];
  for (const note of notes || []) {
    const text = String(note || "").trim();
    if (!text || seen.has(text)) continue;
    seen.add(text);
    out.push(text);
  }
  return out;
}

function overtimeBucketsFromAttendanceRows(rows) {
  let hAfter530 = 0;
  let h8to12 = 0;
  let h12to7 = 0;
  const lateNightDays = new Set();
  const overnightDays = new Set();

  for (const r of rows || []) {
    const outRaw = r.check_out_time || r.checkOutTime || r.checkoutTime || null;
    if (!outRaw) continue;
    const out = outRaw.toDate ? outRaw.toDate() : new Date(outRaw);
    if (Number.isNaN(out.getTime())) continue;

    const hh = out.getHours() + (out.getMinutes() / 60);
    if (hh > 17.5 && hh <= 20) {
      hAfter530 += (hh - 17.5);
    } else if (hh > 20 && hh < 24) {
      hAfter530 += 2.5;
      h8to12 += (hh - 20);
      lateNightDays.add(attendanceDateKey(out));
    } else if (hh >= 0 && hh < 7) {
      // Overnight bucket; conservative approximation when only checkout clock-time is known.
      h12to7 += hh;
      overnightDays.add(attendanceDateKey(out));
    }
  }

  return {
    after530Hours: Math.max(0, Math.ceil(hAfter530)),
    h8to12Hours: Math.max(0, Math.ceil(h8to12)),
    h12to7Hours: Math.max(0, Math.ceil(h12to7)),
    lateNightOccurrences: lateNightDays.size,
    overnightOccurrences: overnightDays.size,
    managementReviewRecommended: lateNightDays.size > 10 || overnightDays.size > 10,
  };
}

async function buildInvoiceItemsFromPdfPolicy({ parentId, childId, period, reqData, payerType }) {
  const table = feeTableFromPdf();
  const now = new Date();
  const periodDate = new Date(now.getFullYear(), now.getMonth(), 1);
  if (period) {
    const m = String(period).match(/^(\d{4})-(\d{2})$/);
    if (m) periodDate.setFullYear(Number(m[1]), Number(m[2]) - 1, 1);
  }

  let child = null;
  if (childId) {
    const childSnap = await db.collection("children").doc(childId).get();
    if (childSnap.exists) child = childSnap.data() || {};
  }

  const childName = child ? String(child.name || child.childName || "").trim() : "";
  const dob = child ? parseIsoDateOnly(child.birthDate) : null;
  const months = dob ? ageInMonths(periodDate, dob) : null;
  const defaultAgeProfile = resolveAgeProfile(months);
  const ageBand = defaultAgeProfile.ageBand;
  const effectivePayerType = (child && child.staffChild === true) ? "staff" : payerType;

  const feePlan = child ? String(child.feePlan || "").trim().toLowerCase() : "";
  const careType = child ? String(child.careType || "fulltime") : "fulltime";
  let attendanceRows = [];
  try {
    if (childId) {
      const s = startOfMonth(periodDate);
      const e = endOfMonth(periodDate);
      const att = await db.collection("attendance")
        .where("childId", "==", childId)
        .where("date", ">=", s)
        .where("date", "<=", e)
        .get();
      attendanceRows = att.docs.map((d) => d.data() || {});
    }
  } catch (err) {
    console.error("attendance-fetch-failed", err);
  }

  const transitUsage = transitUsageFromAttendanceRows(attendanceRows);
  const baseCode = resolveBillingBaseCode({
    child: child ? { ...child, id: childId } : null,
    feePlan,
    careType,
    ageBand,
    transitUsage,
    reqData,
    months,
  });
  const ageProfile = resolveBillingAgePolicy({ months, baseCode });
  const items = [];
  const periodKey = period || monthKey(now);

  const registrationType = baseCode.startsWith("monthly_") ? "fulltime" : "transit";
  const regCode = registrationType === "transit"
    ? "registration_transit_oneoff"
    : "registration_fulltime_oneoff";
  const isRegistrationMonth = registrationChargeRequired(child, periodKey);

  if (isRegistrationMonth) {
    const regSen = priceFor({ table, code: regCode, payerType: effectivePayerType });
    if (regSen != null) {
      items.push({
        code: regCode,
        description: registrationType === "transit"
          ? "Yuran Pendaftaran Transit (Kiraan bulan pendaftaran)"
          : "Yuran Pendaftaran Sepenuh Masa (Kiraan bulan pendaftaran)",
        qty: 1,
        unit: "oneoff",
        unitPriceSen: regSen,
        amountSen: regSen,
      });
    }
  } else {
    const baseSen = priceFor({ table, code: baseCode, payerType: effectivePayerType });
    const baseItem = buildBaseFeeItem({ baseCode, unitPriceSen: baseSen, transitUsage });
    if (baseItem) {
      items.push(baseItem);
    }
  }

  const periodMonth = monthNumberFromPeriod(periodKey);

  // Annual fee (default January) unless already paid for year.
  if (periodMonth === 1) {
    const annualSen = priceFor({ table, code: "annual_fee_yearly", payerType: effectivePayerType });
    if (annualSen != null) {
      items.push({
        code: "annual_fee_yearly",
        description: "Yuran Tahunan",
        qty: 1,
        unit: "year",
        unitPriceSen: annualSen,
        amountSen: annualSen,
      });
    }
  }

  // Communication book every 4 months: Jan, May, Sep.
  if (periodMonth === 1 || periodMonth === 5 || periodMonth === 9) {
    const bookSen = priceFor({ table, code: "comms_book_4months", payerType: effectivePayerType });
    if (bookSen != null) {
      items.push({
        code: "comms_book_4months",
        description: "Buku Komunikasi (4 bulan)",
        qty: 1,
        unit: "4months",
        unitPriceSen: bookSen,
        amountSen: bookSen,
      });
    }
  }

  // Insurance yearly for age >= 2 years (default January).
  if (periodMonth === 1 && months != null && months >= 24) {
    const insSen = priceFor({ table, code: "insurance_yearly_age2plus", payerType: effectivePayerType });
    if (insSen != null) {
      items.push({
        code: "insurance_yearly_age2plus",
        description: "Insurans Tahunan (Umur 2 tahun ke atas)",
        qty: 1,
        unit: "year",
        unitPriceSen: insSen,
        amountSen: insSen,
      });
    }
  }

  // Transport fee if enabled per child.
  if (child && child.transportFromTadika === true) {
    const tSen = priceFor({ table, code: "transport_tadika_month", payerType: effectivePayerType });
    if (tSen != null) {
      items.push({
        code: "transport_tadika_month",
        description: "Pengangkutan Dari Tadika",
        qty: 1,
        unit: "month",
        unitPriceSen: tSen,
        amountSen: tSen,
      });
    }
  }

  const uniformItem = uniformItemForPeriod({ child, months, periodKey, isRegistrationMonth });
  if (uniformItem) {
    items.push(uniformItem);
  }

  // Attendance-based overtime buckets.
  let overtime = {
    after530Hours: 0,
    h8to12Hours: 0,
    h12to7Hours: 0,
  };

  overtime = overtimeBucketsFromAttendanceRows(attendanceRows);

  // Optional manual override from caller.
  const mOver = (reqData && reqData.manualOvertime) ? reqData.manualOvertime : null;
  if (mOver && typeof mOver === "object") {
    overtime = {
      after530Hours: Number.isFinite(Number(mOver.after530Hours)) ? Math.max(0, Math.round(Number(mOver.after530Hours))) : overtime.after530Hours,
      h8to12Hours: Number.isFinite(Number(mOver.h8to12Hours)) ? Math.max(0, Math.round(Number(mOver.h8to12Hours))) : overtime.h8to12Hours,
      h12to7Hours: Number.isFinite(Number(mOver.h12to7Hours)) ? Math.max(0, Math.round(Number(mOver.h12to7Hours))) : overtime.h12to7Hours,
    };
  }

  const otMap = [
    { code: "overtime_after_530", label: "Lebih Masa Selepas 5:30 PM", qty: overtime.after530Hours },
    { code: "overtime_8pm_12am", label: "Lebih Masa 8:00 PM - 12:00 AM", qty: overtime.h8to12Hours },
    { code: "overtime_12am_7am", label: "Lebih Masa 12:00 AM - 7:00 AM", qty: overtime.h12to7Hours },
  ];
  for (const row of otMap) {
    if (!row.qty || row.qty <= 0) continue;
    const unitPriceSen = priceFor({ table, code: row.code, payerType: effectivePayerType });
    if (unitPriceSen == null) continue;
    items.push({
      code: row.code,
      description: row.label,
      qty: row.qty,
      unit: "hour",
      unitPriceSen,
      amountSen: unitPriceSen * row.qty,
    });
  }

  // 10% discount for absence >14 days with supporting letter.
  const absenceAdjustment = childAbsenceAdjustmentForPeriod(child ? { ...child, id: childId } : null, periodKey, reqData);
  const absDays = Number(absenceAdjustment.absenceDaysWithLetter || 0);
  const hasLetter = Boolean(absenceAdjustment.hasAbsenceLetter);
  if (hasLetter && Number.isFinite(absDays) && absDays > 14) {
    const baseItem = items.find((i) => i && i.code && (i.code.startsWith("monthly_") || i.code.startsWith("transit_")));
    if (baseItem && Number(baseItem.amountSen) > 0) {
      const discountSen = Math.round(Number(baseItem.amountSen) * 0.10);
      if (discountSen > 0) {
        items.push({
          code: "discount_absence_14days",
          description: "Potongan 10% (Tidak Hadir >14 Hari + Surat)",
          qty: 1,
          unit: "discount",
          unitPriceSen: -discountSen,
          amountSen: -discountSen,
        });
      }
    }
  }

  const subTotalSen = items.reduce((a, b) => a + moneySenToMYR(b.amountSen), 0);
  const totalSen = moneySenToMYR(subTotalSen);
  const dueDayRaw = child && Number.isFinite(Number(child.billingDueDay)) ? Number(child.billingDueDay) : 7;
  const dueDay = dueDayRaw === 5 ? 5 : 7;
  const dueDate = new Date(periodDate.getFullYear(), periodDate.getMonth(), dueDay, 23, 59, 59);
  const policyNotes = dedupePolicyNotes([
    isRegistrationMonth
      ? "Bayaran pendaftaran dan bayaran ketika mendaftar tidak akan dikembalikan."
      : null,
    uniformItem
      ? "Uniform dikenakan sebagai caj semasa untuk kanak-kanak 3 dan 4 tahun."
      : null,
    hasLetter && Number.isFinite(absDays) && absDays > 14
      ? "Potongan 10% telah digunakan kerana tidak hadir melebihi 14 hari dengan surat."
      : null,
    overtime.managementReviewRecommended
      ? "Lebih masa selepas 8:00 malam atau selepas 12:00 malam melebihi 10 hari dan wajar disemak atas budi bicara pengurusan."
      : null,
  ]);

  if (ageProfile.agePolicyReason === "school_holiday_requires_age_4_plus") {
    policyNotes.unshift("Transit penuh cuti sekolah hanya dibenarkan untuk umur 4 tahun ke atas.");
  } else if (ageProfile.agePolicyReason === "school_holiday_requires_known_age") {
    policyNotes.unshift("Tarikh lahir diperlukan untuk menggunakan transit penuh cuti sekolah.");
  } else if (ageProfile.ageOutOfPolicy) {
    policyNotes.unshift("Umur kanak-kanak berada di luar julat yuran PDF (3 bulan hingga bawah 4 tahun). Invois ini menggunakan kadar terdekat dan perlu disemak secara manual.");
  }

  return {
    child,
    childName,
    table,
    payerType: effectivePayerType,
    items,
    subTotalSen,
    totalSen,
    dueDate,
    dueDay,
    meta: {
      careType,
      ageBand,
      months,
      registrationMonth: isRegistrationMonth,
      transitUsage,
      uniformCharged: Boolean(uniformItem),
      policyNotes,
      managementReviewRecommended: Boolean(overtime.managementReviewRecommended || ageProfile.ageOutOfPolicy),
      overtime,
      absenceAdjustment,
      resolvedBaseCode: baseCode,
      ageOutOfPolicy: Boolean(ageProfile.ageOutOfPolicy),
      agePolicyReason: ageProfile.agePolicyReason,
      resolvedAgeBand: ageBand,
    },
  };
}

exports.billingCreateDemoInvoiceForCurrentMonth = onCall({ region: "asia-southeast1" }, async (req) => {
  requireAuth(req);
  const parentId = (req.data && req.data.parentId) ? String(req.data.parentId).trim() : "";
  const childId = (req.data && req.data.childId) ? String(req.data.childId).trim() : "";
  if (!parentId) return { ok: false, reason: "missing-parentId" };

  const period = monthKey(new Date());
  const { parentData } = await assertParentOwnerByPhone({ parentId, authToken: req.auth.token });
  return createParentInvoiceForPeriod({
    req,
    parentId,
    parentData,
    period,
    reqData: req.data || {},
    createdByKind: "parent-demo",
    fallbackChildId: childId,
  });
});

exports.billingCreateDummyCheckoutSession = onCall({ region: "asia-southeast1" }, async (req) => {
  requireAuth(req);
  const parentId = (req.data && req.data.parentId) ? String(req.data.parentId).trim() : "";
  const invoiceId = (req.data && req.data.invoiceId) ? String(req.data.invoiceId).trim() : "";
  if (!parentId || !invoiceId) return { ok: false, reason: "missing-args" };

  await assertParentOwnerByPhone({ parentId, authToken: req.auth.token });

  const invoiceRef = db.collection("parents").doc(parentId).collection("invoices").doc(invoiceId);
  const invoiceSnap = await invoiceRef.get();
  if (!invoiceSnap.exists) return { ok: false, reason: "invoice-not-found" };

  let inv = invoiceSnap.data() || {};
  if (String(inv.status || "").toLowerCase() !== "paid") {
    const repaired = await repairInvoiceFromEquivalentPaidCopy({ invoiceRef, invoiceData: inv });
    inv = repaired.invoiceData || inv;
  }
  const status = String(inv.status || "").toLowerCase();
  if (status === "paid") return { ok: false, reason: "already-paid" };

  const totalSen = moneySenToMYR(inv.totalSen);
  const sessionRef = invoiceRef.collection("sessions").doc();

  await sessionRef.set({
    mode: "dummy",
    status: "pending",
    currency: String(inv.currency || "MYR"),
    amountSen: totalSen,
    createdAt: FieldValue.serverTimestamp(),
    createdByUid: req.auth.uid,
  });

  return {
    ok: true,
    sessionId: sessionRef.id,
    amountSen: totalSen,
    currency: String(inv.currency || "MYR"),
  };
});

exports.billingCreateDemoCheckoutSession = exports.billingCreateDummyCheckoutSession;

exports.billingRepairInvoiceStatus = onCall({ region: "asia-southeast1" }, async (req) => {
  requireAuth(req);
  const parentId = (req.data && req.data.parentId) ? String(req.data.parentId).trim() : "";
  const invoiceId = (req.data && req.data.invoiceId) ? String(req.data.invoiceId).trim() : "";
  if (!parentId || !invoiceId) return { ok: false, reason: "missing-args" };

  await assertParentOwnerByPhone({ parentId, authToken: req.auth.token });

  const invoiceRef = db.collection("parents").doc(parentId).collection("invoices").doc(invoiceId);
  const invoiceSnap = await invoiceRef.get();
  if (!invoiceSnap.exists) return { ok: false, reason: "invoice-not-found" };

  let inv = invoiceSnap.data() || {};
  const repaired = await repairInvoiceFromEquivalentPaidCopy({ invoiceRef, invoiceData: inv });
  inv = repaired.invoiceData || inv;
  const status = String(inv.status || "unpaid").toLowerCase();

  return {
    ok: true,
    repaired: repaired.repaired === true,
    status,
    paid: status === "paid",
    childCoverageKey: invoiceChildCoverageKey(inv),
  };
});

exports.billingCompleteDummyCheckoutSession = onCall({ region: "asia-southeast1" }, async (req) => {
  requireAuth(req);
  const parentId = (req.data && req.data.parentId) ? String(req.data.parentId).trim() : "";
  const invoiceId = (req.data && req.data.invoiceId) ? String(req.data.invoiceId).trim() : "";
  const sessionId = (req.data && req.data.sessionId) ? String(req.data.sessionId).trim() : "";
  const method = (req.data && req.data.method) ? String(req.data.method).trim() : "FPX";
  const bank = (req.data && req.data.bank) ? String(req.data.bank).trim() : "";
  if (!parentId || !invoiceId || !sessionId) return { ok: false, reason: "missing-args" };

  await assertParentOwnerByPhone({ parentId, authToken: req.auth.token });

  const invoiceRef = db.collection("parents").doc(parentId).collection("invoices").doc(invoiceId);
  const sessionRef = invoiceRef.collection("sessions").doc(sessionId);
  const paymentsCol = db.collection("parents").doc(parentId).collection("payments");

  const res = await db.runTransaction(async (tx) => {
    const [invSnap, sessSnap] = await Promise.all([tx.get(invoiceRef), tx.get(sessionRef)]);
    if (!invSnap.exists) return { ok: false, reason: "invoice-not-found" };
    if (!sessSnap.exists) return { ok: false, reason: "session-not-found" };

    const inv = invSnap.data() || {};
    const sess = sessSnap.data() || {};
    if (String(inv.status || "").toLowerCase() === "paid") return { ok: false, reason: "already-paid" };
    if (String(sess.status || "").toLowerCase() !== "pending") return { ok: false, reason: "session-not-pending" };

    const totalSen = moneySenToMYR(inv.totalSen);
    const payRef = paymentsCol.doc();
    const receipt = `RCPT-${new Date().toISOString().slice(0, 10).replace(/-/g, "")}-${payRef.id.slice(0, 6).toUpperCase()}`;

    tx.set(payRef, {
      provider: "dummy",
      status: "succeeded",
      invoiceId,
      currency: String(inv.currency || "MYR"),
      amountSen: totalSen,
      method,
      bank: bank || null,
      receiptNo: receipt,
      createdAt: FieldValue.serverTimestamp(),
      createdByUid: req.auth.uid,
    });

    tx.update(invoiceRef, {
      status: "paid",
      paidAt: FieldValue.serverTimestamp(),
      paidMethod: method,
      paidBank: bank || null,
      paidAmountSen: totalSen,
      paidReceiptNo: receipt,
      paidPaymentId: payRef.id,
      updatedAt: FieldValue.serverTimestamp(),
    });

    tx.update(sessionRef, {
      status: "succeeded",
      completedAt: FieldValue.serverTimestamp(),
      method,
      bank: bank || null,
      paymentId: payRef.id,
    });

    return { ok: true, paymentId: payRef.id, receiptNo: receipt };
  });

  return res;
});

exports.billingCompleteDemoCheckoutSession = exports.billingCompleteDummyCheckoutSession;

exports.syncSharedChildInvoicePayments = onDocumentWritten("parents/{parentId}/invoices/{invoiceId}", async (event) => {
  const after = event.data && event.data.after ? event.data.after.data() : null;
  const before = event.data && event.data.before ? event.data.before.data() : null;
  if (!after) return null;

  const afterStatus = String(after.status || "").toLowerCase();
  const beforeStatus = String(before && before.status ? before.status : "").toLowerCase();
  const paymentChanged = afterStatus === "paid" && (
    beforeStatus !== "paid" ||
    String(before && before.paidReceiptNo ? before.paidReceiptNo : "") !== String(after.paidReceiptNo || "") ||
    String(before && before.paidPaymentId ? before.paidPaymentId : "") !== String(after.paidPaymentId || "") ||
    String(before && before.paidProvider ? before.paidProvider : "") !== String(after.paidProvider || "")
  );
  if (!paymentChanged) return null;

  await syncEquivalentPaidInvoicesFromSource({
    sourceRef: event.data.after.ref,
    sourceInvoice: after,
  });
  return null;
});
