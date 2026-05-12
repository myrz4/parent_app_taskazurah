// ✅ Firebase Functions v2 syntax
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onCall } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const { getMessaging } = require("firebase-admin/messaging");
const feeEngine = require("./fee-engine");

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

function invoiceCoverageLookupRef(coverageKey) {
  const normalizedCoverageKey = String(coverageKey || "").trim();
  return normalizedCoverageKey
    ? db.collection("billingInvoiceCoverage").doc(normalizedCoverageKey)
    : null;
}

function coveragePeriod(coverageKey) {
  const normalizedCoverageKey = String(coverageKey || "").trim();
  const separatorIndex = normalizedCoverageKey.indexOf("::");
  return separatorIndex >= 0 ? normalizedCoverageKey.slice(0, separatorIndex) : normalizedCoverageKey;
}

function coverageChildIds(coverageKey) {
  const normalizedCoverageKey = String(coverageKey || "").trim();
  const separatorIndex = normalizedCoverageKey.indexOf("::");
  if (separatorIndex < 0) return [];
  return uniqueSortedIds(normalizedCoverageKey.slice(separatorIndex + 2).split("|"));
}

function docRefFromPath(path) {
  const normalizedPath = String(path || "").trim();
  return normalizedPath ? db.doc(normalizedPath) : null;
}

async function loadInvoicesFromLookupPaths(invoicePaths, isValidInvoice) {
  const normalizedPaths = uniqueSortedIds(invoicePaths);
  if (!normalizedPaths.length) {
    return { matches: [], validPaths: [] };
  }

  const reads = await Promise.all(normalizedPaths.map(async (invoicePath) => {
    try {
      const invoiceRef = docRefFromPath(invoicePath);
      if (!invoiceRef) return null;
      const snap = await invoiceRef.get();
      return { invoicePath, snap };
    } catch (err) {
      console.error("billing-lookup-invoice-read-failed", invoicePath, err);
      return null;
    }
  }));

  const matches = [];
  const validPaths = [];
  for (const entry of reads) {
    if (!entry || !entry.snap || !entry.snap.exists) continue;
    const data = entry.snap.data() || {};
    if (!isValidInvoice(data)) continue;
    validPaths.push(entry.snap.ref.path);
    matches.push({ ref: entry.snap.ref, data });
  }

  return { matches, validPaths: uniqueSortedIds(validPaths) };
}

