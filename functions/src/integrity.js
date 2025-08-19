const { google } = require("googleapis");
const { getFirestore } = require("firebase-admin/firestore");
const { onCall } = require("firebase-functions/v2/https");
const config = require("./config");

const db = getFirestore();

exports.verifyIntegrityToken = onCall({ enforceAppCheck: config.enableAppCheck }, async (request) => {
  try {
    const data = request.data || {};
    const token = data.token;

    if (!token) {
      return {
        success: false,
        message: "Integrity token is required",
      };
    }

    // Initialize Google Play Developer API
    const auth = new google.auth.GoogleAuth({
      scopes: ["https://www.googleapis.com/auth/androidpublisher"],
    });

    const androidpublisher = google.androidpublisher({
      version: "v3",
      auth: auth,
    });

    // Verify the integrity token
    const response = await androidpublisher.integrity.decodeIntegrityToken({
      packageName: config.packageName,
      requestBody: {
        integrityToken: token,
      },
    });

    const integrityPayload = response.data.tokenPayloadExternal;

    if (!integrityPayload) {
      return {
        success: false,
        message: "Invalid integrity token",
      };
    }

    // Evaluate payload
    const isDeviceGenuine =
      integrityPayload.deviceIntegrity?.deviceRecognitionVerdict ===
      "MEETS_DEVICE_INTEGRITY";
    const isAppIntegrity =
      integrityPayload.appIntegrity?.appRecognitionVerdict === "PLAY_RECOGNIZED";
    const isAccountIntegrity =
      integrityPayload.accountIntegrity?.appLicensingVerdict === "LICENSED";

    const isIntegrityValid = isDeviceGenuine && isAppIntegrity && isAccountIntegrity;

    // Log integrity check for monitoring
    await db.collection("integrity_checks").add({
      timestamp: new Date(),
      token: token.substring(0, 20) + "...",
      deviceGenuine: isDeviceGenuine,
      appIntegrity: isAppIntegrity,
      accountIntegrity: isAccountIntegrity,
      overallValid: isIntegrityValid,
      googleAccountId: data.googleAccountId || "anonymous",
    });

    return {
      success: isIntegrityValid,
      message: isIntegrityValid ? "Integrity check passed" : "Integrity check failed",
      details: {
        deviceGenuine: isDeviceGenuine,
        appIntegrity: isAppIntegrity,
        accountIntegrity: isAccountIntegrity,
      },
    };
  } catch (error) {
    console.error("Error verifying integrity token:", error);

    return {
      success: false,
      message: "Failed to verify integrity token",
      error: error.message,
    };
  }
});
