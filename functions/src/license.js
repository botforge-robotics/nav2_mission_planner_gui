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

    const { accountId, deviceId } = data;
    const mismatch = ensureAccountMatches(request, accountId);
    if (mismatch) return mismatch;

    const accountsCol = db.collection(config.collections.accounts);

    const accountSnap = await accountsCol.doc(accountId).get();
    if (!accountSnap.exists) {
      return createSuccessResponse({ status: "no_license" }, "No license found");
    }

    const account = accountSnap.data();
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
    const { accountId, deviceId } = data;
    const mismatch = ensureAccountMatches(request, accountId);
    if (mismatch) return mismatch;

    const encodedDeviceId = encodeDeviceId(deviceId);
    const accountsCol = db.collection(config.collections.accounts);
    const devicesCol = db.collection(config.collections.devices);

    const now = new Date();
    const trialEndTime = addDays(now, config.trial.days);

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

