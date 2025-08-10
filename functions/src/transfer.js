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

function addDays(date, days) {
  return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
}

exports.transferLicense = onCall({ enforceAppCheck: config.enableAppCheck }, async (request) => {
  try {
    const data = request.data || {};
    const authErr = await ensureAuthenticated(request);
    if (authErr) return authErr;
    const validationError = validateRequiredFields(data, ["accountId", "newDeviceId"]);
    if (validationError) return validationError;
    const { accountId, newDeviceId } = data;
    const mismatch = ensureAccountMatches(request, accountId);
    if (mismatch) return mismatch;

    const accountsCol = db.collection(config.collections.accounts);
    const devicesCol = db.collection(config.collections.devices);

    const now = new Date();

    await db.runTransaction(async (tx) => {
      const accountRef = accountsCol.doc(accountId);
      const accSnap = await tx.get(accountRef);
      if (!accSnap.exists) throw createErrorResponse(404, "Account not found");
      const acc = accSnap.data();
      if (!acc.licenseType) throw createErrorResponse(404, "No license to transfer");

      // Rate limit: allow max 1 per 30 days
      const history = Array.isArray(acc.transferHistory)
        ? acc.transferHistory
        : [];
      const since = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
      const recent = history.filter(h => new Date(h.transferDate) > since);
      if (recent.length >= (config.transferPolicy.maxPer30Days || 1)) {
        throw createErrorResponse(403, "Transfer rate limit exceeded");
      }

      const prevDeviceId = acc.linkedDeviceId || null;

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
        const prevRef = devicesCol.doc(encodeDeviceId(prevDeviceId));
        tx.set(prevRef, { licenseRevoked: true, updatedAt: now }, { merge: true });
      }

      const newRef = devicesCol.doc(encodeDeviceId(newDeviceId));
      tx.set(
        newRef,
        {
          deviceId: newDeviceId,
          accountId,
          lastLinked: now,
          licenseRevoked: false,
          updatedAt: now,
        },
        { merge: true },
      );
    });

    return createSuccessResponse(
      {
        status: "license_active",
        linkedDeviceId: newDeviceId,
        offlineAllowedUntil: addDays(new Date(), 1).toISOString(),
      },
      "Transfer complete",
    );
  } catch (error) {
    if (error?.error?.code) return error;
    console.error("transferLicense error:", error);
    return createErrorResponse(500, "Internal server error");
  }
});


