const { onCall } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const config = require("./config");
const {
  createSuccessResponse,
  createErrorResponse,
  validateRequiredFields,
  addDays,
} = require("./utils/response");


const db = admin.firestore();



exports.transferLicense = onCall({ enforceAppCheck: config.enableAppCheck }, async (request) => {
  try {
    const data = request.data || {};


    const validationError = validateRequiredFields(data, ["accountId", "newDeviceId"]);
    if (validationError) return validationError;

    const { accountId, newDeviceId } = data;


    const accountsCol = db.collection(config.collections.accounts);
    const devicesCol = db.collection(config.collections.devices);

    const now = new Date();

    let isTrial = false; // Initialize outside transaction
    let prevDeviceId = null;

    await db.runTransaction(async (tx) => {
      // Read account by Firebase UID
      const accountRef = accountsCol.doc(accountId);
      const accountDoc = await tx.get(accountRef);
      if (!accountDoc.exists) {
        throw createErrorResponse(404, "Account not found");
      }
      const acc = accountDoc.data();

      if (!acc.licenseType) {
        throw createErrorResponse(404, "No license to transfer");
      }

      // No rate limiting - users can transfer immediately
      // Transfer history is still logged for audit purposes

      prevDeviceId = acc.linkedDeviceId || null;
      isTrial = acc.licenseType === "trial";

      tx.update(accountRef, {
        linkedDeviceId: newDeviceId,
        lastVerified: now,
        offlineAllowedUntil: addDays(now, 1),
        transferHistory: admin.firestore.FieldValue.arrayUnion({
          fromDeviceId: prevDeviceId,
          toDeviceId: newDeviceId,
          transferDate: now,
        }),
      });

      if (prevDeviceId) {
        const prevRef = devicesCol.doc(prevDeviceId);
        tx.set(prevRef, { licenseRevoked: true, updatedAt: now }, { merge: true });
      }

      const newRef = devicesCol.doc(newDeviceId);
      tx.set(
        newRef,
        {
          deviceId: newDeviceId,
          accountId: accountId,
          lastLinked: now,
          licenseRevoked: false,
          updatedAt: now,
        },
        { merge: true }
      );
    });

    console.log(`✅ License transferred from ${prevDeviceId} to ${newDeviceId}`);

    return createSuccessResponse({
      status: "license_transferred",
      fromDeviceId: prevDeviceId,
      toDeviceId: newDeviceId,
      licenseType: isTrial ? "trial" : "individual",
      offlineAllowedUntil: addDays(now, 1).toISOString(),
    }, "License transferred successfully");

  } catch (error) {
    if (error?.error?.code) return error; // bubbled structured error
    console.error("transferLicense error:", error);
    return createErrorResponse(500, "Internal server error");
  }
});

