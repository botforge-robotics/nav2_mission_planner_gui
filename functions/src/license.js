const { onCall } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const config = require("./config");
const { ensureAuthenticated, ensureAccountMatches } = require("./auth");
const {
  createSuccessResponse,
  createErrorResponse,
  validateRequiredFields,
  timestampToISO,
  encodeDeviceId
} = require("./utils/response");

const db = admin.firestore();

function addDays(date, days) {
  return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
}

// Pricing endpoint removed: no subscriptions; pricing handled by client/storefront

exports.getLicenseStatus = onCall({ enforceAppCheck: config.enableAppCheck }, async (request) => {
  try {
    const data = request.data || {};
    const authErr = await ensureAuthenticated(request);
    if (authErr) return authErr;

    const validationError = validateRequiredFields(data, ["accountId", "deviceId"]);
    if (validationError) return validationError;

    const { accountId, deviceId, googleAccountId } = data;
    const mismatch = ensureAccountMatches(request, accountId);
    if (mismatch) return mismatch;

    if (googleAccountId) {
      console.log("📱 Google account ID provided for license check:", googleAccountId);
    }

    const accountsCol = db.collection(config.collections.accounts);
    const purchasesCol = db.collection(config.collections.purchases);

    // First check if this account has a license
    const accountSnap = await accountsCol.doc(accountId).get();

    // If Google account ID is provided, also check if there are any purchases linked to it
    let googleAccountLicense = null;
    if (googleAccountId && (!accountSnap.exists || accountSnap.data().licenseType === "trial")) {
      console.log("🔍 Checking for purchases linked to Google account ID:", googleAccountId);

      // Look for purchases with this Google account ID
      const googlePurchasesQuery = await purchasesCol
        .where("googleAccountId", "==", googleAccountId)
        .where("refunded", "==", false)
        .limit(1)
        .get();

      if (!googlePurchasesQuery.empty) {
        const googlePurchase = googlePurchasesQuery.docs[0].data();
        console.log("👍 Found purchase for Google account ID:", googlePurchase.purchaseId);

        // Look up the account associated with this purchase
        const linkedAccountSnap = await accountsCol.doc(googlePurchase.accountId).get();
        if (linkedAccountSnap.exists) {
          googleAccountLicense = linkedAccountSnap.data();
          console.log("🔐 Found license linked to Google account ID");
        }
      }
    }

    if (!accountSnap.exists && !googleAccountLicense) {
      return createSuccessResponse({ status: "no_license" }, "No license found");
    }

    // Use the Google account license if available and better than the current account license
    const account = googleAccountLicense || accountSnap.data();

    if (account.licenseRevoked) {
      return createSuccessResponse(
        { status: "license_revoked", reason: account.revocationReason || null },
        "License revoked",
      );
    }

    const now = new Date();
    const offlineAllowedUntil = account.offlineAllowedUntil
      ? timestampToISO(account.offlineAllowedUntil)
      : null;

    if (account.licenseType === "trial") {
      const trialEndTime = account.trialEndTime?.toDate
        ? account.trialEndTime.toDate()
        : (account.trialEndTime
          ? new Date(account.trialEndTime)
          : null);
      if (trialEndTime && now < trialEndTime) {
        // Check if trial is linked to a different device
        if (account.linkedDeviceId && account.linkedDeviceId !== deviceId) {
          return createSuccessResponse(
            { status: "linked_to_other_device", linkedDeviceId: account.linkedDeviceId },
            "Trial linked to other device",
          );
        }
        const remainingMs = trialEndTime.getTime() - now.getTime();
        const remainingDays = Math.ceil(remainingMs / (1000 * 60 * 60 * 24));
        return createSuccessResponse(
          {
            status: "trial_active",
            trialEndTime: trialEndTime.toISOString(),
            remainingDays,
            offlineAllowedUntil,
          },
          "Trial active",
        );
      }
      return createSuccessResponse({ status: "trial_expired" }, "Trial expired");
    }

    if (account.licenseType === "individual" || account.licenseType === "enterprise") {
      if (account.linkedDeviceId && account.linkedDeviceId !== deviceId) {
        return createSuccessResponse(
          { status: "linked_to_other_device", linkedDeviceId: account.linkedDeviceId },
          "Linked to other device",
        );
      }
      return createSuccessResponse(
        {
          status: "license_active",
          licenseType: account.licenseType,
          enterpriseId: account.enterpriseId || null,
          offlineAllowedUntil,
        },
        "License active",
      );
    }

    return createSuccessResponse({ status: "no_license" }, "No license");
  } catch (error) {
    console.error("getLicenseStatus error:", error);
    return createErrorResponse(500, "Internal server error");
  }
});

exports.startTrial = onCall({ enforceAppCheck: config.enableAppCheck }, async (request) => {
  try {
    const data = request.data || {};
    const authErr = await ensureAuthenticated(request);
    if (authErr) return authErr;
    const validationError = validateRequiredFields(data, ["accountId", "deviceId"]);
    if (validationError) return validationError;
    const { accountId, deviceId, googleAccountId } = data;

    if (googleAccountId) {
      console.log("📱 Google account ID provided for trial start:", googleAccountId);
    }
    const mismatch = ensureAccountMatches(request, accountId);
    if (mismatch) return mismatch;

    const encodedDeviceId = encodeDeviceId(deviceId);
    const accountsCol = db.collection(config.collections.accounts);
    const devicesCol = db.collection(config.collections.devices);

    const now = new Date();
    const trialEndTime = addDays(now, config.trial.days);

    // Check if this Google account has already used a trial
    if (googleAccountId) {
      const existingTrialQuery = await accountsCol
        .where("googleAccountId", "==", googleAccountId)
        .where("licenseType", "==", "trial")
        .limit(1)
        .get();

      if (!existingTrialQuery.empty) {
        return createErrorResponse(409, "Trial already used with this Google account");
      }
    }

    await db.runTransaction(async (tx) => {
      const accountRef = accountsCol.doc(accountId);
      const accountSnap = await tx.get(accountRef);
      if (accountSnap.exists) {
        const account = accountSnap.data();
        // Enforce single trial using dates only
        if (account.trialEndTime) {
          throw createErrorResponse(409, "Trial already used");
        }
        if (account.licenseType === "individual" || account.licenseType === "enterprise") {
          throw createErrorResponse(409, "Already purchased");
        }
      }
      tx.set(accountRef, {
        accountId,
        linkedDeviceId: deviceId,
        licenseType: "trial",
        trialStartTime: now,
        trialEndTime: trialEndTime,
        lastVerified: now,
        googleAccountId: googleAccountId || null, // Store Google account ID if provided
        offlineAllowedUntil: addDays(now, 1),
        licenseRevoked: false,
        flags: {},
      }, { merge: true });

      const deviceRef = devicesCol.doc(encodedDeviceId);
      tx.set(deviceRef, {
        deviceId,
        accountId,
        lastLinked: now,
        licenseRevoked: false,
        updatedAt: now,
      }, { merge: true });
    });

    return createSuccessResponse({
      status: "trial_active",
      trialEndTime: trialEndTime.toISOString(),
      offlineAllowedUntil: addDays(new Date(), 1).toISOString(),
    }, "Trial started");
  } catch (error) {
    if (error?.error?.code) return error; // bubbled structured error
    console.error("startTrial error:", error);
    return createErrorResponse(500, "Internal server error");
  }
});

