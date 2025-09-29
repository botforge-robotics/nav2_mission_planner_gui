const { onCall } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const config = require("./config");
const {
  createSuccessResponse,
  createErrorResponse,
  validateRequiredFields,
  addDays,
  timestampToISO,
  createSafeDocumentId
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

    // Use safe document ID for device operations
    const accountsCol = db.collection(config.collections.accounts);
    const devicesCol = db.collection(config.collections.devices);
    const safeDeviceId = createSafeDocumentId(deviceId);

    const now = new Date();
    const trialEndTime = addDays(now, config.trial.days);

    // Ensure device document exists before proceeding
    console.log(`🔍 Checking if device document exists: ${deviceId}`);
    const deviceDoc = await devicesCol.doc(safeDeviceId).get();

    if (!deviceDoc.exists) {
      console.log(`📝 Creating device document for: ${deviceId}`);
      // Create basic device document if it doesn't exist
      await devicesCol.doc(safeDeviceId).set({
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
      const deviceRef = devicesCol.doc(safeDeviceId);
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


/**
 * Get migration status - check if user had previous trial data
 * This helps determine if user should see the trial reset popup
 * Only shows popup for users whose trials expired before the migration date
 */
exports.getMigrationStatus = onCall({ enforceAppCheck: config.enableAppCheck }, async (request) => {
  try {
    const data = request.data || {};
    const validationError = validateRequiredFields(data, ["accountId"]);
    if (validationError) return validationError;

    const { accountId } = data;
    console.log(`🔍 Checking migration status for account: ${accountId}`);

    const accountRef = db.collection(config.collections.accounts).doc(accountId);
    const accountSnap = await accountRef.get();

    if (!accountSnap.exists) {
      // New user - no migration needed
      return createSuccessResponse({
        hadPreviousTrial: false,
        needsMigrationPopup: false,
        migrationPopupShown: false
      });
    }

    const account = accountSnap.data();

    // Hardcoded migration date: September 28th, 2025 (start of day UTC)
    const migrationDate = new Date("2025-09-28T00:00:00.000Z");

    // Check if user had any trial data before
    const hadPreviousTrial = account.trialStartTime !== null ||
      account.trialEndTime !== null ||
      account.licenseType === "trial";

    // Check if migration popup was already shown (cloud-based)
    const migrationPopupShown = account.migrationPopupShown || false;

    // Determine if user needs migration popup
    let needsMigrationPopup = false;

    if (hadPreviousTrial && !migrationPopupShown) {
      // Check if user's trial expired before migration date
      if (account.trialEndTime) {
        const trialEndTime = account.trialEndTime.toDate ?
          account.trialEndTime.toDate() :
          new Date(account.trialEndTime);

        // Only show popup if trial expired before migration date (strictly before)
        if (trialEndTime < migrationDate) {
          needsMigrationPopup = true;
        }
      } else if (account.licenseType === "trial") {
        // If no trialEndTime but licenseType is trial, check account creation date
        const accountCreatedAt = account.createdAt?.toDate() ||
          account.updatedAt?.toDate() ||
          new Date();

        // Only show popup if account was created before migration date
        if (accountCreatedAt < migrationDate) {
          needsMigrationPopup = true;
        }
      }
    }

    // Don't show popup for purchased users
    if (account.licenseType === "individual" || account.licenseType === "enterprise") {
      needsMigrationPopup = false;
    }

    console.log(`📊 Migration status for ${accountId}: ` +
      `hadPreviousTrial=${hadPreviousTrial}, ` +
      `needsPopup=${needsMigrationPopup}, ` +
      `popupShown=${migrationPopupShown}`);

    return createSuccessResponse({
      hadPreviousTrial: hadPreviousTrial,
      needsMigrationPopup: needsMigrationPopup,
      migrationPopupShown: migrationPopupShown,
      migrationDate: migrationDate.toISOString()
    });

  } catch (error) {
    console.error("❌ Error checking migration status:", error);
    return createErrorResponse(500, "Internal server error");
  }
});

/**
 * Mark migration popup as shown for a user AND reset their trial data
 * This prevents the popup from showing again and gives them a fresh start
 */
exports.markMigrationPopupShown = onCall({ enforceAppCheck: config.enableAppCheck }, async (request) => {
  try {
    const data = request.data || {};
    const validationError = validateRequiredFields(data, ["accountId"]);
    if (validationError) return validationError;

    const { accountId } = data;
    console.log(`📝 Marking migration popup as shown and resetting trial for account: ${accountId}`);

    const accountRef = db.collection(config.collections.accounts).doc(accountId);
    const now = new Date();

    // Check if account document exists, create if it doesn't
    const accountSnap = await accountRef.get();
    if (!accountSnap.exists) {
      console.log(`📝 Creating account document for migration popup: ${accountId}`);
      await accountRef.set({
        accountId: accountId,
        migrationPopupShown: true,
        migrationPopupShownAt: now,
        createdAt: now,
        updatedAt: now
      });
    } else {
      const accountData = accountSnap.data();
      console.log(`🔄 Resetting trial data for account: ${accountId}, current license type: ${accountData.licenseType}`);

      // Reset trial data AND mark popup as shown
      const updateData = {
        // Mark popup as shown
        migrationPopupShown: true,
        migrationPopupShownAt: now,

        // Reset trial data to give user fresh start
        trialStartTime: null,
        trialEndTime: null,
        offlineAllowedUntil: null,

        // Update timestamps
        lastVerified: now,
        updatedAt: now
      };

      // If user has a completed payment, set license type to match
      // Otherwise, set licenseType to null for fresh start
      if (accountData.lastPaymentId && accountData.lastPaymentId !== "") {
        console.log("🔄 User has completed payment, setting license type to individual");
        updateData.licenseType = "individual";
      } else {
        console.log("🔄 No completed payment, setting license type to null for fresh start");
        updateData.licenseType = null;
      }

      await accountRef.update(updateData);
    }

    console.log(`✅ Migration popup marked as shown and trial reset for account: ${accountId}`);

    return createSuccessResponse({
      message: "Migration popup marked as shown and trial reset",
      timestamp: timestampToISO(now)
    });

  } catch (error) {
    console.error("❌ Error marking migration popup:", error);
    return createErrorResponse(500, "Internal server error");
  }
});



