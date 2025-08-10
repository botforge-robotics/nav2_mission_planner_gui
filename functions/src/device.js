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
  timestampToISO,
  encodeDeviceId
} = require("./utils/response");

const db = admin.firestore();
const COLLECTION_NAME = "devices";

/**
 * Register a new device
 * POST /api/device/register
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
      "deviceModel", "androidVersion", "appBuildNumber"
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
    const originalDeviceId = sanitizedData.deviceId;

    // Encode device ID for use as Firestore document ID
    const encodedDeviceId = encodeDeviceId(originalDeviceId);

    // Check if device already exists
    const deviceDoc = await db.collection(COLLECTION_NAME).doc(encodedDeviceId).get();

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
      ...sanitizedData,
      deviceId: originalDeviceId, // Store original device ID in data
      registrationTime: now,
      createdAt: now,
      updatedAt: now
    };

    await db.collection(COLLECTION_NAME).doc(encodedDeviceId).set(deviceData);

    return createSuccessResponse({
      deviceId: originalDeviceId, // Return original device ID
      registrationTime: timestampToISO(deviceData.registrationTime)
    }, "Device registered successfully");

  } catch (error) {
    console.error("registerDevice error:", error);
    return createErrorResponse(500, "Internal server error");
  }
});
