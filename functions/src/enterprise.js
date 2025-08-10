const { onCall } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const config = require("./config");
const {
  createSuccessResponse,
  createErrorResponse,
  validateRequiredFields,
  createTimestamp,
  timestampToISO
} = require("./utils/response");

const db = admin.firestore();

/**
 * Get enterprise branding data
 * GET /api/enterprise/branding?enterpriseCode=ABC123
 */
exports.getEnterpriseBranding = onCall({
  enforceAppCheck: config.enableAppCheck
}, async (request) => {
  try {
    const data = request.data || {};

    // Validate required fields
    const validationError = validateRequiredFields(data, ["enterpriseId"]);
    if (validationError) {
      return validationError;
    }

    const enterpriseId = data.enterpriseId;

    // Get enterprise document
    const enterpriseDoc = await db.collection(config.collections.enterprises).doc(enterpriseId).get();

    if (!enterpriseDoc.exists) {
      return createErrorResponse(404, "Enterprise not found");
    }

    const enterpriseData = enterpriseDoc.data();

    if (!enterpriseData.active) {
      return createErrorResponse(402, "Enterprise code inactive");
    }

    const brandingUpdatedAt = enterpriseData.brandingUpdatedAt
      ? (enterpriseData.brandingUpdatedAt.toDate
        ? enterpriseData.brandingUpdatedAt.toDate().toISOString()
        : new Date(enterpriseData.brandingUpdatedAt).toISOString())
      : null;

    return createSuccessResponse(
      {
        appTitle: enterpriseData.appTitle || null,
        supportEmail: enterpriseData.supportEmail || null,
        themeColor: enterpriseData.themeColor || null,
        website: enterpriseData.website || null,
        logoUrl: enterpriseData.logoUrl || null,
        faviconUrl: enterpriseData.faviconUrl || null,
        tagLine: enterpriseData.tagLine || null,
        footerCredits: enterpriseData.footerCredits || null,
        brandingUpdatedAt,
      },
      "Enterprise branding retrieved successfully",
    );

  } catch (error) {
    console.error("getEnterpriseBranding error:", error);
    return createErrorResponse(500, "Internal server error");
  }
});

/**
 * Create enterprise (admin only)
 * POST /api/enterprise/create
 */
exports.createEnterprise = onCall({
  enforceAppCheck: true
}, async (request) => {
  try {
    const data = request.data;

    // Check if user is authenticated and has admin role
    if (!request.auth) {
      return createErrorResponse(401, "Unauthorized");
    }

    // Validate required fields
    const requiredFields = [
      "enterpriseCode", "organizationName", "brandingData"
    ];
    const validationError = validateRequiredFields(data, requiredFields);
    if (validationError) {
      return validationError;
    }

    const enterpriseCode = data.enterpriseCode.toUpperCase();
    const { organizationName, brandingData } = data;

    // Validate enterprise code format
    const codeRegex = /^[A-Z0-9]{6}$/;
    if (!codeRegex.test(enterpriseCode)) {
      return createErrorResponse(400, "Invalid enterprise code format");
    }

    // Check if enterprise code already exists
    const existingDoc = await db.collection("enterprises").doc(enterpriseCode).get();
    if (existingDoc.exists) {
      return createErrorResponse(409, "Enterprise code already exists");
    }

    // Validate branding data structure
    const requiredBrandingFields = [
      "logoUrl", "themeColor", "companyName", "appTitle"
    ];

    for (const field of requiredBrandingFields) {
      if (!brandingData[field]) {
        return createErrorResponse(400, `Missing required branding field: ${field}`);
      }
    }

    // Create enterprise document
    const now = createTimestamp();
    const enterpriseData = {
      code: enterpriseCode,
      organizationName: organizationName,
      brandingData: {
        logoUrl: brandingData.logoUrl,
        faviconIcon: brandingData.faviconIcon || brandingData.logoUrl,
        themeColor: brandingData.themeColor,
        footerCredits: brandingData.footerCredits || `© ${new Date().getFullYear()} ${brandingData.companyName}`,
        tagLine: brandingData.tagLine || "Professional Mission Planning",
        companyName: brandingData.companyName,
        appTitle: brandingData.appTitle,
        supportEmail: brandingData.supportEmail || "support@company.com",
        website: brandingData.website || "https://company.com"
      },
      active: true,
      maxDevices: data.maxDevices || 10,
      devices: [],
      createdAt: now,
      updatedAt: now
    };

    await db.collection("enterprises").doc(enterpriseCode).set(enterpriseData);

    return createSuccessResponse({
      enterpriseCode: enterpriseCode,
      organizationName: organizationName,
      brandingData: enterpriseData.brandingData,
      maxDevices: enterpriseData.maxDevices
    }, "Enterprise created successfully");

  } catch (error) {
    console.error("createEnterprise error:", error);
    return createErrorResponse(500, "Internal server error");
  }
});

