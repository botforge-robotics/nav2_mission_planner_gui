const admin = require("firebase-admin");

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
  admin.initializeApp();
}

/**
 * Utility functions for standardized response formatting
 */

/**
 * Create success response
 * @param {any} data - Response data
 * @param {string} message - Success message
 * @returns {Object} Formatted success response
 */
function createSuccessResponse(data, message = null) {
  return {
    success: true,
    data: data,
    message: message,
    timestamp: new Date().toISOString()
  };
}

/**
 * Create error response
 * @param {number} code - HTTP status code
 * @param {string} message - Error message
 * @param {string} details - Additional error details
 * @returns {Object} Formatted error response
 */
function createErrorResponse(code, message, details = null) {
  return {
    success: false,
    error: {
      code: code,
      message: message,
      details: details,
      timestamp: new Date().toISOString()
    }
  };
}

/**
 * Validate required fields in request data
 * @param {Object} data - Request data
 * @param {Array} requiredFields - Array of required field names
 * @returns {Object|null} Validation result or null if valid
 */
function validateRequiredFields(data, requiredFields) {
  for (const field of requiredFields) {
    if (!data[field] || data[field].toString().trim() === "") {
      return createErrorResponse(400, `Missing required field: ${field}`);
    }
  }
  return null;
}

/**
 * Validate device ID format (Widevine ID)
 * @param {string} deviceId - Device ID to validate
 * @returns {boolean} True if valid, false otherwise
 */
function validateDeviceId(deviceId) {
  // Widevine ID is typically a base64 string with specific length
  return deviceId &&
    typeof deviceId === "string" &&
    deviceId.length >= 16 &&
    deviceId.length <= 100;
}

/**
 * Validate email format
 * @param {string} email - Email to validate
 * @returns {boolean} True if valid, false otherwise
 */
function validateEmail(email) {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(email);
}

/**
 * Sanitize input data
 * @param {Object} data - Data to sanitize
 * @returns {Object} Sanitized data
 */
function sanitizeData(data) {
  const sanitized = {};
  for (const [key, value] of Object.entries(data)) {
    if (typeof value === "string") {
      sanitized[key] = value.trim();
    } else {
      sanitized[key] = value;
    }
  }
  return sanitized;
}

/**
 * Create timestamp for Firestore
 * @returns {Object} Firestore timestamp
 */
function createTimestamp() {
  // Use regular Date instead of admin.firestore.Timestamp
  return new Date();
}

/**
 * Convert Firestore timestamp to ISO string
 * @param {Object} timestamp - Firestore timestamp
 * @returns {string} ISO string
 */
function timestampToISO(timestamp) {
  if (!timestamp) return null;
  // Handle both Date objects and Firestore timestamps
  if (timestamp.toDate) {
    return timestamp.toDate().toISOString();
  }
  return timestamp.toISOString();
}

/**
 * Convert ISO string to Firestore timestamp
 * @param {string} isoString - ISO string
 * @returns {Object} Firestore timestamp
 */
function isoToTimestamp(isoString) {
  if (!isoString) return null;
  return new Date(isoString);
}

/**
 * Safely encode device ID for use as Firestore document ID
 * Firestore document IDs cannot contain certain characters like '/', '+', etc.
 * @param {string} deviceId - Original device ID
 * @returns {string} Encoded device ID safe for Firestore
 */
function encodeDeviceId(deviceId) {
  if (!deviceId) return deviceId;

  // Replace problematic characters for Firestore document IDs
  return deviceId
    .replace(/\+/g, "-")  // Replace + with -
    .replace(/\//g, "_")  // Replace / with _
    .replace(/=/g, "")    // Remove = padding
    .replace(/\./g, "dot") // Replace . with 'dot'
    .replace(/#/g, "hash") // Replace # with 'hash'
    .replace(/\$/g, "dollar") // Replace $ with 'dollar'
    .replace(/\[/g, "lbracket") // Replace [ with 'lbracket'
    .replace(/\]/g, "rbracket") // Replace ] with 'rbracket'
    .replace(/\//g, "slash"); // Replace / with 'slash'
}

/**
 * Decode device ID from Firestore document ID format back to original
 * @param {string} encodedDeviceId - Encoded device ID from Firestore
 * @returns {string} Original device ID
 */
function decodeDeviceId(encodedDeviceId) {
  if (!encodedDeviceId) return encodedDeviceId;

  // Reverse the encoding process
  let decoded = encodedDeviceId
    .replace(/-/g, "+")  // Replace - with +
    .replace(/_/g, "/")  // Replace _ with /
    .replace(/dot/g, ".") // Replace 'dot' with .
    .replace(/hash/g, "#") // Replace 'hash' with #
    .replace(/dollar/g, "$") // Replace 'dollar' with $
    .replace(/lbracket/g, "[") // Replace 'lbracket' with [
    .replace(/rbracket/g, "]") // Replace 'rbracket' with ]
    .replace(/slash/g, "/"); // Replace 'slash' with /

  // Add back base64 padding if needed
  const paddingLength = 4 - (decoded.length % 4);
  if (paddingLength !== 4) {
    decoded += "=".repeat(paddingLength);
  }

  return decoded;
}

module.exports = {
  createSuccessResponse,
  createErrorResponse,
  validateRequiredFields,
  validateDeviceId,
  validateEmail,
  sanitizeData,
  createTimestamp,
  timestampToISO,
  isoToTimestamp,
  encodeDeviceId,
  decodeDeviceId
};
