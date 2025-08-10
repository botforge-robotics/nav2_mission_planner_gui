below is a complete developer-grade implementation spec for the app licensing system (Play Store–compliant, Firebase Auth mandatory, Google Play Billing for purchases, account↔device binding, 1-day offline cache, enterprise branding in separate collection). I’ve excluded any code snippets as requested and focused on precise requirements, data models, APIs, behaviors, validations, edge cases, test cases, and deployment notes so your engineers can implement directly.

1. Overview (what this implements)
   Mandatory login using Firebase Authentication (account = authority).

Per-account license state stored server-side (accounts/{accountId}); enterpriseId references enterprises/{enterpriseId} for branding.

Device identity = Widevine DRM Base64 string; one account → one active device at a time.

Trial (7 days) available once per account, activation must be explicit.

Purchases use Google Play Billing; verification happens server-side via Google Play Developer API.

Offline allowance after any successful server validation = 1 day. App requires online after offline allowance expires.

Secure transfer: when user logs in on a new device, they may transfer license to that device by explicit confirmation; server revokes old device.

All client-to-server calls authenticated via Firebase ID token verification in Cloud Functions.

2. Firestore data model
   2.1 accounts/{accountId}
   Authoritative license state for user account (owned by Firebase UID).

Fields (types and notes):

accountId (string) — same as document ID (Firebase UID).

linkedDeviceId (string|null) — Widevine base64 of currently active device.

licenseType (enum|null) — "null" | "trial" | "individual" | "enterprise".

trialStartTime (ISO8601|null).

trialEndTime (ISO8601|null).

trialStatus (enum) — "not_started" | "active" | "expired".

purchaseToken (string|null) — Google Play purchase token.

orderId (string|null) — Google Play orderId (for audit).

productId (string|null) — Play product id used.

purchaseDate (ISO8601|null).

enterpriseId (string|null) — references enterprises/{enterpriseId}.

lastVerified (ISO8601) — server timestamp of last successful verification.

offlineAllowedUntil (ISO8601) — server timestamp; client may operate offline until this.

transferHistory (array) — entries: { fromDeviceId, toDeviceId, transferDate, admin, note }.

licenseRevoked (boolean) — if true, account license disabled until support action.

flags (map) — for future guards (e.g., suspiciousActivity:true).

Indexes:

index by orderId and purchaseToken (unique constraint enforced via Cloud Functions logic).

2.2 devices/{deviceId}
Audit and quick lookup for device->account mapping.

Fields:

deviceId (string) — doc ID.

accountId (string|null).

lastLinked (ISO8601|null).

licenseRevoked (boolean).

notes (string|null).

2.3 enterprises/{enterpriseId}
Branding data referenced from accounts.

Fields (all optional strings; use null when not provided):

enterpriseId (doc id)

appTitle (string|null)

supportEmail (string|null)

themeColor (string|null)

website (string|null)

logoUrl (string|null)

faviconUrl (string|null)

tagLine (string|null)

footerCredits (string|null)

brandingUpdatedAt (ISO8601)

2.4 purchases/{purchaseId}
Purchase audit log: store Google response and verification result (non-sensitive trimmed copy).

Fields:

purchaseId (doc id)

accountId, deviceId, productId, purchaseToken, orderId, amount, currency, purchaseDate, verificationStatus, rawResponseSummary, createdAt.

3. Cloud Functions (API) — design, requests, responses, codes
   All functions require Firebase ID token verification. Each response uses uniform wrapper:

Success: { success: true, data: {...}, message: "...", timestamp: "ISO" }

Error: { success: false, error: { code: <int>, message: "...", details: null, timestamp: "ISO" } }

3.1 getPricing
Purpose: return dynamic pricing + trialDays.

Request:

Authenticated user (Firebase token).

Body: { accountId } — server verifies token matches accountId.

Response (200):

data: { trialDays: int, individual: { price: int, currency: "INR" }, enterprise: { price: int, currency: "INR" } }

Errors:

401 Unauthorized: invalid token or mismatch.

500 Internal Error.

3.2 getLicenseStatus
Purpose: return account's license/trial status and guidance for client.

Request body:

{ accountId, deviceId } (both required)

Behavior:

If no account doc: return no_license.

If licenseRevoked true: return license_revoked.