/**
 * Update enterprise (admin only)
 * PUT /api/enterprise/update
 */
exports.updateEnterprise = onCall({
  enforceAppCheck: true
}, async (request) => {
  try {
    const data = request.data;

    // Check if user is authenticated and has admin role
    if (!request.auth) {
      return createErrorResponse(401, "Unauthorized");
    }

    // Validate required fields
    const validationError = validateRequiredFields(data, ["enterpriseCode"]);
    if (validationError) {
      return validationError;
    }

    const enterpriseCode = data.enterpriseCode.toUpperCase();
    const updateData = { ...data };
    delete updateData.enterpriseCode; // Remove enterpriseCode from update data

    // Check if enterprise exists
    const enterpriseDoc = await db.collection("enterprises").doc(enterpriseCode).get();
    if (!enterpriseDoc.exists) {
      return createErrorResponse(404, "Enterprise not found");
    }

    // Validate allowed update fields
    const allowedFields = [
      "organizationName", "brandingData", "active", "maxDevices"
    ];
    const filteredData = {};

    for (const field of allowedFields) {
      if (updateData[field] !== undefined) {
        filteredData[field] = updateData[field];
      }
    }

    if (Object.keys(filteredData).length === 0) {
      return createErrorResponse(400, "No valid fields to update");
    }

    // Update enterprise
    filteredData.updatedAt = createTimestamp();
    await db.collection("enterprises").doc(enterpriseCode).update(filteredData);

    // Get updated enterprise data
    const updatedDoc = await db.collection("enterprises").doc(enterpriseCode).get();
    const updatedData = updatedDoc.data();

    return createSuccessResponse({
      enterpriseCode: enterpriseCode,
      organizationName: updatedData.organizationName,
      brandingData: updatedData.brandingData,
      active: updatedData.active,
      maxDevices: updatedData.maxDevices,
      currentDevices: (updatedData.devices || []).length,
      createdAt: timestampToISO(updatedData.createdAt),
      updatedAt: timestampToISO(updatedData.updatedAt)
    }, "Enterprise updated successfully");

  } catch (error) {
    console.error("updateEnterprise error:", error);
    return createErrorResponse(500, "Internal server error");
  }
});

/**
 * Get all enterprises (admin only)
 * GET /api/enterprises
 */
exports.getAllEnterprises = onCall({
  enforceAppCheck: true
}, async (request) => {
  try {
    // Check if user is authenticated and has admin role
    if (!request.auth) {
      return createErrorResponse(401, "Unauthorized");
    }

    // Get all enterprises
    const enterprisesSnapshot = await db.collection("enterprises").get();
    const enterprises = [];

    enterprisesSnapshot.forEach(doc => {
      const enterpriseData = doc.data();
      enterprises.push({
        enterpriseCode: enterpriseData.code,
        organizationName: enterpriseData.organizationName,
        active: enterpriseData.active,
        maxDevices: enterpriseData.maxDevices,
        currentDevices: (enterpriseData.devices || []).length,
        createdAt: timestampToISO(enterpriseData.createdAt),
        updatedAt: timestampToISO(enterpriseData.updatedAt)
      });
    });

    return createSuccessResponse({
      enterprises: enterprises,
      count: enterprises.length
    }, "Enterprises retrieved successfully");

  } catch (error) {
    console.error("getAllEnterprises error:", error);
    return createErrorResponse(500, "Internal server error");
  }
});
