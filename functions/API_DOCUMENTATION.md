# Nav2 Mission Planner Cloud Functions API Documentation

## Overview

This document describes the API endpoints for the Nav2 Mission Planner Cloud Functions. All functions are Firebase Cloud Functions that can be called via the Firebase Functions SDK.

## Base Configuration

- **Runtime**: Node.js 24
- **Framework**: Firebase Functions v6
- **Authentication**: App Check (temporarily disabled for testing)
- **Database**: Firestore
- **Response Format**: JSON

## Standard Response Formats

### Success Response Format

```json
{
  "success": true,
  "data": {
    /* function-specific data */
  },
  "message": "Success message",
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

### Error Response Format

```json
{
  "success": false,
  "error": {
    "code": 400,
    "message": "Error message",
    "details": null,
    "timestamp": "2024-01-15T10:30:00.000Z"
  }
}
```

## HTTP Status Codes

| Code | Description                                     |
| ---- | ----------------------------------------------- |
| 200  | Success                                         |
| 400  | Bad Request (missing fields, validation errors) |
| 402  | Payment Required (inactive enterprise code)     |
| 404  | Not Found (device, enterprise code)             |
| 409  | Conflict (trial already started)                |
| 500  | Internal Server Error                           |

---

## API Endpoints

### 1. Device Registration

**Function**: `registerDevice`

#### Request Data

```json
{
  "deviceId": "gRt+xfcrrE6WoAcchwmOqWsnYMfxVwEcM+IAAe1BkEA=",
  "appVersion": "1.0.0",
  "platform": "android",
  "installationTime": "2024-01-15T10:30:00.000Z",
  "deviceModel": "Samsung Galaxy S21",
  "androidVersion": "13",
  "appBuildNumber": "1"
}
```

#### Field Validation

- `deviceId`: Required, 16-100 characters, base64 format
- `appVersion`: Required, string
- `platform`: Required, "android" or "ios"
- `installationTime`: Required, ISO 8601 date string
- `deviceModel`: Required, string
- `androidVersion`: Required, string
- `appBuildNumber`: Required, string

#### Success Response (200)

```json
{
  "success": true,
  "data": {
    "deviceId": "gRt+xfcrrE6WoAcchwmOqWsnYMfxVwEcM+IAAe1BkEA=",
    "trialStartTime": null,
    "trialEndTime": null,
    "trialDuration": null,
    "registrationTime": "2024-01-15T10:30:00.000Z"
  },
  "message": "Device registered successfully",
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

#### Error Responses

- **400**: Missing required fields or invalid device ID format
- **500**: Internal server error

---

### 2. Start Trial

**Function**: `startTrial`

#### Request Data

```json
{
  "deviceId": "gRt+xfcrrE6WoAcchwmOqWsnYMfxVwEcM+IAAe1BkEA="
}
```

#### Field Validation

- `deviceId`: Required, must be registered device

#### Success Response (200)

```json
{
  "success": true,
  "data": {
    "deviceId": "gRt+xfcrrE6WoAcchwmOqWsnYMfxVwEcM+IAAe1BkEA=",
    "trialStartTime": "2024-01-15T10:30:00.000Z",
    "trialEndTime": "2024-01-22T10:30:00.000Z",
    "trialDuration": 7
  },
  "message": "Trial started successfully",
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

#### Error Responses

- **400**: Missing deviceId
- **404**: Device not found
- **409**: Trial already started
- **500**: Internal server error

---

### 3. Get Trial Status

**Function**: `getTrialStatus`

#### Request Data

```json
{
  "deviceId": "gRt+xfcrrE6WoAcchwmOqWsnYMfxVwEcM+IAAe1BkEA="
}
```

#### Field Validation

- `deviceId`: Required, must be registered device

#### Success Response (200) - Active Trial

```json
{
  "success": true,
  "data": {
    "trialStatus": "active",
    "remainingDays": 5,
    "trialStartTime": "2024-01-15T10:30:00.000Z",
    "trialEndTime": "2024-01-22T10:30:00.000Z",
    "totalTrialDays": 7,
    "lastChecked": "2024-01-17T10:30:00.000Z"
  },
  "message": "Trial status retrieved successfully",
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

#### Success Response (200) - Expired Trial

```json
{
  "success": true,
  "data": {
    "trialStatus": "expired",
    "remainingDays": 0,
    "trialStartTime": "2024-01-15T10:30:00.000Z",
    "trialEndTime": "2024-01-22T10:30:00.000Z",
    "totalTrialDays": 7,
    "expiredAt": "2024-01-22T10:30:00.000Z",
    "lastChecked": "2024-01-23T10:30:00.000Z"
  },
  "message": "Trial status retrieved successfully",
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

#### Success Response (200) - No Trial

```json
{
  "success": true,
  "data": {
    "trialStatus": "not_started",
    "remainingDays": 0,
    "trialStartTime": null,
    "trialEndTime": null,
    "totalTrialDays": null,
    "lastChecked": "2024-01-15T10:30:00.000Z"
  },
  "message": "Trial status retrieved successfully",
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

#### Error Responses

- **400**: Missing deviceId
- **404**: Device not found
- **500**: Internal server error

---

### 4. Verify Individual Purchase

**Function**: `verifyIndividualPurchase`

#### Request Data

```json
{
  "deviceId": "gRt+xfcrrE6WoAcchwmOqWsnYMfxVwEcM+IAAe1BkEA=",
  "purchaseToken": "google_play_purchase_token",
  "productId": "com.botforge.nav2missionplanner.individual"
}
```

#### Field Validation

- `deviceId`: Required, must be registered device
- `purchaseToken`: Required, Google Play purchase token
- `productId`: Required, Google Play product ID

#### Success Response (200)

```json
{
  "success": true,
  "data": {
    "deviceId": "gRt+xfcrrE6WoAcchwmOqWsnYMfxVwEcM+IAAe1BkEA=",
    "purchaseType": "individual",
    "verified": true,
    "purchaseDate": "2024-01-15T10:30:00.000Z"
  },
  "message": "Individual purchase verified successfully",
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

#### Error Responses

- **400**: Missing required fields or purchase verification failed
- **500**: Internal server error

---

### 5. Verify Enterprise Purchase

**Function**: `verifyEnterprisePurchase`

#### Request Data

```json
{
  "deviceId": "gRt+xfcrrE6WoAcchwmOqWsnYMfxVwEcM+IAAe1BkEA=",
  "purchaseToken": "google_play_purchase_token",
  "productId": "com.botforge.nav2missionplanner.enterprise",
  "enterpriseCode": "ENTERPRISE_CODE_123"
}
```

#### Field Validation

- `deviceId`: Required, must be registered device
- `purchaseToken`: Required, Google Play purchase token
- `productId`: Required, Google Play product ID
- `enterpriseCode`: Required, valid enterprise code

#### Success Response (200)

```json
{
  "success": true,
  "data": {
    "deviceId": "gRt+xfcrrE6WoAcchwmOqWsnYMfxVwEcM+IAAe1BkEA=",
    "purchaseType": "enterprise",
    "verified": true,
    "enterpriseCode": "ENTERPRISE_CODE_123",
    "brandingData": {
      "logo": "https://example.com/logo.png",
      "companyName": "Example Corp",
      "primaryColor": "#FF5733",
      "secondaryColor": "#33FF57"
    },
    "purchaseDate": "2024-01-15T10:30:00.000Z"
  },
  "message": "Enterprise purchase verified successfully",
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

#### Error Responses

- **400**: Missing required fields or purchase verification failed
- **404**: Enterprise code not found
- **402**: Enterprise code inactive
- **500**: Internal server error

---

### 6. Get License Status

**Function**: `getLicenseStatus`

#### Request Data

```json
{
  "deviceId": "gRt+xfcrrE6WoAcchwmOqWsnYMfxVwEcM+IAAe1BkEA="
}
```

#### Field Validation

- `deviceId`: Required, must be registered device

#### Success Response (200) - Has License

```json
{
  "success": true,
  "data": {
    "hasLicense": true,
    "licenseType": "individual",
    "verified": true,
    "purchaseDate": "2024-01-15T10:30:00.000Z",
    "enterpriseCode": null,
    "brandingData": null
  },
  "message": "License status retrieved successfully",
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

#### Success Response (200) - Active Trial

```json
{
  "success": true,
  "data": {
    "hasLicense": false,
    "licenseType": "trial",
    "trialStatus": "active",
    "trialEndDate": "2024-01-22T10:30:00.000Z"
  },
  "message": "Trial active",
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

#### Success Response (200) - Expired Trial

```json
{
  "success": true,
  "data": {
    "hasLicense": false,
    "licenseType": "trial",
    "trialStatus": "expired",
    "trialEndDate": "2024-01-22T10:30:00.000Z"
  },
  "message": "Trial expired",
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

#### Success Response (200) - No License

```json
{
  "success": true,
  "data": {
    "hasLicense": false,
    "licenseType": null,
    "message": "No license or trial found"
  },
  "message": "No license found",
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

#### Error Responses

- **400**: Missing deviceId
- **500**: Internal server error

---

### 7. Submit Feedback

**Function**: `submitFeedback`

#### Request Data

```json
{
  "name": "John Doe",
  "email": "john@example.com",
  "subject": "Bug Report",
  "message": "App crashes when opening settings",
  "deviceId": "gRt+xfcrrE6WoAcchwmOqWsnYMfxVwEcM+IAAe1BkEA="
}
```

#### Optional Request Data

```json
{
  "userAgent": "Mozilla/5.0 (Android 13; Mobile; rv:109.0) Gecko/118.0",
  "appVersion": "1.0.0"
}
```

#### Field Validation

- `name`: Required, string
- `email`: Required, valid email format
- `subject`: Required, string
- `message`: Required, string
- `deviceId`: Required, must be registered device
- `userAgent`: Optional, string
- `appVersion`: Optional, string

#### Success Response (200)

```json
{
  "success": true,
  "data": {
    "feedbackId": "feedback_document_id",
    "submittedAt": "2024-01-15T10:30:00.000Z"
  },
  "message": "Feedback submitted successfully",
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

#### Error Responses

- **400**: Missing required fields or invalid email format
- **500**: Internal server error

---

### 8. Health Check

**Function**: `healthCheck`

#### Request Data

Optional - any data sent will be returned in response

#### Success Response (200)

```json
{
  "success": true,
  "message": "Nav2 Mission Planner Cloud Functions are running",
  "timestamp": "2024-01-15T10:30:00.000Z",
  "version": "1.0.0",
  "receivedData": {
    "test": "data"
  }
}
```

---

## Data Types and Validation

### Device ID Format

- **Type**: Base64 string (Widevine ID)
- **Length**: 16-100 characters
- **Special Characters**: `+`, `/`, `=` (automatically encoded for Firestore)
- **Example**: `gRt+xfcrrE6WoAcchwmOqWsnYMfxVwEcM+IAAe1BkEA=`

### Email Format

- **Pattern**: `^[^\s@]+@[^\s@]+\.[^\s@]+$`
- **Example**: `user@example.com`

### Date Format

- **Format**: ISO 8601 with timezone information
- **Example**: `2024-01-15T10:30:00.000Z`

### Trial Configuration

- **Duration**: 7 days from start
- **Time Zone**: UTC
- **Status Values**: `not_started`, `active`, `expired`

### License Types

- **Individual**: Single device license
- **Enterprise**: Multi-device license with branding
- **Trial**: Time-limited trial period

---

## Error Handling

### Common Error Messages

- `Missing required field: {fieldName}`
- `Invalid device ID format`
- `Device not found`
- `Trial already started`
- `Enterprise code not found`
- `Enterprise code inactive`
- `Purchase verification failed`
- `Internal server error`

### Validation Rules

1. All required fields must be present and non-empty
2. Device IDs must be valid base64 strings (16-100 characters)
3. Email addresses must be in valid format
4. Dates must be in ISO 8601 format
5. Platform must be "android" or "ios"

---

## Usage Examples

### Flutter/Dart Example

```dart
import 'package:cloud_functions/cloud_functions.dart';

final functions = FirebaseFunctions.instance;

// Register device
Future<void> registerDevice() async {
  try {
    final result = await functions.httpsCallable('registerDevice').call({
      'deviceId': 'gRt+xfcrrE6WoAcchwmOqWsnYMfxVwEcM+IAAe1BkEA=',
      'appVersion': '1.0.0',
      'platform': 'android',
      'installationTime': DateTime.now().toIso8601String(),
      'deviceModel': 'Samsung Galaxy S21',
      'androidVersion': '13',
      'appBuildNumber': '1',
    });

    print('Success: ${result.data}');
  } catch (e) {
    print('Error: $e');
  }
}

// Start trial
Future<void> startTrial() async {
  try {
    final result = await functions.httpsCallable('startTrial').call({
      'deviceId': 'gRt+xfcrrE6WoAcchwmOqWsnYMfxVwEcM+IAAe1BkEA=',
    });

    print('Success: ${result.data}');
  } catch (e) {
    print('Error: $e');
  }
}
```

### JavaScript Example

```javascript
import { getFunctions, httpsCallable } from "firebase/functions";

const functions = getFunctions();

// Register device
const registerDevice = httpsCallable(functions, "registerDevice");
registerDevice({
  deviceId: "gRt+xfcrrE6WoAcchwmOqWsnYMfxVwEcM+IAAe1BkEA=",
  appVersion: "1.0.0",
  platform: "android",
  installationTime: new Date().toISOString(),
  deviceModel: "Samsung Galaxy S21",
  androidVersion: "13",
  appBuildNumber: "1",
})
  .then((result) => {
    console.log("Success:", result.data);
  })
  .catch((error) => {
    console.error("Error:", error);
  });
```

---

## Deployment Notes

### Environment Variables

- `FIREBASE_PROJECT_ID`: Firebase project ID
- `GOOGLE_APPLICATION_CREDENTIALS`: Service account key (auto-configured)

### App Check Configuration

- Currently disabled for testing (`enforceAppCheck: false`)
- Should be enabled in production for security

### Firestore Collections

- `devices`: Device registration and trial data
- `purchases`: Purchase verification data
- `enterprises`: Enterprise codes and branding data
- `feedback`: User feedback submissions

### Security Rules

- Device IDs are automatically encoded for Firestore document IDs
- All functions validate input data
- Error responses don't expose sensitive information

---

## Version History

### v1.0.0 (Current)

- Initial release
- Device registration and trial management
- Purchase verification (individual and enterprise)
- License status checking
- Feedback submission
- Health check endpoint
- App Check temporarily disabled for testing
