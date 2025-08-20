const config = require("../config");

// In-memory store for rate limiting (in production, consider using Redis)
const requestTimestamps = new Map();

/**
 * Rate limiter for App Check token requests
 * Prevents "Too many attempts" errors by limiting token requests per device
 */
class AppCheckRateLimiter {
  /**
       * Check if a device has exceeded the rate limit for App Check tokens
       * @param {string} deviceId - Unique device identifier
       * @returns {boolean} - True if rate limit exceeded, false otherwise
       */
  static isRateLimited(deviceId) {
    const now = Date.now();
    const oneMinuteAgo = now - (60 * 1000);

    // Clean up old entries
    if (requestTimestamps.has(deviceId)) {
      const timestamps = requestTimestamps.get(deviceId);
      const validTimestamps = timestamps.filter(timestamp => timestamp > oneMinuteAgo);
      requestTimestamps.set(deviceId, validTimestamps);

      // Check if rate limit exceeded
      if (validTimestamps.length >= config.appCheckConfig.maxTokenRequestsPerMinute) {
        return true;
      }
    }

    return false;
  }

  /**
       * Record a token request for rate limiting
       * @param {string} deviceId - Unique device identifier
       */
  static recordRequest(deviceId) {
    const now = Date.now();

    if (!requestTimestamps.has(deviceId)) {
      requestTimestamps.set(deviceId, []);
    }

    const timestamps = requestTimestamps.get(deviceId);
    timestamps.push(now);
    requestTimestamps.set(deviceId, timestamps);

    // Clean up old entries to prevent memory leaks
    if (timestamps.length > 100) {
      const validTimestamps = timestamps.filter(timestamp =>
        timestamp > (now - (5 * 60 * 1000)) // Keep last 5 minutes
      );
      requestTimestamps.set(deviceId, validTimestamps);
    }
  }

  /**
       * Get rate limit status for a device
       * @param {string} deviceId - Unique device identifier
       * @returns {Object} - Rate limit status information
       */
  static getStatus(deviceId) {
    const now = Date.now();
    const oneMinuteAgo = now - (60 * 1000);

    if (!requestTimestamps.has(deviceId)) {
      return {
        rateLimited: false,
        requestsInLastMinute: 0,
        maxRequestsPerMinute: config.appCheckConfig.maxTokenRequestsPerMinute,
        timeUntilReset: 0
      };
    }

    const timestamps = requestTimestamps.get(deviceId);
    const validTimestamps = timestamps.filter(timestamp => timestamp > oneMinuteAgo);
    const requestsInLastMinute = validTimestamps.length;
    const rateLimited = requestsInLastMinute >= config.appCheckConfig.maxTokenRequestsPerMinute;

    // Calculate time until reset
    let timeUntilReset = 0;
    if (rateLimited && validTimestamps.length > 0) {
      const oldestTimestamp = Math.min(...validTimestamps);
      timeUntilReset = Math.max(0, 60000 - (now - oldestTimestamp));
    }

    return {
      rateLimited,
      requestsInLastMinute: requestsInLastMinute,
      maxRequestsPerMinute: config.appCheckConfig.maxTokenRequestsPerMinute,
      timeUntilReset: timeUntilReset
    };
  }

  /**
       * Reset rate limiting for a device (useful for testing or manual reset)
       * @param {string} deviceId - Unique device identifier
       */
  static reset(deviceId) {
    requestTimestamps.delete(deviceId);
  }

  /**
       * Clear all rate limiting data (useful for testing)
       */
  static clearAll() {
    requestTimestamps.clear();
  }
}

module.exports = AppCheckRateLimiter;
