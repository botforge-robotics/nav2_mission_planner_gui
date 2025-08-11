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

// This function directly updates the license without Google Play verification
exports.updateLicense = onCall({ enforceAppCheck: config.enableAppCheck }, async (request) => {
  try {
    console.log("🚀 updateLicense called with data:", JSON.stringify(request.data, null, 2));
    const data = request.data || {};
    const authErr = await ensureAuthenticated(request);
    if (authErr) {
      console.log("❌ Authentication failed:", authErr);
      return authErr;
    }
    const validationError = validateRequiredFields(
      data,
      ["accountId", "deviceId", "purchaseToken", "productId"],
    );
    if (validationError) return validationError;

    const { accountId, deviceId, purchaseToken, productId, orderId = `ORDER-${Date.now()}`, googleAccountId } = data;

    if (googleAccountId) {
      console.log("📱 Google account ID provided:", googleAccountId);
    }
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

    const now = new Date();

    // For consumable purchases, we allow multiple purchases
    // Check if this purchase token has already been used by this account
    const existing = await purchasesCol
      .where("purchaseToken", "==", purchaseToken)
      .where("accountId", "==", accountId)
      .limit(1)
      .get();

    if (!existing.empty) {
      // If this account already used this purchase token, return success
      console.log("Purchase token already used by this account, returning success");
      return createSuccessResponse({
        status: "license_active",
        licenseType,
        enterpriseId,
        offlineAllowedUntil: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
      }, "License already active");
    }

    await db.runTransaction(async (tx) => {
      const accountRef = accountsCol.doc(accountId);
      const deviceRef = devicesCol.doc(encodedDeviceId);
      const purchaseRef = purchasesCol.doc();

      // First, do all reads
      const accountSnap = await tx.get(accountRef);
      const prevLinked = accountSnap.exists ? (accountSnap.data().linkedDeviceId || null) : null;

      // Then, do all writes
      // Write purchase audit
      tx.set(purchaseRef, {
        purchaseId: purchaseRef.id,
        accountId,
        deviceId,
        productId,
        purchaseToken,
        orderId,
        googleAccountId: googleAccountId || null, // Store Google account ID if provided
        verificationStatus: "client_verified",
        purchaseDate: now,
        createdAt: now,
        refunded: false, // Track refund status
      });

      tx.set(accountRef, {
        accountId,
        licenseType,
        enterpriseId,
        purchaseToken,
        orderId,
        productId,
        purchaseDate: now,
        linkedDeviceId: deviceId,
        lastVerified: now,
        googleAccountId: googleAccountId || null, // Store Google account ID if provided
        offlineAllowedUntil: new Date(now.getTime() + 24 * 60 * 60 * 1000),
        transferHistory: prevLinked && prevLinked !== deviceId ? admin.firestore.FieldValue.arrayUnion({
          fromDeviceId: prevLinked,
          toDeviceId: deviceId,
          transferDate: now,
        }) : [],
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

    const response = createSuccessResponse({
      status: "license_active",
      licenseType,
      enterpriseId,
      offlineAllowedUntil: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
    }, "License activated");

    console.log("✅ License update completed successfully:", response);
    return response;
  } catch (error) {
    if (error?.error?.code) return error;
    console.error("updateLicense error:", error);
    return createErrorResponse(500, "Internal server error");
  }
});

// Keeping the original function for backward compatibility
exports.verifyGooglePurchase = onCall({ enforceAppCheck: config.enableAppCheck }, async (request) => {
  try {
    console.log("🚀 verifyGooglePurchase called - redirecting to updateLicense");
    // Just call updateLicense instead
    return await exports.updateLicense(request);
  } catch (error) {
    if (error?.error?.code) return error;
    console.error("verifyGooglePurchase error:", error);
    return createErrorResponse(500, "Internal server error");
  }
});