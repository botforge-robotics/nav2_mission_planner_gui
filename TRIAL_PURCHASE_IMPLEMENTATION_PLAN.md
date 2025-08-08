# Nav2 Mission Planner - Firebase Trial & Purchase Implementation Plan

## 📋 Table of Contents

1. [Overview](#overview)
2. [Current System Analysis](#current-system-analysis)
3. [New System Architecture](#new-system-architecture)
4. [Implementation Plan](#implementation-plan)
5. [Firebase System Design](#firebase-system-design)
6. [Google Play Billing Integration](#google-play-billing-integration)
7. [Enterprise System Design](#enterprise-system-design)
8. [Enhanced Trial System](#enhanced-trial-system)
9. [User Experience Flow](#user-experience-flow)
10. [Screen Design Strategy](#screen-design-strategy)
11. [Data Storage Strategy](#data-storage-strategy)
12. [Error Handling Strategy](#error-handling-strategy)
13. [Testing Strategy](#testing-strategy)
14. [Google Play Console Setup](#google-play-console-setup)
15. [Deployment Strategy](#deployment-strategy)
16. [Implementation Timeline](#implementation-timeline)
17. [Risk Mitigation](#risk-mitigation)
18. [Backend Cloud Functions Implementation](#backend-cloud-functions-implementation)
19. [Response Codes and Formats](#response-codes-and-formats)
20. [Conclusion](#conclusion)

---

## Overview

Implement Firebase-based trial and purchase system with Google Play billing, keeping existing trial logic but replacing license activation with Google Play in-app purchases. Support individual and enterprise plans with secure purchase verification.

---

## Current System Analysis

### Existing Components to KEEP:

- **Trial Service** - Keep existing trial logic and screens
- **Trial Provider** - Keep existing trial state management
- **Trial Screens** - Keep existing trial UI
- **Device Service** - Keep for MediaDrm Widevine device ID
- **Secure Storage** - Keep for local data storage

### Existing Components to REMOVE:

- **License Activation** - Replace with Google Play purchases
- **License Provider** - Replace with purchase provider
- **License Screens** - Replace with purchase screens
- **API Service** - Replace with Firebase functions
- **License Verification** - Replace with Google Play verification
- **Token-based Licensing** - Replace with Google Play purchase verification

### Current Dependencies to REMOVE:

- `http` - Replace with Firebase
- `connectivity_plus` - Replace with Firebase
- `qr_code_scanner_plus` - No longer needed

### Current Dependencies to KEEP:

- `device_info_plus` - For MediaDrm Widevine
- `package_info_plus` - For app info
- `crypto` - For data encryption
- `flutter_secure_storage` - For secure storage
- `shared_preferences` - For local storage

---

## New System Architecture

### Core Components:

#### 1. Trial System (KEEP EXISTING)

- **Duration:** 7 days from first app launch
- **Storage:** Local encrypted storage + Firebase Firestore
- **Verification:** Check on app launch with daily online verification
- **Expiration:** Automatic after 7 days
- **Offline Support:** 1-day grace period for daily online verification

#### 2. Purchase System (NEW)

- **Type:** Google Play in-app purchases
- **Products:**
  - `nav2_mission_planner_individual` - Individual license
  - `nav2_mission_planner_enterprise` - Enterprise license
- **Restoration:** Standard Google Play restoration
- **Verification:** Google Play server verification + Firebase validation
- **Device Binding:** Widevine ID for single-device license binding
- **Offline Support:** Cached license and branding data for offline usage

#### 3. Access Control

- **States:** Trial Active, Trial Expired, Individual Purchased, Enterprise Purchased
- **Logic:** Check trial first, then purchase, then daily verification
- **UI:** Show appropriate screens based on state
- **Daily Verification:** Grace period allows offline usage but requires daily online check

#### 4. Firebase System

- **Database:** Firestore for trial/purchase data
- **Functions:** Cloud Functions for secure operations
- **Authentication:** Anonymous auth for device binding
- **Security:** Device-specific access rules
- **Branding Storage:** Enterprise branding data tied to Google Play account
- **License Tracking:** Purchase verification and device binding tracking

---

## Implementation Plan

### Phase 1: Add Firebase Dependencies

#### New Dependencies to Add:

```yaml
dependencies:
  # Firebase
  firebase_core: ^2.24.2
  firebase_auth: ^4.15.3
  cloud_firestore: ^4.13.6
  firebase_functions: ^4.5.8

  # Google Play Billing
  in_app_purchase: ^3.1.13
  in_app_purchase_android: ^0.3.7+1

  # Keep existing dependencies
  device_info_plus: ^10.1.0
  package_info_plus: ^8.3.0
  crypto: ^3.0.3
  flutter_secure_storage: ^9.0.0
  shared_preferences: ^2.5.3
```

### Phase 2: Create New System Components

#### New Files to Create:

1. **`lib/constants/purchase_constants.dart`**

   - Product IDs for individual/enterprise
   - Trial duration constants
   - Storage keys
   - Grace period settings

2. **`lib/services/firebase_service.dart`**

   - Firebase initialization
   - Anonymous authentication
   - Firestore operations
   - Cloud Functions calls

3. **`lib/services/purchase_service.dart`**

   - Google Play purchase handling
   - Purchase verification with Google Play
   - Purchase restoration
   - Individual vs Enterprise handling

4. **`lib/services/enterprise_service.dart`**

   - Enterprise code validation
   - Branding data management
   - Organization setup

5. **`lib/providers/purchase_provider.dart`**

   - Purchase state management
   - Individual/Enterprise status
   - UI state control
   - Firebase sync coordination

6. **`lib/screens/purchase/individual_purchase_screen.dart`**

   - Individual purchase flow
   - Google Play billing integration
   - Purchase benefits display

7. **`lib/screens/purchase/enterprise_purchase_screen.dart`**

   - Enterprise code input
   - Enterprise purchase flow
   - Branding setup

8. **`lib/models/purchase_model.dart`**
   - Purchase states
   - Individual/Enterprise models
   - Firebase data models

### Phase 3: Update Existing Components

#### Modified Files:

1. **`lib/services/trial_service.dart` (UPDATE)**

   - Add Firebase sync
   - Keep existing trial logic
   - Add cloud functions integration

2. **`lib/providers/license_provider.dart` (REPLACE)**

   - Replace with purchase provider
   - Keep trial-related methods
   - Add purchase state management

3. **`lib/main.dart` (UPDATE)**

   - Initialize Firebase
   - Add purchase provider
   - Keep trial provider
   - Update initialization

---

## Firebase System Design

### Firestore Database Structure:

#### Collections:

1. **`trials`** - Trial data by device ID

```javascript
trials/{widevine_device_id} = {
  trialStartDate: timestamp,
  trialStatus: "active" | "expired" | "grace_period",
  gracePeriodDays: number,
  lastSync: timestamp,
  deviceId: "widevine_123"
}
```

2. **`purchases`** - Purchase data by device ID

```javascript
purchases/{widevine_device_id} = {
  purchaseType: "individual" | "enterprise",
  purchaseToken: "google_play_token",
  purchaseDate: timestamp,
  verified: boolean,
  deviceId: "widevine_123",
  googlePlayAccount: "user@gmail.com"
}
```

3. **`enterprises`** - Enterprise codes and branding

```javascript
enterprises/{enterprise_code} = {
  code: "ABC123",
  organizationName: "Company Name",
  brandingData: {
    logo: "url",
    colors: {...},
    customizations: {...}
  },
  active: boolean,
  maxDevices: number,
  devices: ["widevine_123", "widevine_456"]
}
```

### Cloud Functions:

#### 1. **`registerDevice`** - Device registration

```javascript
// Input: { deviceId, appVersion, platform, etc. }
// Output: { success: true, deviceId }
// Security: Allow anonymous auth, validate device data
```

#### 2. **`startTrial`** - Start trial for device

```javascript
// Input: { deviceId }
// Output: { success: true, trialStartDate }
// Security: Allow anonymous auth, validate device exists
```

#### 3. **`verifyPurchase`** - Verify Google Play purchase

```javascript
// Input: { deviceId, purchaseToken, productId }
// Output: { success: true, purchaseType }
// Security: Verify with Google Play API, validate purchase
```

#### 4. **`validateEnterpriseCode`** - Validate enterprise code

```javascript
// Input: { enterpriseCode, deviceId }
// Output: { success: true, brandingData }
// Security: Validate code, check device limits
```

### Security Rules:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Trials - read/write for authenticated users to their own data
    match /trials/{deviceId} {
      allow read, write: if request.auth != null &&
                           request.auth.uid == deviceId;
    }

    // Purchases - read/write for authenticated users to their own data
    match /purchases/{deviceId} {
      allow read, write: if request.auth != null &&
                           request.auth.uid == deviceId;
    }

    // Enterprises - read for authenticated users, write only via Cloud Functions
    match /enterprises/{code} {
      allow read: if request.auth != null;
      allow write: if false; // Only Cloud Functions can write
    }
  }
}
```

---

## Google Play Billing Integration

### Product Configuration:

#### 1. Individual License Product:

```yaml
Product ID: nav2_mission_planner_individual
Type: Non-consumable
Price: $X.XX (one-time)
Description: Individual license for Nav2 Mission Planner
```

#### 2. Enterprise License Product:

```yaml
Product ID: nav2_mission_planner_enterprise
Type: Non-consumable
Price: $X.XX (one-time)
Description: Enterprise license for Nav2 Mission Planner
```

### Purchase Flow:

#### Individual Purchase:

```
1. User clicks "Buy Individual License"
2. Google Play billing dialog appears
3. User completes purchase
4. App receives purchase token
5. App calls Cloud Function to verify purchase
6. Cloud Function verifies with Google Play API
7. License bound to device using Widevine ID
8. Purchase data stored in Firebase
9. User gets individual access
10. License cached locally for offline usage
```

#### Enterprise Purchase:

```
1. User clicks "Buy Enterprise License"
2. User enters enterprise code
3. App validates code with Cloud Function
4. If valid, Google Play billing dialog appears
5. User completes purchase
6. App receives purchase token
7. App calls Cloud Function to verify purchase
8. Cloud Function verifies with Google Play API
9. License bound to device using Widevine ID
10. Enterprise branding retrieved from Firebase
11. Branding applied and cached locally
12. Purchase data stored in Firebase
13. User gets enterprise access with branding
14. License and branding cached for offline usage
```

### Purchase Verification Security:

#### 1. Google Play API Verification:

```javascript
// Cloud Function verifies purchase with Google Play API
const googlePlayResponse = await googlePlayAPI.verifyPurchase({
  packageName: "com.botforge.nav2missionplanner",
  productId: purchaseToken,
  purchaseToken: purchaseToken,
});

if (googlePlayResponse.purchaseState === "PURCHASED") {
  // Purchase is valid
  return { success: true, purchaseType: productId };
}
```

#### 2. License Verification Steps:

**✅ Individual License Verification:**

1. App queries Google Play Billing to verify purchase
2. App uses Widevine ID to bind the license to the device
3. License data and purchase plan (Individual) are synced to Firebase for tracking

**✅ Enterprise License Verification:**

1. App queries Google Play Billing to verify purchase
2. App uses Widevine ID to bind the license to the device
3. License data and purchase plan (Enterprise) are synced to Firebase for tracking
4. Enterprise branding details retrieved from Firebase using Google Play account ID
5. Branding is tied to this account and stored in Firebase along with the Widevine ID

#### 2. Firebase Storage:

```javascript
// Store verified purchase in Firebase
await firestore.collection("purchases").doc(deviceId).set({
  purchaseType: productId,
  purchaseToken: purchaseToken,
  purchaseDate: new Date(),
  verified: true,
  deviceId: deviceId,
  widevineId: deviceId,
  googlePlayAccount: userEmail,
  enterpriseCode: enterpriseCode, // Only for enterprise
  brandingData: brandingData, // Only for enterprise
});
```

---

## Enterprise System Design

### Enterprise Code System:

#### 1. Code Generation:

- **Format:** 6-character alphanumeric (e.g., "ABC123")
- **Uniqueness:** Each code is unique
- **Validation:** Cloud Function validates codes
- **Branding:** Each code is tied to specific organization branding

#### 2. Branding Retrieval (Enterprise only):

After verifying an Enterprise plan purchase, the app retrieves branding details (logo, theme, app name, etc.) from Firebase using the Google Play account ID.

Branding is tied to this account and stored in Firebase along with the Widevine ID for future reactivation.

#### 3. Branding System:

- **Logo:** Custom organization logo
- **Colors:** Custom color scheme
- **Text:** Custom app text/branding
- **Features:** Organization-specific features
- **Caching:** Branding cached locally for offline usage

#### 4. Enterprise Purchase Flow:

```
1. User enters enterprise code
2. App calls Cloud Function to validate code
3. If valid, show enterprise purchase option
4. User completes Google Play purchase
5. App verifies purchase with Google Play API
6. App retrieves branding from Firebase using Google Play account
7. App applies enterprise branding and caches locally
8. Store enterprise data in Firebase with Widevine ID binding
```

---

## Enhanced Trial System (Keep Existing + Firebase)

### Trial States:

```
1. NOT_STARTED - First time user
2. ACTIVE - Trial is running (0-7 days)
3. GRACE_PERIOD - Trial expired, grace period active (1 day)
4. EXPIRED - Grace period expired, need internet
5. INDIVIDUAL_PURCHASED - Individual license active
6. ENTERPRISE_PURCHASED - Enterprise license active
```

### Trial + Firebase Integration:

```
Local Trial Data → Firebase Sync → Cloud Functions
Firebase Data → Local Storage → App Access
```

### Daily Verification System:

```
- Grace period: 1 day for offline usage
- Daily online verification required for trial and active licenses
- Grace period resets after successful verification
- Grace period decreases each day without verification
- Purchased users: Unlimited grace period for offline usage
```

---

## User Experience Flow

### Trial User:

```
1. App Launch → Check Local Trial → Sync with Firebase → Allow Access
2. Daily: Online verification required, grace period for offline usage
3. Trial Expired: Show purchase options (Individual/Enterprise)
4. Grace period resets after successful daily verification
```

### Individual Purchase User:

```
1. App Launch → Check Local Purchase → Verify with Google Play → Full Access
2. No trial/purchase UI
3. Full access forever
4. Purchase restored automatically
5. Daily online verification with unlimited grace period for offline usage
```

### Enterprise Purchase User:

```
1. App Launch → Check Local Purchase → Verify with Google Play → Apply Branding → Full Access
2. Custom branding applied
3. Organization-specific features
4. Full access forever
5. Purchase restored automatically
6. Daily online verification with unlimited grace period for offline usage
```

---

## Screen Design Strategy

### 1. Trial Welcome Screen (KEEP EXISTING)

- App introduction
- "Start 7-Day Trial" button
- "Purchase Individual License" button
- "Purchase Enterprise License" button
- Trial benefits listed

### 2. Trial Active Screen (KEEP EXISTING)

- Trial countdown
- Days remaining
- Purchase buttons (Individual/Enterprise)
- Continue using app

### 3. Purchase Options Screen (NEW)

- Individual license benefits and price
- Enterprise license benefits and price
- "Buy Individual" button
- "Buy Enterprise" button
- Enterprise code input field

### 4. Enterprise Code Screen (NEW)

- Enterprise code input
- Code validation
- Organization branding preview
- "Continue to Purchase" button

### 5. Individual Purchase Screen (NEW)

- Individual license benefits
- Price display
- "Buy Now" button
- Terms and conditions

### 6. Enterprise Purchase Screen (NEW)

- Enterprise license benefits
- Organization branding display
- Price display
- "Buy Now" button
- Terms and conditions

---

## Data Storage Strategy

### Local Storage (SharedPreferences):

```
- trial_start_date: ISO date string
- trial_status: "active", "expired", "grace_period", "individual_purchased", "enterprise_purchased"
- purchase_verified: boolean
- grace_period_days: int (starts at 1)
- last_firebase_sync: ISO date string
- last_verification_date: ISO date string
- enterprise_code: string (if enterprise user)
- branding_data: JSON string (if enterprise user)
```

### Firebase Firestore:

```
- trials/{deviceId}: Trial data
- purchases/{deviceId}: Purchase data
- enterprises/{code}: Enterprise data
```

### Encryption:

```
- Encrypt sensitive data
- Use device-specific keys
- Prevent easy tampering
```

---

## Error Handling Strategy

### 1. Network Issues:

- Work offline with cached data
- Verify when internet available
- Graceful degradation
- Daily verification with grace period for offline usage

### 2. Google Play Issues:

- Fallback to local verification
- Retry mechanism
- User-friendly error messages
- Grace period extension

### 3. Purchase Issues:

- Handle purchase failures
- Retry purchase flow
- Clear error messages
- Daily verification with grace period for purchase verification

### 4. Firebase Issues:

- Continue with local data
- Retry sync when possible
- Conflict resolution
- Data integrity checks
- Daily verification with grace period for offline usage

---

## Testing Strategy

### 1. Trial Testing:

- Test trial start with Firebase
- Test trial expiration
- Test trial countdown
- Test trial reset scenarios
- Test grace period system

### 2. Purchase Testing:

- Test individual purchase flow
- Test enterprise purchase flow
- Test purchase restoration
- Test purchase verification
- Test purchase errors

### 3. Firebase Testing:

- Test Firestore operations
- Test Cloud Functions
- Test offline functionality
- Test sync failures

### 4. Enterprise Testing:

- Test enterprise code validation
- Test branding application
- Test device limits
- Test enterprise purchase flow

### 5. Edge Cases:

- No internet connection
- Google Play unavailable
- Firebase unavailable
- App reinstall
- Device changes
- Daily verification failure
- Multiple device usage

---

## Google Play Console Setup

### 1. Create In-App Products:

#### Individual License:

```
Product ID: nav2_mission_planner_individual
Type: Non-consumable
Price: $X.XX (one-time)
Description: Individual license for Nav2 Mission Planner
```

#### Enterprise License:

```
Product ID: nav2_mission_planner_enterprise
Type: Non-consumable
Price: $X.XX (one-time)
Description: Enterprise license for Nav2 Mission Planner
```

### 2. Configure Firebase Project:

```
- Create Firebase project
- Enable Firestore database
- Enable Cloud Functions
- Configure security rules
- Set up authentication
```

### 3. Android Configuration:

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<meta-data
    android:name="com.google.android.gms.games.APP_ID"
    android:value="@string/game_services_project_id"/>
```

### 4. Testing:

```
- Use test accounts
- Test purchase flow
- Test trial expiration
- Test purchase restoration
- Test Firebase sync
- Test offline functionality
```

---

## Deployment Strategy

### 1. Firebase Setup:

- Create Firebase project
- Configure Firestore
- Deploy Cloud Functions
- Set up security rules
- Configure authentication

### 2. Google Play Console Setup:

- Configure in-app products
- Set up test accounts
- Configure billing
- Test purchase flow

### 3. App Configuration:

- Add Firebase configuration
- Configure Google Play billing
- Test all flows
- Prepare for release

---

## Implementation Timeline

### Week 1: Firebase Setup

- Set up Firebase project
- Configure Firestore
- Deploy Cloud Functions
- Test basic operations

### Week 2: Google Play Billing

- Add in-app purchase dependencies
- Configure Google Play products
- Implement purchase flow
- Test purchase verification

### Week 3: Trial + Firebase Integration

- Update existing trial service
- Add Firebase sync
- Test trial with Firebase
- Test grace period system

### Week 4: Enterprise System

- Implement enterprise code system
- Add branding management
- Test enterprise purchase flow
- Test enterprise features

### Week 5: Integration & Testing

- Integrate all components
- End-to-end testing
- Bug fixes
- Performance optimization

### Week 6: Deployment

- Configure production Firebase
- Set up production Google Play
- Test with test accounts
- Prepare for release

---

## Risk Mitigation

### 1. Trial Abuse:

- Accept some abuse as cost of simplicity
- Monitor abuse patterns
- Consider enhanced security if needed
- Daily verification limits abuse

### 2. Purchase Issues:

- Robust error handling
- Clear user feedback
- Support documentation
- Grace period for verification

### 3. Firebase Issues:

- Local fallback system
- Conflict resolution
- Data integrity checks
- User-friendly error messages
- Daily verification with grace period for offline usage

### 4. Enterprise Issues:

- Code validation security
- Device limit enforcement
- Branding data validation
- Enterprise support system

## Conclusion

This enhanced plan provides a comprehensive approach to implementing a Firebase-based trial and purchase system with Google Play billing that includes:

1. **Keep Existing Trial Logic** - No removal of current trial system
2. **Replace License Activation** - Google Play in-app purchases
3. **Individual/Enterprise Plans** - Two purchase options
4. **Firebase Integration** - Secure cloud storage and functions
5. **MediaDrm Widevine** - Secure device identification
6. **Secure Purchase Verification** - Google Play API + Firebase validation

The implementation prioritizes:

1. **Backward Compatibility** - Keep existing trial functionality
2. **Security** - Google Play verification + Firebase security
3. **User Experience** - Smooth trial to purchase transition
4. **Enterprise Support** - Custom branding and features
5. **Offline Support** - Grace period and local storage

This approach provides a robust, secure, and user-friendly system that leverages Google Play's trusted billing infrastructure while maintaining the existing trial experience.

---

## Device Management & Offline Behavior

### Reset/Reinstall Logic:

**On reinstall, the app revalidates purchase via Play Billing.**

If the same Widevine ID and Google Play ID are found, the previous license and branding are restored from Firebase.

### Multi-Device Prevention:

**Although Google Play allows purchases to be shared across devices, we bind the license to a single device using Widevine ID.**

If the app is installed on a second device using the same account, the license will only be active on the first device where it was activated.

### Offline Behavior:

**Once branding and license info are downloaded after purchase verification, they are cached locally.**

App can function offline with full features after initial activation.

---

## Backend Cloud Functions Implementation

### **🔐 Security Implementation**

#### **1. Google Play API Integration:**

```javascript
// Google Play API verification
const googlePlayAPI = require("google-play-api");

async function verifyGooglePlayPurchase(purchaseToken, productId) {
  try {
    const response = await googlePlayAPI.verifyPurchase({
      packageName: "com.botforge.nav2missionplanner",
      productId: productId,
      purchaseToken: purchaseToken,
    });

    return {
      valid: response.purchaseState === "PURCHASED",
      purchaseState: response.purchaseState,
      purchaseTime: response.purchaseTime,
      orderId: response.orderId,
    };
  } catch (error) {
    throw new Error("Google Play verification failed");
  }
}
```

#### **2. Device Authentication:**

```javascript
// Anonymous authentication for devices
const admin = require("firebase-admin");

async function authenticateDevice(deviceId) {
  try {
    const user = await admin.auth().createCustomToken(deviceId);
    return user;
  } catch (error) {
    throw new Error("Device authentication failed");
  }
}
```

#### **3. Firestore Security Rules:**

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Trials - read/write for authenticated users to their own data
    match /trials/{deviceId} {
      allow read, write: if request.auth != null &&
                         request.auth.uid == deviceId;
    }

    // Purchases - read/write for authenticated users to their own data
    match /purchases/{deviceId} {
      allow read, write: if request.auth != null &&
                         request.auth.uid == deviceId;
    }

    // Enterprises - read for authenticated users, write only via Cloud Functions
    match /enterprises/{code} {
      allow read: if request.auth != null;
      allow write: if false; // Only Cloud Functions can write
    }

    // Devices - read/write for authenticated users to their own data
    match /devices/{deviceId} {
      allow read, write: if request.auth != null &&
                         request.auth.uid == deviceId;
    }

    // Feedback - read for admins, write for authenticated users
    match /feedback/{feedbackId} {
      allow read: if request.auth != null &&
                   request.auth.token.admin == true;
      allow write: if request.auth != null;
    }
  }
}
```

### **📊 Database Schema**

#### **1. Devices Collection (Updated Structure):**

```javascript
devices/{deviceId} = {
  // Device Information
  deviceId: "3X8ew9dXWzr1qdD9Y5VwYlHXcrEldy4oimmN1cdTVpk=",
  deviceModel: "moto g82 5G",
  platform: "android",
  androidVersion: "13",

  // App Information
  appVersion: "1.2.0",
  appBuildNumber: "4",

  // Timestamps
  installationTime: "2025-08-06T21:35:06.836409",
  registrationTime: timestamp,
  createdAt: timestamp,
  updatedAt: timestamp,

  // Trial Information (included in device document)
  trialStartTime: timestamp | null,
  trialEndTime: timestamp | null,
  trialDuration: 7,

  // Purchase Information (separate collection)
  purchaseType: "individual" | "enterprise" | null,
  purchaseToken: "google_play_token" | null,
  verified: boolean | null,

  // Enterprise Information (only for enterprise license)
  enterpriseId: "ABC123" | null
}
```

#### **2. Purchases Collection (Separate for purchases):**

```javascript
purchases/{deviceId} = {
  deviceId: "3X8ew9dXWzr1qdD9Y5VwYlHXcrEldy4oimmN1cdTVpk=",
  widevineId: "3X8ew9dXWzr1qdD9Y5VwYlHXcrEldy4oimmN1cdTVpk=",
  purchaseType: "individual" | "enterprise",
  purchaseToken: "google_play_token",
  productId: "nav2_mission_planner_individual",
  purchaseDate: timestamp,
  verified: boolean,
  googlePlayAccount: "user@gmail.com",
  enterpriseCode: "ABC123", // Only for enterprise
  brandingData: {...}, // Only for enterprise
  createdAt: timestamp,
  updatedAt: timestamp
}
```

#### **3. Enterprises Collection:**

```javascript
enterprises/{code} = {
  code: "ABC123",
  organizationName: "Acme Corporation",
  GST: "",
  brandingData: {
    logoUrl: "https://company.com/logo.png",
    faviconIcon: "https://company.com/favicon.png",
    themeColor: "#FF5733",
    footerCredits: "© 2025 Acme Corp",
    tagLine: "Professional Mission Planning",
    companyName: "Acme Corp",
    appTitle: "Acme Mission Planner",
    supportEmail: "support@acme.com",
    website: "https://acme.com"
  },
  active: boolean,
  createdAt: timestamp,
  updatedAt: timestamp
}
```

#### **4. Feedback Collection:**

```javascript
feedback/{feedbackId} = {
  deviceId: "3X8ew9dXWzr1qdD9Y5VwYlHXcrEldy4oimmN1cdTVpk=",
  feedback: "Great app!",
  rating: 5,
  category: "general",
  createdAt: timestamp
}
```

### **📊 Firestore Security Rules (Updated):**

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Devices - read/write for authenticated users to their own data
    match /devices/{deviceId} {
      allow read, write: if request.auth != null &&
                         request.auth.uid == deviceId;
    }

    // Purchases - read/write for authenticated users to their own data
    match /purchases/{deviceId} {
      allow read, write: if request.auth != null &&
                         request.auth.uid == deviceId;
    }

    // Enterprises - read for authenticated users, write only via Cloud Functions
    match /enterprises/{code} {
      allow read: if request.auth != null;
      allow write: if false; // Only Cloud Functions can write
    }

    // Feedback - read for admins, write for authenticated users
    match /feedback/{feedbackId} {
      allow read: if request.auth != null &&
                   request.auth.token.admin == true;
      allow write: if request.auth != null;
    }
  }
}
```

### **🔧 Cloud Function Implementation Example:**

#### **`registerDevice` Implementation:**

```javascript
const functions = require("firebase-functions");
const admin = require("firebase-admin");

exports.registerDevice = functions.https.onCall(async (data, context) => {
  try {
    const {
      deviceId,
      deviceModel,
      platform,
      androidVersion,
      appVersion,
      appBuildNumber,
      installationTime,
    } = data;

    // Validate required fields
    if (!deviceId || !deviceModel || !platform || !appVersion) {
      return createErrorResponse(400, "Missing required device information");
    }

    const db = admin.firestore();
    const deviceRef = db.collection("devices").doc(deviceId);

    // Check if device already exists
    const deviceDoc = await deviceRef.get();

    if (deviceDoc.exists) {
      // Device exists - return existing data
      const deviceData = deviceDoc.data();
      return createSuccessResponse(deviceData, "Device already registered");
    } else {
      // New device - create with null trial dates
      const now = admin.firestore.Timestamp.now();
      const deviceData = {
        deviceId,
        deviceModel,
        platform,
        androidVersion,
        appVersion,
        appBuildNumber,
        installationTime,
        registrationTime: now,
        createdAt: now,
        updatedAt: now,
        trialStartTime: null,
        trialEndTime: null,
        trialDuration: 7,
        purchaseType: null,
        purchaseToken: null,
        verified: null,
      };

      await deviceRef.set(deviceData);

      return createSuccessResponse(
        deviceData,
        "Device registered successfully"
      );
    }
  } catch (error) {
    console.error("registerDevice error:", error);
    return createErrorResponse(500, "Internal server error");
  }
});
```

This updated implementation matches your existing device model structure and implements the registration flow as described, where trial data is included in the device document and the app handles registration on launch.

## **📋 Response Codes and Formats**

### **🔧 Standard Response Format**

#### **Success Response Format:**

```javascript
{
  "success": true,
  "data": {
    // Function-specific data
  },
  "message": "Operation completed successfully",
  "timestamp": "2025-08-06T21:35:09.000Z"
}
```

#### **Error Response Format:**

```javascript
{
  "success": false,
  "error": {
    "code": 400,
    "message": "Invalid request data",
    "details": "Missing required field: deviceId",
    "timestamp": "2025-08-06T21:35:09.000Z"
  }
}
```

### **📊 HTTP Status Codes**

#### **2xx Success Codes:**

- **200 OK** - Request successful
- **201 Created** - Resource created successfully
- **204 No Content** - Request successful, no content to return

#### **4xx Client Error Codes:**

- **400 Bad Request** - Invalid request data
- **401 Unauthorized** - Authentication required
- **403 Forbidden** - Access denied
- **404 Not Found** - Resource not found
- **409 Conflict** - Resource already exists
- **422 Unprocessable Entity** - Validation failed

#### **5xx Server Error Codes:**

- **500 Internal Server Error** - Server error
- **502 Bad Gateway** - External service error
- **503 Service Unavailable** - Service temporarily unavailable

### **🔧 Function-Specific Response Codes**

#### **1. Device Management Functions:**

##### **`registerDevice` Response Codes:**

```javascript
// Success (200)
{
  "success": true,
  "data": {
    "deviceId": "3X8ew9dXWzr1qdD9Y5VwYlHXcrEldy4oimmN1cdTVpk=",
    "deviceModel": "moto g82 5G",
    "platform": "android",
    "androidVersion": "13",
    "appVersion": "1.2.0",
    "appBuildNumber": "4",
    "installationTime": "2025-08-06T21:35:06.836409",
    "registrationTime": "2025-08-06T21:35:09.000Z",
    "createdAt": "2025-08-06T21:35:09.000Z",
    "updatedAt": "2025-08-06T21:35:09.000Z",
    "trialStartTime": null,
    "trialEndTime": null,
    "trialDuration": 7,
    "purchaseType": null,
    "purchaseToken": null,
    "verified": null
  },
  "message": "Device registered successfully",
  "timestamp": "2025-08-06T21:35:09.000Z"
}

// Error (400) - Missing required fields
{
  "success": false,
  "error": {
    "code": 400,
    "message": "Missing required device information",
    "details": "Required fields: deviceId, deviceModel, platform, appVersion",
    "timestamp": "2025-08-06T21:35:09.000Z"
  }
}

// Error (409) - Device already registered
{
  "success": false,
  "error": {
    "code": 409,
    "message": "Device already registered",
    "details": "Device with ID already exists in database",
    "timestamp": "2025-08-06T21:35:09.000Z"
  }
}

// Error (500) - Internal server error
{
  "success": false,
  "error": {
    "code": 500,
    "message": "Internal server error",
    "details": "Database connection failed",
    "timestamp": "2025-08-06T21:35:09.000Z"
  }
}
```

#### **2. Trial Management Functions:**

##### **`getTrialStatus` Response Codes:**

```javascript
// Success (200) - Active trial
{
  "success": true,
  "data": {
    "trialStatus": "active",
    "trialStartTime": "2025-08-06T21:38:13.000Z",
    "trialEndTime": "2025-08-13T21:38:13.000Z",
    "trialDuration": 7,
    "daysRemaining": 3,
    "lastVerification": "2025-08-06T21:40:00.000Z"
  },
  "message": "Trial status retrieved successfully",
  "timestamp": "2025-08-06T21:40:00.000Z"
}

// Success (200) - Trial not started
{
  "success": true,
  "data": {
    "trialStatus": "not_started",
    "trialStartTime": null,
    "trialEndTime": null,
    "trialDuration": 7,
    "daysRemaining": 7,
    "lastVerification": null,
  },
  "message": "Trial not started",
  "timestamp": "2025-08-06T21:40:00.000Z"
}

// Success (200) - Trial expired
{
  "success": true,
  "data": {
    "trialStatus": "expired",
    "trialStartTime": "2025-08-06T21:38:13.000Z",
    "trialEndTime": "2025-08-13T21:38:13.000Z",
    "trialDuration": 7,
    "daysRemaining": 0,
    "lastVerification": "2025-08-06T21:40:00.000Z",
  },
  "message": "Trial has expired",
  "timestamp": "2025-08-06T21:40:00.000Z"
}

// Error (400) - Invalid device ID
{
  "success": false,
  "error": {
    "code": 400,
    "message": "Invalid device ID",
    "details": "Device ID format is invalid",
    "timestamp": "2025-08-06T21:40:00.000Z"
  }
}

// Error (404) - Device not found
{
  "success": false,
  "error": {
    "code": 404,
    "message": "Device not found",
    "details": "Device with specified ID does not exist",
    "timestamp": "2025-08-06T21:40:00.000Z"
  }
}
```

##### **`startTrial` Response Codes:**

```javascript
// Success (200) - Trial started
{
  "success": true,
  "data": {
    "trialStartTime": "2025-08-06T21:38:13.000Z",
    "trialEndTime": "2025-08-13T21:38:13.000Z",
    "trialDuration": 7,
    "daysRemaining": 7
  },
  "message": "Trial started successfully",
  "timestamp": "2025-08-06T21:38:13.000Z"
}

// Error (400) - Invalid device ID
{
  "success": false,
  "error": {
    "code": 400,
    "message": "Invalid device ID",
    "details": "Device ID format is invalid",
    "timestamp": "2025-08-06T21:38:13.000Z"
  }
}

// Error (404) - Device not found
{
  "success": false,
  "error": {
    "code": 404,
    "message": "Device not found",
    "details": "Device with specified ID does not exist",
    "timestamp": "2025-08-06T21:38:13.000Z"
  }
}

// Error (409) - Trial already started
{
  "success": false,
  "error": {
    "code": 409,
    "message": "Trial already started",
    "details": "Trial has already been activated for this device",
    "timestamp": "2025-08-06T21:38:13.000Z"
  }
}
```

#### **3. Purchase Verification Functions:**

##### **`verifyIndividualPurchase` Response Codes:**

```javascript
// Success (200) - Purchase verified
{
  "success": true,
  "data": {
    "purchaseType": "individual",
    "verified": true,
    "purchaseDate": "2025-08-06T21:40:00.000Z",
    "productId": "nav2_mission_planner_individual",
    "purchaseToken": "google_play_purchase_token_123"
  },
  "message": "Individual purchase verified successfully",
  "timestamp": "2025-08-06T21:40:00.000Z"
}

// Error (400) - Invalid purchase data
{
  "success": false,
  "error": {
    "code": 400,
    "message": "Invalid purchase data",
    "details": "Missing required fields: deviceId, purchaseToken, productId",
    "timestamp": "2025-08-06T21:40:00.000Z"
  }
}

// Error (401) - Purchase verification failed
{
  "success": false,
  "error": {
    "code": 401,
    "message": "Purchase verification failed",
    "details": "Google Play API verification failed",
    "timestamp": "2025-08-06T21:40:00.000Z"
  }
}

// Error (409) - Purchase already verified
{
  "success": false,
  "error": {
    "code": 409,
    "message": "Purchase already verified",
    "details": "This purchase has already been verified",
    "timestamp": "2025-08-06T21:40:00.000Z"
  }
}
```

##### **`verifyEnterprisePurchase` Response Codes:**

```javascript
// Success (200) - Enterprise purchase verified
{
  "success": true,
  "data": {
    "purchaseType": "enterprise",
    "verified": true,
    "purchaseDate": "2025-08-06T21:40:00.000Z",
    "productId": "nav2_mission_planner_enterprise",
    "purchaseToken": "google_play_purchase_token_123",
    "enterpriseCode": "ABC123",
    "brandingData": {
      "logoUrl": "https://company.com/logo.png",
      "themeColor": "#FF5733",
      "companyName": "Acme Corp",
      "appTitle": "Acme Mission Planner"
    }
  },
  "message": "Enterprise purchase verified successfully",
  "timestamp": "2025-08-06T21:40:00.000Z"
}

// Error (400) - Invalid purchase data
{
  "success": false,
  "error": {
    "code": 400,
    "message": "Invalid purchase data",
    "details": "Missing required fields: deviceId, purchaseToken, productId, enterpriseCode",
    "timestamp": "2025-08-06T21:40:00.000Z"
  }
}

// Error (401) - Purchase verification failed
{
  "success": false,
  "error": {
    "code": 401,
    "message": "Purchase verification failed",
    "details": "Google Play API verification failed",
    "timestamp": "2025-08-06T21:40:00.000Z"
  }
}

// Error (402) - Invalid enterprise code
{
  "success": false,
  "error": {
    "code": 402,
    "message": "Invalid enterprise code",
    "details": "Enterprise code not found or inactive",
    "timestamp": "2025-08-06T21:40:00.000Z"
  }
}

// Error (403) - Device limit reached
{
  "success": false,
  "error": {
    "code": 403,
    "message": "Device limit reached",
    "details": "Maximum number of devices reached for this enterprise code",
    "timestamp": "2025-08-06T21:40:00.000Z"
  }
}
```

#### **4. Enterprise Management Functions:**

##### **`validateEnterpriseCode` Response Codes:**

```javascript
// Success (200) - Valid enterprise code
{
  "success": true,
  "data": {
    "valid": true,
    "enterpriseCode": "ABC123",
    "brandingData": {
      "logoUrl": "https://company.com/logo.png",
      "themeColor": "#FF5733",
      "companyName": "Acme Corp",
      "appTitle": "Acme Mission Planner",
      "supportEmail": "support@acme.com",
      "website": "https://acme.com"
    },
    "organizationName": "Acme Corporation"
  },
  "message": "Enterprise code validated successfully",
  "timestamp": "2025-08-06T21:40:00.000Z"
}

// Error (400) - Invalid enterprise code
{
  "success": false,
  "error": {
    "code": 400,
    "message": "Invalid enterprise code",
    "details": "Enterprise code format is invalid",
    "timestamp": "2025-08-06T21:40:00.000Z"
  }
}

// Error (401) - Enterprise code not found
{
  "success": false,
  "error": {
    "code": 401,
    "message": "Enterprise code not found",
    "details": "Enterprise code does not exist in database",
    "timestamp": "2025-08-06T21:40:00.000Z"
  }
}

// Error (402) - Enterprise code inactive
{
  "success": false,
  "error": {
    "code": 402,
    "message": "Enterprise code inactive",
    "details": "Enterprise code is not active",
    "timestamp": "2025-08-06T21:40:00.000Z"
  }
}


```

#### **5. License Verification Functions:**

##### **`verifyLicense` Response Codes:**

```javascript
// Success (200) - License verified
{
  "success": true,
  "data": {
    "licenseVerified": true,
    "licenseType": "individual",
    "licenseData": {
      "tokenId": "license_token_123",
      "licenseType": "individual",
      "issuedAt": "2025-08-06T21:35:09.000Z",
      "androidId": "3X8ew9dXWzr1qdD9Y5VwYlHXcrEldy4oimmN1cdTVpk=",
      "active": true,
      "userId": "user_123"
    }
  },
  "message": "License verified successfully",
  "timestamp": "2025-08-06T21:40:00.000Z"
}

// Error (400) - Invalid license data
{
  "success": false,
  "error": {
    "code": 400,
    "message": "Invalid license data",
    "details": "Missing required fields: deviceId, token",
    "timestamp": "2025-08-06T21:40:00.000Z"
  }
}

// Error (401) - License verification failed
{
  "success": false,
  "error": {
    "code": 401,
    "message": "License verification failed",
    "details": "License token is invalid or expired",
    "timestamp": "2025-08-06T21:40:00.000Z"
  }
}

// Error (404) - License not found
{
  "success": false,
  "error": {
    "code": 404,
    "message": "License not found",
    "details": "License with specified token does not exist",
    "timestamp": "2025-08-06T21:40:00.000Z"
  }
}
```

#### **6. Feedback Function:**

##### **`submitFeedback` Response Codes:**

```javascript
// Success (200) - Feedback submitted
{
  "success": true,
  "message": "Feedback submitted successfully"
}

// Error (400) - Invalid feedback data
{
  "success": false,
  "error": {
    "code": 400,
    "message": "Invalid feedback data",
    "details": "Missing required fields: name,email,message",
    "timestamp": "2025-08-06T21:40:00.000Z"
  }
}

// Error (422) - Validation failed
{
  "success": false,
  "error": {
    "code": 422,
    "message": "Validation failed",
    "timestamp": "2025-08-06T21:40:00.000Z"
  }
}
```

### **🔧 Error Handling Utilities**

#### **1. Create Error Response Function:**

```javascript
function createErrorResponse(code, message, details = null) {
  return {
    success: false,
    error: {
      code: code,
      message: message,
      details: details,
      timestamp: new Date().toISOString(),
    },
  };
}
```

#### **2. Create Success Response Function:**

```javascript
function createSuccessResponse(data, message = null) {
  return {
    success: true,
    data: data,
    message: message,
    timestamp: new Date().toISOString(),
  };
}
```

### **📊 Response Headers**

#### **Standard Headers:**

```javascript
{
  "Content-Type": "application/json",
  "Cache-Control": "no-cache",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE",
  "Access-Control-Allow-Headers": "Content-Type, Authorization"
}
```

#### **Rate Limiting Headers:**

```javascript
{
  "X-RateLimit-Limit": "100",
  "X-RateLimit-Remaining": "95",
  "X-RateLimit-Reset": "1640995200"
}
```

This comprehensive response codes and formats section provides all the necessary information for implementing proper error handling and response formatting in the Cloud Functions.

---

## Conclusion

This enhanced plan provides a comprehensive approach to implementing a Firebase-based trial and purchase system with Google Play billing that includes:

1. **Keep Existing Trial Logic** - No removal of current trial system
2. **Replace License Activation** - Google Play in-app purchases
3. **Individual/Enterprise Plans** - Two purchase options
4. **Firebase Integration** - Secure cloud storage and functions
5. **MediaDrm Widevine** - Secure device identification
6. **Secure Purchase Verification** - Google Play API + Firebase validation

The implementation prioritizes:

1. **Backward Compatibility** - Keep existing trial functionality
2. **Security** - Google Play verification + Firebase security
3. **User Experience** - Smooth trial to purchase transition
4. **Enterprise Support** - Custom branding and features
5. **Offline Support** - Grace period and local storage

This approach provides a robust, secure, and user-friendly system that leverages Google Play's trusted billing infrastructure while maintaining the existing trial experience.