If licenseType == "trial" and now < trialEndTime => trial_active (return remainingDays).

If licenseType == "trial" and now >= trialEndTime => trial_expired.

If licenseType == "individual" or "enterprise" and linkedDeviceId == deviceId => license_active.

If linkedDeviceId != null and different => linked_to_other_device (include linkedDeviceId).

Always include offlineAllowedUntil if available.

Success responses (examples):

no_license → data: { status: "no_license" }

trial_active → data: { status: "trial_active", trialEndTime, remainingDays, offlineAllowedUntil }

license_active → data: { status: "license_active", licenseType, enterpriseId|null, offlineAllowedUntil }

linked_to_other_device → data: { status: "linked_to_other_device", linkedDeviceId }

license_revoked → data: { status: "license_revoked", reason: "..." }

Errors:

400 missing fields

401 unauthorized

500 server error

3.3 startTrial
Request body:

{ accountId, deviceId } (authenticated)

Server validation:

If account doc exists and trialStatus != "not_started" -> return 409 (trial already used).

If account doc exists and licenseType is individual or enterprise -> return 409 (already purchased).

Otherwise set trialStartTime=now, trialEndTime = now + trialDays, trialStatus="active", linkedDeviceId = deviceId if null, lastVerified=now, offlineAllowedUntil = now + 1 day. Write devices collection mapping.

Success:

200 with data containing the trial times, remainingDays and offlineAllowedUntil.

Errors:

403 if account blocked.

409 trial already used / already licensed.

500 server error.

3.4 verifyGooglePurchase
Purpose: verify a Play Billing purchase token, record purchase, bind license to account+device, return license.

Request body:

{ accountId, deviceId, purchaseToken, productId }

Server steps:

Verify Firebase token->accountId.

Validate inputs.

Call Google Play Developer API to verify purchaseToken for productId.

Check returned orderId/purchaseState; ensure purchaseState is purchased/consumed as appropriate.

Ensure purchaseToken or orderId not previously used (prevent reuse).

Update purchases audit doc with summary of verification.

Update accounts/{accountId}: set licenseType to individual/enterprise, purchaseToken, orderId, purchaseDate, productId, linkedDeviceId = deviceId (overwriting old linkedDeviceId), lastVerified=now, offlineAllowedUntil = now + 1 day.

Update devices/{deviceId} mapping and add transferHistory entry if overwrote previous device.

If enterprise: lookup enterprises/{enterpriseId} by mapping of productId->enterpriseId (product configuration stored on server) and set enterpriseId and branding pointer.

Response (200):

data: { status: "license_active", licenseType, enterpriseId|null, offlineAllowedUntil }

Errors:

400 missing fields

402 purchase not verified / invalid purchase

409 purchase already consumed or used

500 server error

3.5 transferLicense
Purpose: bind an existing account license to a new device (user-initiated).

Request:

{ accountId, newDeviceId } (authenticated)

Rules:

Account must have licenseType != null.

Rate-limit transfers: configurable policy (e.g., max 1 transfer per 30 days or N lifetime). Return 403 if rate-limited.

If allowed:

Add entry to transferHistory with fromDeviceId (previous linkedDeviceId), toDeviceId, timestamp.

Set devices/{oldDeviceId}.licenseRevoked = true.

Set accounts/{accountId}.linkedDeviceId = newDeviceId.

Update devices/{newDeviceId} mapping.

Set lastVerified = now, offlineAllowedUntil = now + 1 day.

Response:

200 with data { status: "license_active", linkedDeviceId: newDeviceId, offlineAllowedUntil }

Errors:

404 no license to transfer

403 transfer not allowed (rate limit)

500 server error

3.6 getEnterpriseBranding
Request:

{ enterpriseId } (optional: allow unauthenticated to display branding if enterprise license active; better to require account auth)

Response:

data with branding fields exactly: appTitle, supportEmail, themeColor, website, logoUrl, faviconUrl, tagLine, footerCredits, brandingUpdatedAt.

Errors:

404 enterprise not found

500 server error

4. Client behavior — full online/offline flows
   All local storage must be encrypted using platform keystore; store only the server-provided offlineAllowedUntil, last-known licenseType, enterpriseId, and branding snapshot. Local cache is not authoritative.

4.1 App startup (always)
Verify Firebase Auth token; if not authenticated, show login screen and block further use.

