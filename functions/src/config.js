// Centralized configuration for Cloud Functions

const config = {
  enableAppCheck: false, // temporarily disabled to unblock local/release sideload testing
  collections: {
    accounts: "accounts",
    devices: "devices",
    purchases: "purchases",
    enterprises: "enterprises",
    plans: "plans",
  },
  // Map Play product IDs to license metadata
  productMap: {
    // Test product IDs (non-consumable lifetime)
    test13: { licenseType: "individual", consumable: false },
    test23: { licenseType: "enterprise", enterpriseId: null, consumable: false },
    // Original product IDs
    n2mp_individual_lifetime: { licenseType: "individual" },
    n2mp_enterprise_lifetime: { licenseType: "enterprise", enterpriseId: null },
  },
  packageName: "com.botforge.nav2missionplanner",
  // Trial configuration
  trial: {
    days: 7, // 7-day trial period
  },
  // Transfer policy configuration
  transferPolicy: {
    maxPer30Days: 999, // No practical limit - users can transfer immediately
  },
};

module.exports = config;


