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
    n2mp_individual_lifetime: { licenseType: "individual" },
    n2mp_enterprise_lifetime: { licenseType: "enterprise", enterpriseId: null },
  },
  packageName: "com.botforge.nav2missionplanner",
};

module.exports = config;