async function loadCoverageLookupInvoices(coverageKey) {
  const lookupRef = invoiceCoverageLookupRef(coverageKey);
  if (!lookupRef) return [];

  const lookupSnap = await lookupRef.get();
  if (!lookupSnap.exists) return [];

  const lookupData = lookupSnap.data() || {};
  const storedPaths = uniqueSortedIds(lookupData.invoicePaths || []);
  const { matches, validPaths } = await loadInvoicesFromLookupPaths(
    storedPaths,
    (invoiceData) => invoiceChildCoverageKey(invoiceData) === coverageKey,
  );

  if (storedPaths.join("|") !== validPaths.join("|")) {
    await lookupRef.set({
      period: coveragePeriod(coverageKey),
      childIds: coverageChildIds(coverageKey),
      childCoverageKey: coverageKey,
      invoicePaths: validPaths,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  }

  return matches;
}

async function upsertInvoiceLookupDocs({ invoiceRef, invoiceData }) {
  if (!invoiceRef || !invoiceData) return;

  const period = String(invoiceData.period || "").trim();
  const childIds = invoiceChildIds(invoiceData);
  const coverageKey = invoiceChildCoverageKey(invoiceData);
  if (!period || !childIds.length || !coverageKey) return;

  const coverageRef = invoiceCoverageLookupRef(coverageKey);
  if (!coverageRef) return;

  await coverageRef.set({
    period,
    childIds,
    childCoverageKey: coverageKey,
    invoicePaths: FieldValue.arrayUnion(invoiceRef.path),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
}

async function findEquivalentPaidInvoice({ period, childIds, excludePath = "" }) {
  const normalizedPeriod = String(period || "").trim();
  const coverageKey = childCoverageKey(normalizedPeriod, childIds);
  if (!normalizedPeriod || !coverageKey) return null;

  const invoices = await loadCoverageLookupInvoices(coverageKey);
  for (const invoice of invoices) {
    if (excludePath && invoice.ref.path === excludePath) continue;
    const data = invoice.data || {};
    if (String(data.status || "").toLowerCase() !== "paid") continue;
    return { ref: invoice.ref, data };
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
  const invoices = await loadCoverageLookupInvoices(coverageKey);
  const batch = db.batch();
  let updates = 0;

  for (const invoice of invoices) {
    if (invoice.ref.path === sourceRef.path) continue;
    const data = invoice.data || {};
    if (invoicePaymentFingerprint(data) === sourceFingerprint) continue;
    batch.set(invoice.ref, buildPaidInvoiceSyncPatch(sourceInvoice, sourceRef.path), { merge: true });
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
  const ageProfile = feeEngine.determineAgeBand(months);
  return {
    ageBand: String(ageProfile.codeSuffix || "AGE_4"),
    ageOutOfPolicy: Boolean(ageProfile.ageOutOfPolicy),
    agePolicyReason: String(ageProfile.agePolicyReason || "in_range"),
  };
}

function registrationChargeRequired(child, periodKey) {
  if (!child) return false;

  const appliedPeriod = String(child.registrationFeeAppliedPeriod || "").trim();
  if (appliedPeriod) {
    return !periodKey || appliedPeriod === String(periodKey).trim();
  }

  const registrationDate = childRegistrationDate(child);
  if (!registrationDate || Number.isNaN(registrationDate.getTime())) {
    return false;
  }

  const registrationPeriod = monthKey(registrationDate);
  return !periodKey || registrationPeriod === periodKey;
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
  const catalog = feeEngine.buildDefaultCatalog();
  return {
    version: String(catalog.version || "taska_zurah_2026"),
    table: catalog.table,
    policy: catalog.policy,
  };
}

let catalogCache = {
  ts: 0,
  catalog: null,
};

const LEGACY_BILLING_CODES = [
  "monthly_fulltime_3m_2y",
  "monthly_fulltime_2y_4y",
  "transit_halfday_month",
  "transit_2h_month",
  "transit_schoolholiday_month",
  "overtime_after_530",
  "overtime_8pm_12am",
  "transport_tadika_month",
  "registration_fulltime_oneoff",
  "registration_transit_oneoff",
  "annual_fee_yearly",
  "comms_book_oneoff",
  "insurance_oneoff_age2plus",
];

const TASKA_ZURAH_CATALOG_ID = "taska_zurah_2026";
const TASKA_ZURAH_CATALOG_VERSION = "taska_zurah_2026";

function sanitizeTransitCode(raw) {
  const v = String(raw || "").trim().toLowerCase();
  if (!v) return "";
  return /^transit_[a-z0-9_]+$/.test(v) ? v : "";
}

function normalizeCatalogDoc(raw) {
  const src = raw && typeof raw === "object" ? raw : {};
  const tableRaw = (src.table && typeof src.table === "object")
    ? src.table
    : Object.fromEntries(
      Object.entries(src).filter(([key, value]) => {
        if (["version", "active", "updatedAt", "updatedBy"].includes(key)) return false;
        return value && typeof value === "object" && Object.prototype.hasOwnProperty.call(value, "staff")
          && Object.prototype.hasOwnProperty.call(value, "nonstaff");
      }),
    );
  const table = {};

  for (const [code, value] of Object.entries(tableRaw)) {
    if (!value || typeof value !== "object") continue;
    table[code] = {
      staff: moneySenToMYR(value.staff),
      nonstaff: moneySenToMYR(value.nonstaff),
    };
  }

  return {
    version: String(src.version || TASKA_ZURAH_CATALOG_VERSION),
    table,
    active: Boolean(src.active),
    defaultTransitMonthlyCode: sanitizeTransitCode(src.defaultTransitMonthlyCode),
    policy: feeEngine.resolveFeePolicy(src.policy || {}),
  };
}

function isLegacyBillingCatalog(table) {
  const rows = table && table.table ? table.table : (table || {});
  return LEGACY_BILLING_CODES.some((code) => Object.prototype.hasOwnProperty.call(rows, code));
}

function isTaskaZurahCatalog(table) {
  const rows = table && table.table ? table.table : (table || {});
  return BILLING_REQUIRED_CODES.every((code) => Object.prototype.hasOwnProperty.call(rows, code));
}

function canonicalTaskaZurahCatalog() {
  return normalizeCatalogDoc({
    ...feeTableFromPdf(),
    version: TASKA_ZURAH_CATALOG_VERSION,
    active: true,
    defaultTransitMonthlyCode: "",
  });
}

function canonicalTaskaZurahCatalogPayload(updatedBy = "") {
  const canonical = canonicalTaskaZurahCatalog();
  return {
    version: TASKA_ZURAH_CATALOG_VERSION,
    active: true,
    table: canonical.table,
    defaultTransitMonthlyCode: "",
    policy: canonical.policy,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedBy: String(updatedBy || ""),
  };
}

async function enforceCanonicalTaskaZurahCatalog({ pruneLegacy = false, updatedBy = "" } = {}) {
  const snap = await db.collection("billingCatalog").get();
  const batch = db.batch();
  const canonicalRef = db.collection("billingCatalog").doc(TASKA_ZURAH_CATALOG_ID);

  snap.docs.forEach((doc) => {
    const normalized = normalizeCatalogDoc(doc.data() || {});
    const legacy = isLegacyBillingCatalog(normalized);
    if (legacy && pruneLegacy) {
      batch.delete(doc.ref);
      return;
    }
    if (doc.id !== TASKA_ZURAH_CATALOG_ID && doc.get("active") === true) {
      batch.set(doc.ref, { active: false }, { merge: true });
    }
  });

  batch.set(canonicalRef, canonicalTaskaZurahCatalogPayload(updatedBy), { merge: true });
  batch.set(db.collection("billingConfig").doc("current"), {
    activeCatalogId: TASKA_ZURAH_CATALOG_ID,
    defaultTransitMonthlyCode: "",
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedBy: String(updatedBy || ""),
  }, { merge: true });

  await batch.commit();
  catalogCache = { ts: 0, catalog: null };
  return canonicalTaskaZurahCatalog();
}

async function loadActiveFeeCatalog() {
  const now = Date.now();
  if (catalogCache.catalog && (now - catalogCache.ts) < 60_000) {
    return catalogCache.catalog;
  }

  const fallback = canonicalTaskaZurahCatalog();

  try {
    const pointer = await db.collection("billingConfig").doc("current").get();
    if (pointer.exists) {
      const data = pointer.data() || {};
      const activeId = String(data.activeCatalogId || "").trim();
      const configuredTransitCode = sanitizeTransitCode(data.defaultTransitMonthlyCode);
      if (activeId) {
        const catalogSnap = await db.collection("billingCatalog").doc(activeId).get();
        if (catalogSnap.exists) {
          const normalized = normalizeCatalogDoc(catalogSnap.data() || {});
          if (isTaskaZurahCatalog(normalized)) {
            normalized.defaultTransitMonthlyCode = configuredTransitCode || normalized.defaultTransitMonthlyCode || "";
            catalogCache = { ts: now, catalog: normalized };
            return normalized;
          }
          const repaired = await enforceCanonicalTaskaZurahCatalog({
            pruneLegacy: true,
            updatedBy: String(data.updatedBy || ""),
          });
          catalogCache = { ts: now, catalog: repaired };
          return repaired;
        }
      }
    }

    const activeSnap = await db.collection("billingCatalog").where("active", "==", true).limit(1).get();
    if (!activeSnap.empty) {
      const normalized = normalizeCatalogDoc(activeSnap.docs[0].data() || {});
      if (isTaskaZurahCatalog(normalized)) {
        normalized.defaultTransitMonthlyCode = normalized.defaultTransitMonthlyCode || "";
        catalogCache = { ts: now, catalog: normalized };
        return normalized;
      }
      const repaired = await enforceCanonicalTaskaZurahCatalog({
        pruneLegacy: true,
        updatedBy: String(activeSnap.docs[0].get("updatedBy") || ""),
      });
      catalogCache = { ts: now, catalog: repaired };
      return repaired;
    }

    const repaired = await enforceCanonicalTaskaZurahCatalog({ pruneLegacy: true });
    catalogCache = { ts: now, catalog: repaired };
    return repaired;
  } catch (err) {
    console.error("billing-catalog-load-failed", err);
  }

  catalogCache = { ts: now, catalog: fallback };
  return fallback;
}

function priceFor({ table, code, payerType }) {
  const row = table && table.table ? table.table[code] : table[code];
  if (!row) return null;
  const k = payerType === "staff" ? "staff" : "nonstaff";
  return moneySenToMYR(row[k]);
}

exports.billingGetFeeCatalog = onCall({ region: "asia-southeast1" }, async (req) => {
  requireAuth(req);
  const table = await loadActiveFeeCatalog();
  const policy = feeEngine.resolveFeePolicy(table.policy || {});
  return {
    ok: true,
    version: table.version,
    currency: "MYR",
    table: table.table,
    policy: {
      ...policy,
      defaultTransitMonthlyCode: table.defaultTransitMonthlyCode || "",
      dueDayOptions: [7],
      notes: [
        "Registered-child billing now uses the Taska Zurah age-based model only.",
        "Registration includes the registration fee, insurance or takaful, yearly maintenance fee, and the current month monthly fee.",
        "Monthly invoices are generated on the 21st and due on the 7th of the invoice month.",
        "Overtime is billed separately using the 21st-to-20th cycle.",
        "Casual transit remains separate from registered monthly billing.",
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

function periodKeyToDate(period) {
  const match = String(period || "").trim().match(/^(\d{4})-(\d{2})$/);
  if (!match) return null;
  const dt = new Date(Number(match[1]), Number(match[2]) - 1, 1, 0, 0, 0, 0);
  return Number.isNaN(dt.getTime()) ? null : dt;
}

function shiftPeriodKey(period, monthDelta) {
  const periodDate = periodKeyToDate(period);
  if (!periodDate) return null;
  periodDate.setMonth(periodDate.getMonth() + Number(monthDelta || 0), 1);
  return monthKey(periodDate);
}

function startOfLocalDay(dt) {
  if (!(dt instanceof Date) || Number.isNaN(dt.getTime())) return null;
  return new Date(dt.getFullYear(), dt.getMonth(), dt.getDate(), 0, 0, 0, 0);
}

function childRegistrationDate(child) {
  if (!child || typeof child !== "object") return null;

  const registeredAt = child.registeredAt || child.registrationDate || child.createdAt || null;
  if (!registeredAt) return null;

  const dt = registeredAt && typeof registeredAt.toDate === "function"
    ? registeredAt.toDate()
    : new Date(registeredAt);
  return Number.isNaN(dt.getTime()) ? null : dt;
}

function periodLabel(period) {
  const periodDate = periodKeyToDate(period);
  if (!periodDate) return String(period || "").trim();
  const monthNames = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
  ];
  return `${monthNames[periodDate.getMonth()]} ${periodDate.getFullYear()}`;
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
    `Next-month invoices are generated on the 21st and due on the ${dueDay === 5 ? 5 : 7}th of the invoice month.`,
    "Overtime is billed as a separate line item using the 21st-to-20th cycle.",
    "Casual transit remains separate from registered monthly billing.",
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

async function findParentInvoiceDocByPeriod(invoiceCol, period) {
  const normalizedPeriod = String(period || "").trim();
  if (!invoiceCol || !normalizedPeriod) return null;

  const snap = await invoiceCol.get();
  for (const doc of snap.docs) {
    const data = doc.data() || {};
    if (String(data.period || "").trim() === normalizedPeriod) {
      return doc;
    }
  }

  return null;
}

function invoiceUsesTaskaZurahBilling(invoice) {
  const pricingVersion = String(invoice && invoice.pricingVersion ? invoice.pricingVersion : "").trim().toLowerCase();
  if (pricingVersion.startsWith("taska_zurah")) {
    return true;
  }

  const billingMeta = invoice && typeof invoice.billingMeta === "object" ? invoice.billingMeta : {};
  const childSummaries = Array.isArray(billingMeta.children) ? billingMeta.children : [];
  for (const summary of childSummaries) {
    const childMeta = summary && typeof summary.billingMeta === "object" ? summary.billingMeta : {};
    if (String(childMeta.feePolicyVersion || "").trim() === "TASKA_ZURAH_2026"
        && String(childMeta.activeBillingModel || "").trim() === "TASKA_ZURAH_AGE_BASED") {
      return true;
    }
  }

  const itemCodes = new Set((Array.isArray(invoice && invoice.items) ? invoice.items : [])
    .map((item) => String(item && item.code ? item.code : "").trim())
    .filter(Boolean));
  return itemCodes.has("monthly_fee")
    || itemCodes.has("registration_fee")
    || itemCodes.has("insurance_takaful")
    || itemCodes.has("yearly_maintenance_fee");
}

function invoiceNeedsTaskaZurahRefresh(invoice) {
  return !invoiceUsesTaskaZurahBilling(invoice);
}

async function createParentInvoiceForPeriod({ req, parentId, parentData, period, reqData, createdByKind, fallbackChildId }) {
  const invoiceCol = db.collection("parents").doc(parentId).collection("invoices");
  const existingDoc = await findParentInvoiceDocByPeriod(invoiceCol, period);
  if (existingDoc) {
    const doc = existingDoc;
    const existingData = doc.data() || {};
    if (String(existingData.status || "").toLowerCase() !== "paid") {
      await repairInvoiceFromEquivalentPaidCopy({ invoiceRef: doc.ref, invoiceData: existingData });
      const refreshed = await buildFamilyInvoiceFromPdfPolicy({
        parentId,
        parentData,
        period,
        reqData,
        fallbackChildId,
      });
      if (refreshed && refreshed.ok) {
        await doc.ref.set({
          payerType: refreshed.payerType,
          childId: refreshed.childIds.length === 1 ? refreshed.childIds[0] : null,
          childName: refreshed.childNameSummary || null,
          childIds: refreshed.childIds,
          childCoverageKey: childCoverageKey(period, refreshed.childIds),
          childNames: refreshed.childNames,
          items: refreshed.items,
          subTotalSen: refreshed.subTotalSen,
          totalSen: refreshed.totalSen,
          pricingVersion: refreshed.pricingVersion,
          dueDate: refreshed.dueDate,
          billingMeta: {
            ...(refreshed.billingMeta || {}),
            refreshedAt: FieldValue.serverTimestamp(),
            refreshedBy: { uid: req.auth.uid, kind: createdByKind || "billing-refresh" },
          },
          updatedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
        await upsertInvoiceLookupDocs({
          invoiceRef: doc.ref,
          invoiceData: {
            ...existingData,
            period,
            childId: refreshed.childIds.length === 1 ? refreshed.childIds[0] : null,
            childIds: refreshed.childIds,
            childCoverageKey: childCoverageKey(period, refreshed.childIds),
          },
        });

        if (refreshed.registrationFeeChildIds && refreshed.registrationFeeChildIds.length) {
          await Promise.all(refreshed.registrationFeeChildIds.map(async (childId) => {
            try {
              await db.collection("children").doc(childId).set({
                registrationFeeAppliedPeriod: period,
              }, { merge: true });
            } catch (err) {
              console.error("registration-period-mark-failed", { childId, period, error: String(err && err.message ? err.message : err) });
            }
          }));
        }
      }
    } else {
      await upsertInvoiceLookupDocs({ invoiceRef: doc.ref, invoiceData: existingData });
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
  await upsertInvoiceLookupDocs({ invoiceRef: ref, invoiceData });

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

const MALAYSIA_UTC_OFFSET_MINUTES = 8 * 60;

function malaysiaShift(date) {
  return new Date(date.getTime() + (MALAYSIA_UTC_OFFSET_MINUTES * 60 * 1000));
}

function malaysiaDateParts(date) {
  const shifted = malaysiaShift(date);
  return {
    year: shifted.getUTCFullYear(),
    month: shifted.getUTCMonth(),
    day: shifted.getUTCDate(),
    hour: shifted.getUTCHours(),
    minute: shifted.getUTCMinutes(),
  };
}

function attendanceDateKey(dt) {
  const parts = malaysiaDateParts(dt);
  return `${parts.year}-${String(parts.month + 1).padStart(2, "0")}-${String(parts.day).padStart(2, "0")}`;
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

function overtimeUsesClosedPreviousMonthCycle(baseCode) {
  const normalizedBaseCode = String(baseCode || "").trim().toLowerCase();
  return normalizedBaseCode.startsWith("monthly_fulltime_")
    || normalizedBaseCode === "transit_2h_month"
    || normalizedBaseCode === "transit_halfday_month"
    || normalizedBaseCode === "transit_schoolholiday_month";
}

async function loadAttendanceRowsForChildPeriod(childId, periodDate) {
  if (!childId || !(periodDate instanceof Date) || Number.isNaN(periodDate.getTime())) {
    return [];
  }

  try {
    const s = startOfMonth(periodDate);
    const e = endOfMonth(periodDate);
    const att = await db.collection("attendance")
      .where("childId", "==", childId)
      .where("date", ">=", s)
      .where("date", "<=", e)
      .get();
    return att.docs.map((doc) => doc.data() || {});
  } catch (err) {
    console.error("attendance-fetch-failed", { childId, period: monthKey(periodDate), error: String(err && err.message ? err.message : err) });
    return [];
  }
}

async function loadAttendanceRowsForChildRange(childId, startDate, endDate) {
  if (!childId || !(startDate instanceof Date) || Number.isNaN(startDate.getTime()) || !(endDate instanceof Date) || Number.isNaN(endDate.getTime())) {
    return [];
  }

  try {
    const att = await db.collection("attendance")
      .where("childId", "==", childId)
      .where("date", ">=", startDate)
      .where("date", "<=", endDate)
      .get();
    return att.docs.map((doc) => doc.data() || {});
  } catch (err) {
    console.error("attendance-range-fetch-failed", {
      childId,
      startDate: startDate.toISOString(),
      endDate: endDate.toISOString(),
      error: String(err && err.message ? err.message : err),
    });
    return [];
  }
}

function attendanceHasCheckOut(data) {
  return Boolean(data && (data.checkOutAt || data.check_out_time || data.checkOutTime || data.checkoutTime));
}

function manualOvertimeOverrideForChild(reqData, childId) {
  const req = reqData && typeof reqData === "object" ? reqData : {};
  const normalizedChildId = String(childId || "").trim();
  const byChild = req.manualOvertimeByChild && typeof req.manualOvertimeByChild === "object"
    ? req.manualOvertimeByChild
    : null;

  if (byChild && normalizedChildId && byChild[normalizedChildId] && typeof byChild[normalizedChildId] === "object") {
    return byChild[normalizedChildId];
  }

  return req.manualOvertime && typeof req.manualOvertime === "object"
    ? req.manualOvertime
    : null;
}

function emptyOvertimeCharge() {
  return {
    items: [],
    totalSen: 0,
    breakdown: [],
    weekdayBlocks: 0,
    saturdayBlocks: 0,
    managementReviewRecommended: false,
  };
}

async function buildClosedOvertimeChargeForInvoice({ child, childId, invoicePeriod, baseCode, payerType, table, feePolicy, reqData }) {
  const empty = emptyOvertimeCharge();
  const invoiceDate = periodKeyToDate(invoicePeriod);
  if (!invoiceDate) {
    return {
      applied: true,
      overtime: empty,
      sourcePeriod: "",
      sourcePeriodLabel: "",
      cycleStart: null,
      cycleEnd: null,
      partialRegistrationMonth: false,
      attendanceRowCount: 0,
    };
  }

  const registrationDate = childRegistrationDate(child);
  const cycle = feeEngine.determineOvertimeCycleForInvoice({
    invoiceMonth: invoiceDate,
    registrationDate,
    policy: feePolicy,
  });

  if (!cycle.applies || !cycle.cycleStart || !cycle.cycleEnd) {
    return {
      applied: true,
      overtime: empty,
      sourcePeriod: "",
      sourcePeriodLabel: "",
      cycleStart: cycle.cycleStart || null,
      cycleEnd: cycle.cycleEnd || null,
      partialRegistrationMonth: Boolean(cycle.partialRegistrationMonth),
      attendanceRowCount: 0,
    };
  }

  const manualOvertime = manualOvertimeOverrideForChild(reqData, childId);
  const sourceAttendanceRows = manualOvertime
    ? []
    : await loadAttendanceRowsForChildRange(childId, cycle.cycleStart, cycle.cycleEnd);
  const closedRows = sourceAttendanceRows.filter((row) => attendanceHasCheckOut(row));
  const rawOvertime = manualOvertime
    ? feeEngine.calculateOvertimeCharge({ manualOvertime, policy: feePolicy })
    : feeEngine.calculateOvertimeForCycle({
      attendanceRows: closedRows,
      cycleStart: cycle.cycleStart,
      cycleEnd: cycle.cycleEnd,
      policy: feePolicy,
    });
  const sourcePeriod = cycle.cycleEnd ? monthKey(cycle.cycleEnd) : "";
  const sourcePeriodLabel = cycle.cycleStart && cycle.cycleEnd
    ? `${feeEngine.malaysiaDateKey(cycle.cycleStart)} to ${feeEngine.malaysiaDateKey(cycle.cycleEnd)}`
    : "";
  const overtimeWeekdayBlocks = Number(rawOvertime.weekdayBlocks || 0);
  const overtimeSaturdayBlocks = Number(rawOvertime.saturdayBlocks || 0);

  return {
    applied: true,
    overtime: {
      items: (Array.isArray(rawOvertime.items) ? rawOvertime.items : []).map((item) => ({
        ...item,
        label: feeEngine.formatOvertimeLineDescription({
          label: String(item.label || item.description || item.code || "Overtime Charge").trim(),
          cycleStart: cycle.cycleStart,
          cycleEnd: cycle.cycleEnd,
          breakdown: rawOvertime.breakdown,
          weekdayBlocks: overtimeWeekdayBlocks,
          saturdayBlocks: overtimeSaturdayBlocks,
          policy: feePolicy,
        }),
        description: feeEngine.formatOvertimeLineDescription({
          label: String(item.description || item.label || item.code || "Overtime Charge").trim(),
          cycleStart: cycle.cycleStart,
          cycleEnd: cycle.cycleEnd,
          breakdown: rawOvertime.breakdown,
          weekdayBlocks: overtimeWeekdayBlocks,
          saturdayBlocks: overtimeSaturdayBlocks,
          policy: feePolicy,
        }),
        notes: dedupePolicyNotes([
          ...(Array.isArray(item.notes) ? item.notes : []),
          sourcePeriod ? `Closed overtime cycle ${sourcePeriod}` : "",
          cycle.partialRegistrationMonth && cycle.cycleStart ? `Cycle started on registration date ${feeEngine.malaysiaDateKey(cycle.cycleStart)}` : "",
        ].filter(Boolean)),
        sourcePeriod,
        sourcePeriodLabel,
        cycleStartDate: cycle.cycleStart ? feeEngine.malaysiaDateKey(cycle.cycleStart) : "",
        cycleEndDate: cycle.cycleEnd ? feeEngine.malaysiaDateKey(cycle.cycleEnd) : "",
        cycleType: "21-to-20-overtime-cycle",
      })),
      totalSen: moneySenToMYR(rawOvertime.totalSen),
      breakdown: Array.isArray(rawOvertime.breakdown) ? rawOvertime.breakdown : [],
      weekdayBlocks: overtimeWeekdayBlocks,
      saturdayBlocks: overtimeSaturdayBlocks,
      managementReviewRecommended: Boolean(rawOvertime.managementReviewRecommended),
    },
    sourcePeriod,
    sourcePeriodLabel,
    cycleStart: cycle.cycleStart,
    cycleEnd: cycle.cycleEnd,
    partialRegistrationMonth: Boolean(cycle.partialRegistrationMonth),
    attendanceRowCount: closedRows.length,
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

async function buildInvoiceItemsFromPdfPolicy({ parentId, childId, period, reqData, payerType }) {
  const table = await loadActiveFeeCatalog();
  const feePolicy = feeEngine.resolveFeePolicy(table.policy || {});
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
  const registrationDate = childRegistrationDate(child);
  const dob = child ? parseIsoDateOnly(child.birthDate) : null;
  const months = dob ? ageInMonths(periodDate, dob) : null;
  const ageProfile = resolveAgeProfile(months);
  const effectivePayerType = (child && typeof child.staffChild === "boolean")
    ? (child.staffChild ? "staff" : "nonstaff")
    : payerType;
  const periodKey = period || monthKey(now);
  const isRegistrationMonth = registrationChargeRequired(child, periodKey);
  const closedOvertimeCharge = await buildClosedOvertimeChargeForInvoice({
    child,
    childId,
    invoicePeriod: periodKey,
    baseCode: "monthly_fee",
    payerType: effectivePayerType,
    table,
    feePolicy,
    reqData,
  });
  const calculation = feeEngine.generateInvoiceLineItems({
    periodKey,
    periodDate,
    payerType: effectivePayerType,
    table,
    policy: feePolicy,
    careMode: "REGISTERED_CHILD",
    ageMonths: months,
    isRegistrationMonth,
    registrationDate,
    yearlyFeeCoveredYear: child && Number.isFinite(Number(child.yearlyFeeCoveredYear))
      ? Number(child.yearlyFeeCoveredYear)
      : null,
    overtimeChargeOverride: closedOvertimeCharge.applied ? closedOvertimeCharge.overtime : null,
    manualOvertime: closedOvertimeCharge.applied ? null : manualOvertimeOverrideForChild(reqData, childId),
  });

  const monthlyFeeItem = (calculation.items || []).find((item) => String(item && item.code ? item.code : "") === "monthly_fee");
  const overtimeSummary = {
    weekdayHalfHourBlocks: Number(calculation.overtime && calculation.overtime.weekdayBlocks ? calculation.overtime.weekdayBlocks : 0),
    saturdayHalfHourBlocks: Number(calculation.overtime && calculation.overtime.saturdayBlocks ? calculation.overtime.saturdayBlocks : 0),
    managementReviewRecommended: Boolean(calculation.overtime && calculation.overtime.managementReviewRecommended),
    totalSen: moneySenToMYR(calculation.overtime && calculation.overtime.totalSen),
    billedInPeriod: periodKey,
    sourcePeriod: closedOvertimeCharge.applied ? String(closedOvertimeCharge.sourcePeriod || "") : periodKey,
    sourcePeriodLabel: closedOvertimeCharge.applied ? String(closedOvertimeCharge.sourcePeriodLabel || "") : periodLabel(periodKey),
    cycleStartDate: closedOvertimeCharge.cycleStart ? attendanceDateKey(closedOvertimeCharge.cycleStart) : "",
    cycleEndDate: closedOvertimeCharge.cycleEnd ? attendanceDateKey(closedOvertimeCharge.cycleEnd) : "",
    partialRegistrationMonth: Boolean(closedOvertimeCharge.partialRegistrationMonth),
    attendanceRowCount: Number(closedOvertimeCharge.attendanceRowCount || 0),
    cycleMode: closedOvertimeCharge.applied ? "21-to-20-closed" : "same-period",
    breakdown: calculation.overtime && Array.isArray(calculation.overtime.breakdown)
      ? calculation.overtime.breakdown
      : [],
  };

  const subTotalSen = moneySenToMYR(calculation.subTotalSen);
  const totalSen = moneySenToMYR(calculation.totalSen);
  const dueDay = Number(feePolicy.invoiceSchedule && feePolicy.invoiceSchedule.dueDay ? feePolicy.invoiceSchedule.dueDay : 7);
  const dueDate = new Date(periodDate.getFullYear(), periodDate.getMonth(), dueDay, 23, 59, 59);
  const policyNotes = dedupePolicyNotes([
    isRegistrationMonth
      ? "Registration billing includes the registration fee, insurance or takaful, yearly maintenance fee, and the current month monthly fee."
      : null,
    closedOvertimeCharge.applied && overtimeSummary.totalSen > 0 && closedOvertimeCharge.sourcePeriodLabel
      ? `Overtime from ${closedOvertimeCharge.sourcePeriodLabel} is billed separately in this invoice.`
      : null,
    closedOvertimeCharge.applied && overtimeSummary.totalSen > 0 && closedOvertimeCharge.partialRegistrationMonth && closedOvertimeCharge.cycleStart
      ? `The first overtime cycle started on ${attendanceDateKey(closedOvertimeCharge.cycleStart)} based on the registration date.`
      : null,
    ...(Array.isArray(calculation.policyNotes) ? calculation.policyNotes : []),
  ]);

  if (ageProfile.ageOutOfPolicy) {
    policyNotes.unshift("Child age is outside the supported Taska Zurah range. The invoice remains flagged for manual review.");
  }

  return {
    child,
    childName,
    table,
    payerType: effectivePayerType,
    items: calculation.items,
    subTotalSen,
    totalSen,
    dueDate,
    dueDay,
    meta: {
      careType: "REGISTERED_CHILD",
      ageBand: ageProfile.ageBand,
      months,
      registrationMonth: isRegistrationMonth,
      policyNotes,
      managementReviewRecommended: Boolean(calculation.managementReviewRecommended || ageProfile.ageOutOfPolicy),
      overtime: overtimeSummary,
      resolvedBaseCode: "monthly_fee",
      ageOutOfPolicy: Boolean(ageProfile.ageOutOfPolicy),
      agePolicyReason: ageProfile.agePolicyReason,
      resolvedAgeBand: ageProfile.ageBand,
      feePolicyVersion: String(calculation.feePolicyVersion || feePolicy.policyVersion || "TASKA_ZURAH_2026"),
      activeBillingModel: String(calculation.activeBillingModel || feePolicy.activeBillingModel || "TASKA_ZURAH_AGE_BASED"),
      yearlyFeeCoveredYear: Number.isFinite(Number(calculation.yearlyFeeCoveredYear)) ? Number(calculation.yearlyFeeCoveredYear) : null,
      monthlyFeeSen: monthlyFeeItem ? moneySenToMYR(monthlyFeeItem.amountSen) : 0,
      registrationDate: registrationDate ? registrationDate.toISOString() : "",
      invoiceDueDay: dueDay,
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
    createdByKind: "parent-app",
    fallbackChildId: childId,
  });
});

exports.billingCreateInvoiceForCurrentMonth = exports.billingCreateDemoInvoiceForCurrentMonth;

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

  const { parentData } = await assertParentOwnerByPhone({ parentId, authToken: req.auth.token });

  const invoiceRef = db.collection("parents").doc(parentId).collection("invoices").doc(invoiceId);
  const invoiceSnap = await invoiceRef.get();
  if (!invoiceSnap.exists) return { ok: false, reason: "invoice-not-found" };

  let inv = invoiceSnap.data() || {};
  const repaired = await repairInvoiceFromEquivalentPaidCopy({ invoiceRef, invoiceData: inv });
  inv = repaired.invoiceData || inv;
  let refreshedLegacyDetails = false;

  if (String(inv.status || "unpaid").toLowerCase() !== "paid"
      && String(inv.status || "unpaid").toLowerCase() !== "void"
      && String(inv.period || "").trim()
      && invoiceNeedsTaskaZurahRefresh(inv)) {
    await createParentInvoiceForPeriod({
      req,
      parentId,
      parentData,
      period: String(inv.period || "").trim(),
      reqData: {},
      createdByKind: "billing-repair",
      fallbackChildId: invoiceChildIds(inv)[0] || "",
    });
    const refreshedSnap = await invoiceRef.get();
    if (refreshedSnap.exists) {
      inv = refreshedSnap.data() || inv;
      refreshedLegacyDetails = true;
    }
  }

  const status = String(inv.status || "unpaid").toLowerCase();

  return {
    ok: true,
    repaired: repaired.repaired === true,
    refreshedLegacyDetails,
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

  await upsertInvoiceLookupDocs({
    invoiceRef: event.data.after.ref,
    invoiceData: after,
  });

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
