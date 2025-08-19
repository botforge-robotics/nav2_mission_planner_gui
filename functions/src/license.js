const { onCall } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const config = require("./config");
const {
  createSuccessResponse,
  createErrorResponse,
  validateRequiredFields,
  addDays,
  timestampToISO,
} = require("./utils/response");


const db = admin.firestore();

/**
 * Get license status for a Firebase account (UID)
 * Uses Firebase UID as the primary user identifier; googleAccountId is optional metadata
 */
exports.getLicenseStatus = onCall({ enforceAppCheck: config.enableAppCheck }, async (request) => {
  try {
    const data = request.data || {};

    const validationError = validateRequiredFields(data, ["accountId", "deviceId"]);
    if (validationError) return validationError;

    const { accountId, deviceId } = data;

    console.log(`🔍 Getting license status for account: ${accountId}, device: ${deviceId}`);

    // Read account doc by UID
    const accountRef = db.collection(config.collections.accounts).doc(accountId);
    const accountSnap = await accountRef.get();
    if (!accountSnap.exists) {
      console.log("❌ No account document found");
      return createSuccessResponse({ status: "no_license" }, "No license found");
    }
    const account = accountSnap.data();

    console.log(`📊 Found account: ${accountId}, license type: ${account.licenseType}`);

    // Check if license is revoked
    if (account.licenseRevoked) {
      return createSuccessResponse({
        status: "license_revoked",
        reason: account.revocationReason || "License revoked",
        revocationDate: timestampToISO(account.revocationDate),
      }, "License revoked");
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

/**
 * Start trial for a Firebase account (UID)
 */
exports.startTrial = onCall({ enforceAppCheck: config.enableAppCheck }, async (request) => {
  try {
    const data = request.data || {};

    const validationError = validateRequiredFields(data, ["accountId", "deviceId"]);
    if (validationError) return validationError;

    const { accountId, deviceId } = data;

    console.log(`🚀 Starting trial for account: ${accountId}, device: ${deviceId}`);

    // Use raw device ID to match device registration
    const accountsCol = db.collection(config.collections.accounts);
    const devicesCol = db.collection(config.collections.devices);

    const now = new Date();
    const trialEndTime = addDays(now, config.trial.days);

    // Ensure device document exists before proceeding
    console.log(`🔍 Checking if device document exists: ${deviceId}`);
    const deviceDoc = await devicesCol.doc(deviceId).get();

    if (!deviceDoc.exists) {
      console.log(`📝 Creating device document for: ${deviceId}`);
      // Create basic device document if it doesn't exist
      await devicesCol.doc(deviceId).set({
        deviceId: deviceId, // Use raw device ID
        accountId: accountId,
        lastLinked: now,
        createdAt: now,
        updatedAt: now,
      });
      console.log("✅ Device document created successfully");
    } else {
      console.log(`📊 Existing device document found: ${JSON.stringify(deviceDoc.data())}`);
    }

    // Check if this account has already used a trial
    const existingDoc = await accountsCol.doc(accountId).get();
    if (existingDoc.exists) {
      const acc = existingDoc.data();
      if (acc.trialEndTime) {
        return createErrorResponse(409, "Trial already used");
      }
      if (acc.licenseType === "individual" || acc.licenseType === "enterprise") {
        return createErrorResponse(409, "Already purchased");
      }
    }

    console.log("🔍 Starting transaction for trial creation...");

    await db.runTransaction(async (tx) => {
      // Create/update account document with Firebase UID
      const accountRef = accountsCol.doc(accountId);
      const accountSnap = await tx.get(accountRef);

      if (accountSnap.exists) {
        const account = accountSnap.data();
        console.log(`📊 Existing account found: ${JSON.stringify(account)}`);
        // Enforce single trial using dates only
        if (account.trialEndTime) {
          throw createErrorResponse(409, "Trial already used");
        }
        if (account.licenseType === "individual" || account.licenseType === "enterprise") {
          throw createErrorResponse(409, "Already purchased");
        }
      } else {
        console.log(`📝 Creating new account document for: ${accountId}`);
      }

      // Update account with trial information
      const accountData = {
        accountId,
        linkedDeviceId: deviceId,
        licenseType: "trial",
        trialStartTime: now,
        trialEndTime: trialEndTime,
        lastVerified: now,
        offlineAllowedUntil: addDays(now, 1),
        licenseRevoked: false,
        flags: {},
        updatedAt: now,
      };

      console.log(`💾 Setting account data: ${JSON.stringify(accountData)}`);
      tx.set(accountRef, accountData, { merge: true });

      // Create/update device document
      const deviceRef = devicesCol.doc(deviceId);
      const deviceData = {
        deviceId: deviceId, // Use raw device ID
        accountId: accountId,
        lastLinked: now,
        createdAt: now,
        updatedAt: now,
      };

      console.log(`💾 Setting device data: ${JSON.stringify(deviceData)}`);
      tx.set(deviceRef, deviceData, { merge: true });

      console.log("✅ Transaction operations queued successfully");
    });

    console.log("🎉 Trial creation transaction completed successfully");

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



