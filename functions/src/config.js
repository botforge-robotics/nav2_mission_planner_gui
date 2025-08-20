// Centralized configuration for Cloud Functions

const config = {
  // App Check Configuration
  enableAppCheck: true, // Enable App Check enforcement
  appCheckConfig: {
    // Rate limiting for App Check token verification
    maxTokenRequestsPerMinute: 10,
    // Allow some flexibility for development/testing
    allowDebugTokens: process.env.NODE_ENV === "development",
    // Token refresh grace period (seconds)
    tokenRefreshGracePeriod: 300, // 5 minutes
  },

  requireAuth: true, // temporarily disabled for testing - set to true in production
  collections: {
    accounts: "accounts",
    devices: "devices",
    purchases: "purchases", // Legacy - will be replaced by payments
    payments: "payments", // New secure payment tracking
    enterprises: "enterprises",
    plans: "plans",
    audit: "audit", // New audit trail collection
  },
  // Map Play product IDs to license metadata
  productMap: {
    // Test product IDs (consumable - allows multiple purchases from same Google account)
    n2mp_individual_life: {
      licenseType: "individual",
      consumable: true,
      price: 1990,
      currency: "INR"
    },
  },
  packageName: "com.botforge.nav2missionplanner",
  // Trial configuration
  trial: {
    days: 14, // 14-day trial period
  },
  // Transfer policy configuration
  transferPolicy: {
    maxPer30Days: 999, // No practical limit - users can transfer immediately
  },
  // Google Play RTDN configuration
  rtdn: {
    topic: "projects/nav2-mission-planner/topics/RTDN",
    enabled: true,
  },
};

module.exports = config;


