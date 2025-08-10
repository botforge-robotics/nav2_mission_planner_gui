const { onCall } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const {
  createSuccessResponse,
  createErrorResponse,
  validateRequiredFields,
  createTimestamp
} = require("./utils/response");

const db = admin.firestore();

/**
 * Submit feedback
 * POST /api/feedback/submit
 */
exports.submitFeedback = onCall({
  enforceAppCheck: false // Temporarily disabled for testing
}, async (request) => {
  try {
    const data = request.data;

    // Validate required fields
    const requiredFields = ["name", "email", "subject", "message", "deviceId"];
    const validationError = validateRequiredFields(data, requiredFields);
    if (validationError) {
      return validationError;
    }

    const feedbackData = {
      name: data.name,
      email: data.email,
      subject: data.subject,
      message: data.message,
      deviceId: data.deviceId,
      userAgent: data.userAgent || "Unknown",
      appVersion: data.appVersion || "1.0.0",
      createdAt: createTimestamp()
    };

    // Add feedback to database
    const feedbackRef = await db.collection("feedback").add(feedbackData);

    return createSuccessResponse({
      feedbackId: feedbackRef.id,
      submittedAt: feedbackData.createdAt.toISOString()
    }, "Feedback submitted successfully");

  } catch (error) {
    console.error("submitFeedback error:", error);
    return createErrorResponse(500, "Internal server error");
  }
});