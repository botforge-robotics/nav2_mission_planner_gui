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
const feedbackFunctions = require("./src/feedback");
const integrityFunctions = require("./src/integrity");


// Device management
exports.registerDevice = deviceFunctions.registerDevice;

// Licensing flows
exports.getLicenseStatus = licenseFunctions.getLicenseStatus;
exports.startTrial = licenseFunctions.startTrial;
exports.verifyGooglePurchase = purchaseFunctions.verifyGooglePurchase;
exports.updateLicense = purchaseFunctions.updateLicense;
exports.transferLicense = transferFunctions.transferLicense;
exports.getEnterpriseBranding = enterpriseFunctions.getEnterpriseBranding;


// Play Integrity
exports.verifyIntegrityToken = integrityFunctions.verifyIntegrityToken;

// Feedback
exports.submitFeedback = feedbackFunctions.submitFeedback;

// Pricing endpoint removed

// Health check
exports.healthCheck = onCall({ enforceAppCheck: config.enableAppCheck }, (request) => {
  const data = request.data || {};
  return {
    success: true,
    message: "Nav2 Mission Planner Cloud Functions are running",
    timestamp: new Date().toISOString(),
    version: "1.0.0",
    receivedData: data,
  };
});
