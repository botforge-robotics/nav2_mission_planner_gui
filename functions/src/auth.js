const { createErrorResponse } = require("./utils/response");
const config = require("./config");

async function ensureAuthenticated(request) {
  if (config.requireAuth === false) {
    return null;
  }
  if (!request.auth || !request.auth.uid) {
    return createErrorResponse(401, "Unauthorized");
  }
  return null;
}

function ensureAccountMatches(request, accountId) {
  if (config.requireAuth === false) {
    return null;
  }
  if (!request.auth || !request.auth.uid || request.auth.uid !== accountId) {
    return createErrorResponse(401, "Unauthorized: accountId mismatch");
  }
  return null;
}

module.exports = {
  ensureAuthenticated,
  ensureAccountMatches,
};