Build deviceId (Widevine base64) on device.

Load local cache (encrypted) for licenseSummary (if exists).

Evaluate:

If licenseSummary.offlineAllowedUntil >= now:

Allow offline access per cached licenseSummary.

Trigger background async task to refresh server status; if refresh fails and offlineAllowedUntil still valid, allow continued offline use.

Else:

Require immediate online getLicenseStatus call; if offline or call fails, block and prompt user to connect to internet.

4.2 First-time online after login
Call getLicenseStatus(accountId, deviceId).

Handle server responses:

no_license:

Show screen: explicit choices — Start 7-day trial OR Buy now.

Do NOT start trial automatically.

trial_active:

Store server offlineAllowedUntil, trialEndTime in encrypted cache.

Allow access; display trial days left.

trial_expired:

Show buy screen disabling protected features until purchase.

license_active:

Store offlineAllowedUntil, licenseType, enterpriseId.

If enterpriseId present: call getEnterpriseBranding(enterpriseId) and cache branding locally (overwrite local styling).

Allow access.

linked_to_other_device:

Show clear UI: “This account is linked to another device (device ending XXXX). Transfer license to this device?” with explanation that transfer will revoke previous device.

If user confirms, call transferLicense.

license_revoked:

Show support contact and block access per policy.

4.3 Activating trial
User taps Start Trial:

Call startTrial(accountId, deviceId).

On 200 success: update local cache with trialEndTime, offlineAllowedUntil.

On 409: display "Trial already used".

On 403/other: show message and direct to support.

4.4 Purchasing (Play Billing)
App queries Play Billing for configured product IDs (in app config / remote config).

User completes purchase via Google Play Billing UI.

On purchase success, app receives purchaseToken and orderId client-side.

App should immediately call verifyGooglePurchase(accountId, deviceId, purchaseToken, productId).

On success:

Update local cache with license_active and offlineAllowedUntil.

If enterprise: fetch getEnterpriseBranding(enterpriseId) and cache.

Display success UI and enabled features.

On verify failure:

Show payment failed UI; advise contacting support with orderId.

4.5 Daily/periodic checks
On app foreground or daily heartbeat:

If now > offlineAllowedUntil, force online getLicenseStatus.

If now ≤ offlineAllowedUntil, allow use but schedule async online refresh in background.

If online refresh indicates mismatch (e.g., linked_to_other_device or license_revoked), immediately reflect server state: block features or show transfer prompt.

4.6 Transfer flow on new device
User logs in on new device; getLicenseStatus returns linked_to_other_device.

App informs user rights and consequences and asks for confirmation.

If user confirms, call transferLicense(accountId, newDeviceId).

On success: update encryption cache and fetch branding if enterprise.

On failure: display reason.

5. Security & anti-tamper
   5.1 Server-side protections
   Require Firebase Auth token on every request and validate.

Google Play verification must call Google Play Developer API (service account credentials) from server only.

Enforce uniqueness of purchaseToken and orderId: Cloud Functions must check purchases collection to prevent re-use.

Rate-limit transfer operations and sensitive endpoints.

Log all sensitive operations (purchases, transfers) into audit collection with admin id, timestamps, IP, and verification result.

Use strict Firestore security rules so client cannot write license fields directly (only Cloud Functions service account can).

5.2 Client-side protections
Store cached license state in encrypted secure storage (Android Keystore / iOS Keychain).

Obfuscate app binary (proguard/R8 + recommended native protections).

Detect rooted/jailbroken devices and mark as suspicious; optionally restrict use or require extra verification.

Detect time rollback: compare system time with monotonic clock offsets or last server lastVerified to detect large negative shifts. If detected, force online verify.

Do not expose enterpriseId-to-branding endpoint unauthenticated if brand assets are private; prefer to fetch after license verification.

6. Admin & operational tools
   6.1 Admin console
   View accounts and devices.

Force revoke/unrevoke license (set licenseRevoked).

Approve manual transfers (if you choose to allow manual/manual override).

Search purchase logs by orderId/purchaseToken.

Edit enterprises branding documents.

6.2 Monitoring & alerts
Alert on failed bulk purchase verifications.

Alert on suspicious transfer frequency for a single account.

Monitor licenseRevoked rates and root/jailbroken flagged device counts.

