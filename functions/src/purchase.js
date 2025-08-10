const { onCall } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const config = require("./config");
const { ensureAuthenticated, ensureAccountMatches } = require("./auth");
const {
  createSuccessResponse,
  createErrorResponse,
  validateRequiredFields,
  encodeDeviceId,
} = require("./utils/response");

const db = admin.firestore();

async function verifyGooglePlayPurchaseServer(purchaseToken, productId) {
  // Implement Google Play Developer API verify via Android Publisher v3
  // This is a minimal implementation using googleapis. Configure credentials via env.
  const { google } = require("googleapis");
  const packageName = config.packageName;
  const auth = await google.auth.getClient({
    scopes: ["https://www.googleapis.com/auth/androidpublisher"],
  });
  const androidpublisher = google.androidpublisher({ version: "v3", auth });

  // Managed products (one-time) use purchases.products.get
  const res = await androidpublisher.purchases.products.get({
    packageName,
    productId,
    token: purchaseToken,
  });

  const data = res.data || {};
  // purchaseState: 0 purchased, 1 canceled, 2 pending
  const state = data.purchaseState;
  const orderId = data.orderId || data.orderId?.[0] || `ORDER-${Date.now()}`;
  const verified = state === 0;
  return { verified, orderId, purchaseState: state };
}

exports.verifyGooglePurchase = onCall({ enforceAppCheck: config.enableAppCheck }, async (request) => {
  try {
    const data = request.data || {};
    const authErr = await ensureAuthenticated(request);
    if (authErr) return authErr;
    const validationError = validateRequiredFields(
      data,
      ["accountId", "deviceId", "purchaseToken", "productId"],
    );
    if (validationError) return validationError;

    const { accountId, deviceId, purchaseToken, productId } = data;
    const mismatch = ensureAccountMatches(request, accountId);
    if (mismatch) return mismatch;

    const mapping = config.productMap[productId];
    if (!mapping) {
      return createErrorResponse(400, "Unknown productId");
    }
    const licenseType = mapping.licenseType;
    const enterpriseId = mapping.enterpriseId || null;

    const encodedDeviceId = encodeDeviceId(deviceId);
    const accountsCol = db.collection(config.collections.accounts);
    const devicesCol = db.collection(config.collections.devices);
    const purchasesCol = db.collection(config.collections.purchases);

    // Verify with Google Play Developer API
    const verifyResult = await verifyGooglePlayPurchaseServer(purchaseToken, productId);
    if (!verifyResult.verified) {
      return createErrorResponse(402, "Purchase not verified");
    }

    const now = new Date();

    // Enforce uniqueness of purchaseToken/orderId
    const existing = await purchasesCol.where("purchaseToken", "==", purchaseToken).limit(1).get();
    if (!existing.empty) {
      return createErrorResponse(409, "Purchase token already used");
    }

    await db.runTransaction(async (tx) => {
      const accountRef = accountsCol.doc(accountId);
      const deviceRef = devicesCol.doc(encodedDeviceId);
      const purchaseRef = purchasesCol.doc();

      // Write purchase audit
      tx.set(purchaseRef, {
        purchaseId: purchaseRef.id,
        accountId,
        deviceId,
        productId,
        purchaseToken,
        orderId: verifyResult.orderId,
        verificationStatus: "verified",
        purchaseDate: now,
        createdAt: now,
      });

      const accountSnap = await tx.get(accountRef);
      const prevLinked = accountSnap.exists ? (accountSnap.data().linkedDeviceId || null) : null;

      tx.set(accountRef, {
        accountId,
        licenseType,
        enterpriseId,
        purchaseToken,
        orderId: verifyResult.orderId,
        productId,
        purchaseDate: now,
        linkedDeviceId: deviceId,
        lastVerified: now,
        offlineAllowedUntil: new Date(now.getTime() + 24 * 60 * 60 * 1000),
        transferHistory: prevLinked && prevLinked !== deviceId ? admin.firestore.FieldValue.arrayUnion({
          fromDeviceId: prevLinked,
          toDeviceId: deviceId,
          transferDate: now,
        }) : admin.firestore.FieldValue.arrayUnion(),
        licenseRevoked: false,
      }, { merge: true });

      tx.set(deviceRef, {
        deviceId,
        accountId,
        lastLinked: now,
        licenseRevoked: false,
        updatedAt: now,
      }, { merge: true });
    });

    return createSuccessResponse({
      status: "license_active",
      licenseType,
      enterpriseId,
      offlineAllowedUntil: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
    }, "Purchase verified");
  } catch (error) {
    if (error?.error?.code) return error;
    console.error("verifyGooglePurchase error:", error);
    return createErrorResponse(500, "Internal server error");
  }
});
