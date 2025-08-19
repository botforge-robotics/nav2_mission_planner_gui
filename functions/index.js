const { onCall } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const config = require("./src/config");

admin.initializeApp();

// Import function modules
const deviceFunctions = require("./src/device");
const licenseFunctions = require("./src/license");
const purchaseFunctions = require("./src/purchase");
const enterpriseFunctions = require("./src/enterprise");
const transferFunctions = require("./src/transfer");
// REMOVED: const feedbackFunctions = require("./src/feedback"); // Unused import
const integrityFunctions = require("./src/integrity");

// Device management
exports.registerDevice = deviceFunctions.registerDevice;

// Licensing flows
exports.getLicenseStatus = licenseFunctions.getLicenseStatus;
exports.startTrial = licenseFunctions.startTrial;


exports.checkPaymentStatus = purchaseFunctions.checkPaymentStatus;

exports.storePurchaseDetails = purchaseFunctions.storePurchaseDetails;

// Google Play RTDN handler (Pub/Sub trigger)
exports.handlePlayRtdn = purchaseFunctions.handlePlayRtdn;


// Transfer and enterprise
exports.transferLicense = transferFunctions.transferLicense;
exports.getEnterpriseBranding = enterpriseFunctions.getEnterpriseBranding;

// Play Integrity
exports.verifyIntegrityToken = integrityFunctions.verifyIntegrityToken;

// Feedback (from purchaseFunctions, not feedbackFunctions)
exports.submitFeedback = purchaseFunctions.submitFeedback;

// Health check
exports.healthCheck = onCall({ enforceAppCheck: config.enableAppCheck }, (request) => {
  const data = request.data || {};
  return {
    success: true,
    message: "Nav2 Mission Planner Cloud Functions are running",
    timestamp: new Date().toISOString(),
    version: "2.1.0", // Updated version for new payment verification system
    receivedData: data,
  };
});