7. Edge cases and how to handle them
   User clears app data or reinstalls: deviceId may be preserved (Widevine) — server getLicenseStatus returns license and app restores. If deviceId changed (rare), user must transfer license via transferLicense.

User changes deviceId by tampering: Widevine ID is hard to spoof; still, server verifies patterns and flags suspicious changes. Require support for manual recovery if abused.

Concurrent purchases: Cloud Function must check and prevent double-updating or race conditions using Firestore transactions.

Google Play refund: if Google notifies refund/cancellation (use Google Play real-time developer notifications or periodic verification), server must mark license revoked and set offlineAllowedUntil to now to force immediate re-check.

Time zone issues: store and compare timestamps in UTC ISO8601 only.

Network interruptions during purchase: If client couldn’t call verify endpoint after purchase, app should retry on next start; purchases should be verifiable by server independently (Google API provides purchaseToken lookup).

Enterprise branding changes: update enterprises/{enterpriseId}.brandingUpdatedAt to invalidate local cache and trigger app to re-fetch branding on next online check.

8. Firestore Security Rules (high-level)
   Deny client writes to accounts, purchases, devices, enterprises; only allow reads where appropriate (e.g., enterprise branding can be read only after license check or via Cloud Functions).

Allow clients to read enterprises branding only if their accounts/{accountId}.enterpriseId == requested enterpriseId and token validated. Prefer to serve branding via Cloud Function to centralize auth.

9. Environment & deployment configuration
   Required environment variables for Cloud Functions
   GOOGLE_APPLICATION_CREDENTIALS (service account json) for Google Play Developer API access.

FIREBASE_PROJECT_ID

PLAY_API_PACKAGE_NAME (app package name)

PLAY_API_SERVICE_ACCOUNT_EMAIL

PLAY_API_KEY or access via service account

Logging/monitoring config (stackdriver)

Secrets & keys
Keep Google Play service account keys and Firebase service keys secure and out of repo (use Cloud Functions environment or secret manager).

10. Test cases (must implement automated tests)
    Purchase verification success and failure scenarios for each productId.

Start trial success (first time) and failure (second attempt).

Transfer flow: initiate transfer and validate that old device is revoked and new device becomes linked.

Offline cache expiration behavior: allow offline for offlineAllowedUntil and block after expiration.

Refund handling: simulate Play refund notification and ensure license revoked.

Race conditions: concurrent verifyGooglePurchase calls with same purchaseToken should be idempotent and prevented.

Branding fetch: ensure enterprise branding is applied after purchase and updated when brandingUpdatedAt changes.

11. Logging & audit
    Log all license-changing operations (startTrial, verifyGooglePurchase, transferLicense) to purchases and audit collections with admin field when applicable.

Include requesterIp, userAgent, and functionName for support.

12. Rollout & migration notes
    If migrating existing users from previous license model, provide migration Cloud Function to map old license fields into new accounts schema. Lock down migration to admin-only.

13. Developer checklist (implementation steps)
    Implement Firebase Auth login flow and enforce accountId requirement in app.

Implement Widevine deviceId extraction and ensure format normalization.

Implement Firestore data model and necessary indexes.

Implement Cloud Functions:

getPricing, getLicenseStatus, startTrial, verifyGooglePurchase, transferLicense, getEnterpriseBranding.

All functions validate Firebase token and input.

Use Firestore transactions for updates.

Integrate Google Play Billing in app and supply productId mapping in remote config.

Implement encrypted local cache + offlineAllowedUntil enforcement.

Implement root/jailbreak/time-rollback detection.

Build admin console for audit and manual operations.

Add monitoring, alerts, test automation.

Deploy and test end-to-end (purchase, reinstall, transfer, refund).

14. Acceptance criteria (for QA)
    New user can sign up, choose to start trial, and get 7 days trial.

Purchase via Play Billing succeeds and server verifies; license applied to account and device.

Reinstalling app on same device restores license without additional purchase.

Logging in on a new device shows transfer prompt and after approval old device loses license.

Offline use allowed strictly up to server-provided offlineAllowedUntil (1 day) and requires online after expiration.

Refunds processed by Google result in revoked license on next verification.

# Nav2 Mission Planner — Licensing Flow Diagrams (End-to-End)

