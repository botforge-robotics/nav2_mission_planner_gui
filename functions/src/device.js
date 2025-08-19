const { onCall } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const config = require("./config");
const {
  createSuccessResponse,
  createErrorResponse,
  validateRequiredFields,
  validateDeviceId,
  sanitizeData,
  createTimestamp,
  timestampToISO
} = require("./utils/response");


const db = admin.firestore();
const COLLECTION_NAME = "devices";

/**
 * Register a new device
 * This now uses Google account ID instead of Firebase UID
 */
exports.registerDevice = onCall({
  enforceAppCheck: config.enableAppCheck
}, async (request) => {
  try {
    const data = request.data;


    // Validate required fields
    console.log(data);
    const requiredFields = [
      "deviceId", "appVersion", "platform", "installationTime",
      "deviceModel", "androidVersion", "appBuildNumber", "accountId"
    ];

    const validationError = validateRequiredFields(data, requiredFields);
    if (validationError) {
      return validationError;
    }

    // Validate device ID format
    if (!validateDeviceId(data.deviceId)) {
      return createErrorResponse(400, "Invalid device ID format");
    }

    // Sanitize input data
    const sanitizedData = sanitizeData(data);
    const deviceId = sanitizedData.deviceId;
    const accountId = sanitizedData.accountId;


    // Check if device already exists
    const deviceDoc = await db.collection(COLLECTION_NAME).doc(deviceId).get();

    if (deviceDoc.exists) {
      // Device exists - return existing data
      const deviceData = deviceDoc.data();
      return createSuccessResponse({
        deviceId: deviceData.deviceId, // Return original device ID
        trialStartTime: timestampToISO(deviceData.trialStartTime),
        trialEndTime: timestampToISO(deviceData.trialEndTime),
        trialDuration: deviceData.trialDuration,
        registrationTime: timestampToISO(deviceData.registrationTime)
      }, "Device already registered");
    }

    // Create new device document
    const now = createTimestamp();
    const deviceData = {
      deviceId: deviceId,
      accountId: accountId,
      appVersion: sanitizedData.appVersion,
      platform: sanitizedData.platform,
      installationTime: sanitizedData.installationTime,
      deviceModel: sanitizedData.deviceModel,
      androidVersion: sanitizedData.androidVersion,
      appBuildNumber: sanitizedData.appBuildNumber,
      registrationTime: now,
      createdAt: now,
      updatedAt: now,
    };

    await db.collection(COLLECTION_NAME).doc(deviceId).set(deviceData);

    return createSuccessResponse(
      deviceData,
      "Device registered successfully"
    );
  } catch (error) {
    console.error("registerDevice error:", error);
    return createErrorResponse(500, "Internal server error");
  }
});
