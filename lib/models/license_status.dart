enum LicenseStatus {
  checking, // Currently verifying
  welcome, // Welcome screen (trial or license selection)
  valid, // License is active and valid
  expired, // License has expired
  invalid, // License token is invalid
  suspended, // License is suspended
  trial, // Using trial period
  noInternet, // No internet, using cached data
  error, // Verification error
  mandatoryCheckRequired, // Requires online verification
  tamperingDetected, // Time tampering detected
}