This document contains end-to-end flow diagrams (Mermaid) covering all major cases and response codes for the licensing system: first install/login, trial activation, Google Play purchase verification, offline behavior, device transfer, refunds/revocations, and error handling. Use this as the single-source visual reference for developers and QA.

---

## Legend

- `200` — Success
- `400` — Bad Request (missing/invalid fields)
- `401` — Unauthorized (invalid Firebase token)
- `402` — Payment required / Payment verification failed
- `403` — Forbidden (blocked / rate limit / transfer not allowed)
- `404` — Not Found (account/device not found)
- `409` — Conflict (trial already used / purchase token reuse)
- `500` — Internal Server Error

---

## 1. Overall Start & License Check Flow

```mermaid
flowchart TD
  A[App Start] --> B[Ensure Firebase Auth]
  B -->|No token| C[Show Login Screen]
  B -->|Token OK| D[Build deviceId (Widevine)]
  D --> E[Load local encrypted cache]
  E --> F{offlineAllowedUntil >= now?}
  F -->|Yes| G[Allow offline access]
  F -->|No| H[Call getLicenseStatus(accountId, deviceId)]

  H --> I{HTTP response}
  I -->|401| R401[Force re-login]
  I -->|400| R400[Show error & retry]
  I -->|200 - no_license| S1[Show Start Trial / Buy Now]
  I -->|200 - trial_active| S2[Allow access; show remaining days]
  I -->|200 - trial_expired| S3[Show Buy Now]
  I -->|200 - license_active| S4[Allow access; apply branding if enterprise]
  I -->|200 - linked_to_other_device| S5[Show Transfer Prompt]
  I -->|200 - license_revoked| S6[Show support/contact; block]
  I -->|500| R500[Show server error; retry]

  G --> BG[Background async getLicenseStatus when possible]
```

---

## 2. Trial Activation Flow (explicit)

```mermaid
flowchart TD
  T1[User taps Start Trial] --> T2[Call startTrial(accountId, deviceId)]
  T2 --> T3{HTTP response}
  T3 -->|200| TA[Trial started; return trialEndTime, offlineAllowedUntil]
  T3 -->|401| TB[Re-login required]
  T3 -->|403| TC[Account blocked]
  T3 -->|409| TD[Trial already used - show message]
  T3 -->|500| TE[Server error - retry]
```

---

## 3. Purchase Flow (Google Play Billing & verify)

```mermaid
flowchart TD
  P1[User chooses Buy Now] --> P2[Trigger Google Play Billing flow in-app]
  P2 --> P3{Play Billing result}
  P3 -->|Success: purchaseToken, orderId| P4[Call verifyGooglePurchase(accountId, deviceId, purchaseToken, productId)]
  P3 -->|Failure or Cancel| Pfail[Show purchase failed / user cancelled]

  P4 --> P5{Server Google Play verification}
  P5 -->|Valid purchase| P6[Create purchases record; update accounts: licenseType, orderId, purchaseDate, linkedDeviceId; set offlineAllowedUntil = now+1day]
  P5 -->|Invalid| P7[Return 402 - Payment not verified]
  P5 -->|AlreadyUsed| P8[Return 409 - token/order already used]
  P5 -->|500| P9[Server error]

  P6 --> Pdone[200 - license_active returned to app; fetch branding if enterprise]
```

---

## 4. Offline / Online Enforcement Flow (detailed)

```mermaid
flowchart TD
  O1[App resume/start] --> O2[Check local cache]
  O2 --> O3{cache exists?}
  O3 -->|No| O4[Require immediate online getLicenseStatus]
  O3 -->|Yes| O5[Check offlineAllowedUntil]
  O5 -->|>= now| O6[Allow offline access]
  O5 -->|< now| O4

  O6 --> O7[Schedule background refresh: call getLicenseStatus asynchronously]
  O4 --> O8{Network available?}
  O8 -->|No| O9[Block app; show "connect to internet" message]
  O8 -->|Yes| O10[Call getLicenseStatus]

  O10 --> O11{response}
  O11 -->|200 license_active| O12[Update cache, set offlineAllowedUntil = now+1day, allow access]
  O11 -->|200 linked_to_other_device| O13[Show transfer prompt]
  O11 -->|200 trial_active| O14[Allow access; update cache]
  O11 -->|200 trial_expired| O15[Block features; show buy]
  O11 -->|402/500| O16[Show error; retry later]
```

