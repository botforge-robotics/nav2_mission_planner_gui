# Nav2 Mission Planner - Firebase Cloud Functions

This directory contains the Firebase Cloud Functions implementation for the Nav2 Mission Planner trial and purchase system, migrated from the existing PHP backend.

## 📋 Table of Contents

1. [Overview](#overview)
2. [Migration Summary](#migration-summary)
3. [Project Structure](#project-structure)
4. [API Endpoints](#api-endpoints)
5. [Database Schema](#database-schema)
6. [Setup Instructions](#setup-instructions)
7. [Deployment](#deployment)
8. [Testing](#testing)
9. [Security](#security)
10. [Troubleshooting](#troubleshooting)

## Overview

This Firebase Cloud Functions implementation provides a complete backend solution for the Nav2 Mission Planner app, including:

- **Device Management**: Registration, trial management, and device tracking
- **Trial System**: 7-day trial with Firebase integration
- **Purchase System**: Google Play billing integration for individual and enterprise licenses
- **Enterprise System**: Enterprise codes, branding, and device limits
- **License Verification**: Backward-compatible license verification
- **Feedback System**: User feedback collection and management

## Migration Summary

### Migrated Components

| PHP Component            | Firebase Function | Status      |
| ------------------------ | ----------------- | ----------- |
| `DeviceController`       | `device.js`       | ✅ Complete |
| `DeviceService`          | `device.js`       | ✅ Complete |
| `LicenseController`      | `license.js`      | ✅ Complete |
| `PaymentController`      | `purchase.js`     | ✅ Complete |
| `FeedbackController`     | `feedback.js`     | ✅ Complete |
| `OrganizationController` | `enterprise.js`   | ✅ Complete |

**Note**: Some functions have been removed as requested:

- Authentication-related functions (none existed in original)
- `updateDevice`, `deleteDevice`, `getAllDevices` from device management
- `validateEnterpriseCode` from enterprise management
- `verifyLicense` from license verification

### Key Changes

1. **Authentication**: Replaced Laravel authentication with Firebase Auth
2. **Database**: Migrated from MySQL to Firestore
3. **API**: Converted REST endpoints to Firebase Callable Functions
4. **Payment**: Integrated Google Play billing instead of Razorpay
5. **Security**: Implemented Firestore security rules
6. **Response Format**: Standardized JSON responses

## Project Structure

```
functions/
├── index.js                 # Main entry point
├── package.json            # Dependencies
├── firebase.json           # Firebase configuration
├── firestore.rules         # Security rules
├── firestore.indexes.json  # Database indexes
├── src/
│   ├── utils/
│   │   └── response.js     # Response utilities
│   ├── device.js           # Device management
│   ├── trial.js            # Trial management
│   ├── purchase.js         # Purchase verification
│   ├── enterprise.js       # Enterprise management
│   ├── license.js          # License verification
│   └── feedback.js         # Feedback system
└── README.md              # This file
```

## API Endpoints

### Device Management

| Function         | Method | Description         |
| ---------------- | ------ | ------------------- |
| `registerDevice` | POST   | Register new device |

### Trial Management

| Function         | Method | Description            |
| ---------------- | ------ | ---------------------- |
| `startTrial`     | POST   | Start trial for device |
| `getTrialStatus` | GET    | Get trial status       |

### Purchase Verification

| Function                   | Method | Description                |
| -------------------------- | ------ | -------------------------- |
| `verifyIndividualPurchase` | POST   | Verify individual purchase |
| `verifyEnterprisePurchase` | POST   | Verify enterprise purchase |
| `getPurchaseStatus`        | GET    | Get purchase status        |

### Enterprise Management

| Function                | Method | Description                 |
| ----------------------- | ------ | --------------------------- |
| `getEnterpriseBranding` | GET    | Get enterprise branding     |
| `createEnterprise`      | POST   | Create enterprise (admin)   |
| `updateEnterprise`      | PUT    | Update enterprise (admin)   |
| `getAllEnterprises`     | GET    | Get all enterprises (admin) |

### License Verification

| Function           | Method | Description        |
| ------------------ | ------ | ------------------ |
| `getLicenseStatus` | GET    | Get license status |

### Feedback

| Function          | Method | Description                |
| ----------------- | ------ | -------------------------- |
| `submitFeedback`  | POST   | Submit feedback            |
| `getFeedback`     | GET    | Get feedback (admin)       |
| `getFeedbackById` | GET    | Get feedback by ID (admin) |
| `deleteFeedback`  | DELETE | Delete feedback (admin)    |

## Database Schema

### Collections

#### `devices`

```javascript
{
  deviceId: "widevine_device_id",
  deviceModel: "moto g82 5G",
  platform: "android",
  androidVersion: "13",
  appVersion: "1.2.0",
  appBuildNumber: "4",
  installationTime: "2025-08-06T21:35:06.836409",
  trialStartTime: timestamp | null,
  trialEndTime: timestamp | null,
  trialDuration: 7,
  registrationTime: timestamp,
  createdAt: timestamp,
  updatedAt: timestamp
}
```

#### `purchases`

```javascript
{
  deviceId: "widevine_device_id",
  widevineId: "widevine_device_id",
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

#### `enterprises`

```javascript
{
  code: "ABC123",
  organizationName: "Acme Corporation",
  brandingData: {
    logoUrl: "https://company.com/logo.png",
    themeColor: "#FF5733",
    companyName: "Acme Corp",
    appTitle: "Acme Mission Planner"
  },
  active: boolean,
  maxDevices: 10,
  devices: ["device1", "device2"],
  createdAt: timestamp,
  updatedAt: timestamp
}
```

#### `feedback`

```javascript
{
  name: "John Doe",
  email: "john@example.com",
  subject: "Feature Request",
  message: "Great app!",
  deviceId: "widevine_device_id",
  userAgent: "Mozilla/5.0...",
  appVersion: "1.2.0",
  createdAt: timestamp
}
```

## Setup Instructions

### Prerequisites

1. **Node.js 18+** installed
2. **Firebase CLI** installed: `npm install -g firebase-tools`
3. **Firebase project** created
4. **Google Play Console** account with billing setup

### Installation

1. **Clone the repository**

   ```bash
   cd functions
   ```

2. **Install dependencies**

   ```bash
   npm install
   ```

3. **Initialize Firebase**

   ```bash
   firebase login
   firebase use --add
   ```

4. **Configure environment**
   ```bash
   # Set up Google Play API credentials
   # Configure Firebase project settings
   ```

### Google Play API Setup

1. **Create Google Play API credentials**

   ```bash
   # Download service account key from Google Cloud Console
   # Enable Google Play Android Developer API
   ```

2. **Configure environment variables**
   ```bash
   # Set GOOGLE_APPLICATION_CREDENTIALS
   export GOOGLE_APPLICATION_CREDENTIALS="path/to/service-account-key.json"
   ```

## Deployment

### Development

1. **Start emulators**

   ```bash
   firebase emulators:start
   ```

2. **Test functions locally**
   ```bash
   # Functions will be available at http://localhost:5001
   ```

### Production

1. **Deploy functions**

   ```bash
   firebase deploy --only functions
   ```

2. **Deploy Firestore rules**

   ```bash
   firebase deploy --only firestore:rules
   ```

3. **Deploy Firestore indexes**
   ```bash
   firebase deploy --only firestore:indexes
   ```

## Testing

### Unit Tests

```bash
npm test
```

### Integration Tests

```bash
# Test with Firebase emulators
firebase emulators:exec "npm test"
```

### Manual Testing

1. **Test device registration**

   ```javascript
   const functions = firebase.functions();
   const registerDevice = functions.httpsCallable("registerDevice");

   registerDevice({
     deviceId: "test_device_id",
     appVersion: "1.0.0",
     platform: "android",
     deviceModel: "Test Device",
     androidVersion: "13",
     appBuildNumber: "1",
     installationTime: new Date().toISOString(),
   });
   ```

2. **Test trial start**

   ```javascript
   const startTrial = functions.httpsCallable("startTrial");

   startTrial({
     deviceId: "test_device_id",
   });
   ```

## Security

### Authentication

- **Anonymous Auth**: Used for device identification
- **Custom Claims**: For admin access control
- **Device Binding**: Widevine ID for device-specific access

### Firestore Rules

- **Device-specific access**: Users can only access their own device data
- **Admin-only access**: Certain functions require admin privileges
- **Enterprise protection**: Enterprise data protected by Cloud Functions

### Data Validation

- **Input sanitization**: All inputs are sanitized
- **Field validation**: Required fields are validated
- **Type checking**: Data types are verified

## Troubleshooting

### Common Issues

1. **Function deployment fails**

   ```bash
   # Check Node.js version
   node --version

   # Clear cache
   firebase functions:delete --force
   firebase deploy --only functions
   ```

2. **Firestore rules deployment fails**

   ```bash
   # Validate rules
   firebase firestore:rules:validate firestore.rules
   ```

3. **Google Play API errors**

   ```bash
   # Check credentials
   gcloud auth application-default login

   # Verify API access
   gcloud services enable androidpublisher.googleapis.com
   ```

### Logs

```bash
# View function logs
firebase functions:log

# View specific function logs
firebase functions:log --only registerDevice
```

### Performance

- **Cold starts**: Functions may take 1-2 seconds on first invocation
- **Warm starts**: Subsequent calls are much faster
- **Memory usage**: Functions use minimal memory
- **Timeout**: Functions timeout after 60 seconds

## Migration Checklist

### ✅ Completed

- [x] Device registration and management
- [x] Trial system with Firebase integration
- [x] Purchase verification with Google Play
- [x] Enterprise code validation
- [x] License verification (backward compatible)
- [x] Feedback system
- [x] Security rules and indexes
- [x] Response standardization
- [x] Error handling
- [x] Documentation

### 🔄 In Progress

- [ ] Google Play API integration testing
- [ ] Performance optimization
- [ ] Monitoring and analytics
- [ ] Backup and recovery procedures

### 📋 Pending

- [ ] Admin dashboard functions
- [ ] Analytics functions
- [ ] Notification functions
- [ ] Advanced security features

## Support

For issues and questions:

1. **Check logs**: `firebase functions:log`
2. **Review documentation**: This README
3. **Test locally**: Use Firebase emulators
4. **Contact team**: For critical issues

---

**Version**: 1.0.0
**Last Updated**: 2025-01-06
**Compatibility**: Firebase Functions v4.5.0+