---

## 5. Device Transfer Flow

```mermaid
flowchart TD
  TR1[Login on New Device] --> TR2[Call getLicenseStatus]
  TR2 --> TR3{response}
  TR3 -->|linked_to_other_device| TR4[Show transfer prompt to user - explain revocation]
  TR4 -->|User confirms| TR5[Call transferLicense(accountId, newDeviceId)]
  TR5 --> TR6{response}
  TR6 -->|200| TR7[Server: add transferHistory, mark old device revoked, set linkedDeviceId=newDeviceId, offlineAllowedUntil=now+1day]
  TR6 -->|403| TR8[Transfer disallowed (rate limit) - show message]
  TR6 -->|404| TR9[No license to transfer - show purchase prompt]
  TR6 -->|500| TR10[Server error - ask to retry or contact support]
  TR7 --> TR11[App updates cache; fetch branding if enterprise]
```

---

## 6. Refund / Revocation Flow (Google Play notifications)

```mermaid
flowchart TD
  RN1[Google Play refund/chargeback or periodic verification finds refund] --> RN2[Server receives notification / periodic poll]
  RN2 --> RN3[Find account by orderId/purchaseToken]
  RN3 --> RN4[Set accounts/{accountId}.licenseRevoked = true; update purchases log; set offlineAllowedUntil = now]
  RN4 --> RN5[Next time app calls getLicenseStatus -> 200 license_revoked or immediate block]
```

---

## 7. Error codes & client handling summary

```mermaid
flowchart LR
  E1[401 Unauthorized] --> E1a[Client: Force re-login via Firebase Auth]
  E2[400 Bad Request] --> E2a[Client: Show validation error; avoid retry until fixed]
  E3[402 Payment failed] --> E3a[Client: Show purchase failed; retry or contact support]
  E4[403 Forbidden] --> E4a[Client: Transfer rate-limited or account blocked; show message]
  E5[404 Not Found] --> E5a[Client: Treat as no_license; prompt register/start trial/buy]
  E6[409 Conflict] --> E6a[Client: Show conflict (trial used / purchase token used)]
  E7[500 Server Error] --> E7a[Client: Show "try again later" and log]
```

---

## 8. Sequence diagram (compact) — First install → Trial → Purchase → Transfer

```mermaid
sequenceDiagram
  participant App
  participant CloudFunc
  participant Firestore
  participant GooglePlay

  App->>CloudFunc: getLicenseStatus(accountId, deviceId)
  CloudFunc->>Firestore: read accounts/{accountId}
  Firestore-->>CloudFunc: returns no_license
  CloudFunc-->>App: 200 no_license
  App->>App: show Start Trial / Buy Now

  App->>CloudFunc: startTrial(accountId, deviceId)
  CloudFunc->>Firestore: write accounts/{accountId} trial fields
  Firestore-->>CloudFunc: write success
  CloudFunc-->>App: 200 trial_active + offlineAllowedUntil

  App->>GooglePlay: initiate purchase (productId)
  GooglePlay-->>App: purchaseToken, orderId
  App->>CloudFunc: verifyGooglePurchase(purchaseToken, productId)
  CloudFunc->>GooglePlay: verify purchaseToken via Play API
  GooglePlay-->>CloudFunc: purchase OK + orderId
  CloudFunc->>Firestore: write purchases; update accounts linkedDeviceId, licenseType
  CloudFunc-->>App: 200 license_active

  App (new device)->>CloudFunc: getLicenseStatus(accountId, newDeviceId)
  CloudFunc->>Firestore: read accounts; linkedDeviceId != newDeviceId
  CloudFunc-->>App: 200 linked_to_other_device
  App->>User: prompt transfer
  App->>CloudFunc: transferLicense(accountId, newDeviceId)
  CloudFunc->>Firestore: update accounts linkedDeviceId, mark old device revoked, write transferHistory
  CloudFunc-->>App: 200 license_active
```

---

## 9. Notes for Devs

- All timestamps are UTC ISO8601.
- Offline cache must be encrypted and tamper-detected.
- Use Firestore transactions for all writes that change license state to avoid race conditions.
- Log every state-changing operation to `purchases` and `audit` collections.

---

If you want, I can export these diagrams as a PNG/SVG set or create a simplified single-page printable diagram. Which output format do you prefer?
