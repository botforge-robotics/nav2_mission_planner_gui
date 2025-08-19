# Google Play RTDN (Real-Time Developer Notifications) Setup

This guide explains how to set up Google Play RTDN to automatically receive payment status updates in your Firebase Cloud Functions.

## 🚨 **CRITICAL: Google Play Console Configuration Required**

**Your RTDN handler will NOT work until you configure Google Play Console to send notifications to your Pub/Sub topic!**

## 📋 **Prerequisites**

1. **Google Cloud Project** with Firebase Functions enabled
2. **Google Play Console** access for your app
3. **Service Account** with Google Play Developer API access
4. **Pub/Sub Topic** created in Google Cloud

## 🔧 **Step-by-Step Setup**

### **Step 1: Create Pub/Sub Topic in Google Cloud**

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Navigate to **Pub/Sub** > **Topics**
3. Click **Create Topic**
4. **Topic ID**: `play-rtdn-topic`
5. Click **Create**

### **Step 2: Configure Google Play Console RTDN**

1. Go to [Google Play Console](https://play.google.com/console/)
2. Select your app: **Nav2 Mission Planner**
3. Navigate to **Setup** > **Advanced setup** > **Real-time developer notifications**
4. Click **Set up notifications**
5. **Select notification type**: Choose **In-app purchases** and **Subscriptions**
6. **Cloud Pub/Sub topic**: Enter your topic name
   - Format: `projects/YOUR_PROJECT_ID/topics/play-rtdn-topic`
   - Replace `YOUR_PROJECT_ID` with your actual Google Cloud project ID
7. Click **Save**

### **Step 3: Verify RTDN Configuration**

1. In Google Play Console, go to **Setup** > **Advanced setup** > **Real-time developer notifications**
2. You should see:
   - ✅ **Status**: Active
   - ✅ **Topic**: `projects/YOUR_PROJECT_ID/topics/play-rtdn-topic`
   - ✅ **Notification types**: In-app purchases, Subscriptions

### **Step 4: Deploy Cloud Functions**

```bash
cd functions
npm run deploy
```

## 📡 **How RTDN Works**

### **Message Flow:**

```
Google Play → Pub/Sub Topic → Cloud Function → Firebase Database
```

### **RTDN Event Types Handled:**

| Event Type               | Description                     | Action Taken        |
| ------------------------ | ------------------------------- | ------------------- |
| `PURCHASE_STATE_CHANGED` | Purchase completed successfully | ✅ Activate license |
| `PURCHASE_CANCELED`      | Purchase was cancelled          | ❌ Revert to trial  |
| `PURCHASE_REFUNDED`      | Purchase was refunded           | ❌ Revoke license   |
| `PURCHASE_CHARGEBACK`    | Chargeback occurred             | ❌ Revoke license   |
| `PURCHASE_FAILED`        | Purchase failed                 | ❌ Revert to trial  |
| `PURCHASE_PENDING`       | Purchase is pending             | ⏳ Keep as pending  |

## 🔍 **Testing RTDN**

### **Test 1: Check Function Deployment**

```bash
cd functions
npm run logs
```

Look for:

- ✅ Function deployed successfully
- ✅ Listening to `play-rtdn-topic`

### **Test 2: Make a Test Purchase**

1. Use test account in your app
2. Make a test purchase
3. Check Firebase Functions logs for RTDN messages

### **Test 3: Verify Database Updates**

Check Firestore collections:

- `payments` - Payment status should update automatically
- `audit` - RTDN processing should be logged
- `accounts` - License status should change based on payment

## 🚨 **Common Issues & Solutions**

### **Issue 1: RTDN Not Received**

**Symptoms:**

- Payment status stays "pending" in Firebase
- No RTDN logs in Cloud Functions

**Solutions:**

1. ✅ Verify Google Play Console RTDN is configured
2. ✅ Check Pub/Sub topic exists: `play-rtdn-topic`
3. ✅ Ensure function is deployed and listening
4. ✅ Check service account has Google Play API access

### **Issue 2: Function Can't Find Payment Record**

**Symptoms:**

- RTDN received but payment not found
- PurchaseToken mismatch

**Solutions:**

1. ✅ Ensure `purchaseToken` is stored in payment record
2. ✅ Check payment collection name: `payments`
3. ✅ Verify payment document structure

### **Issue 3: License Not Activating**

**Symptoms:**

- Payment shows "paid" but license inactive
- RTDN processed but account not updated

**Solutions:**

1. ✅ Check `updatePaymentAndAccountStatus` function
2. ✅ Verify account and device collections exist
3. ✅ Check function permissions and authentication

## 📊 **Monitoring & Debugging**

### **Cloud Functions Logs**

```bash
cd functions
npm run logs --only handlePlayRtdn
```

### **Firebase Console**

1. Go to **Functions** > **Logs**
2. Filter by function: `handlePlayRtdn`
3. Look for RTDN processing messages

### **Audit Trail**

Check `audit` collection in Firestore for:

- `rtdn_processed` - Successful RTDN processing
- `rtdn_error` - RTDN processing errors
- `rtdn_no_payment_found` - Missing payment records

## 🎯 **Benefits of RTDN Over Polling**

| Aspect                 | RTDN                    | Polling              |
| ---------------------- | ----------------------- | -------------------- |
| **Speed**              | ⚡ Instant (seconds)    | 🐌 Delayed (minutes) |
| **Reliability**        | ✅ Guaranteed delivery  | ❌ May miss updates  |
| **Cost**               | 💰 Pay per notification | 💸 Pay per API call  |
| **Real-time**          | ✅ Yes                  | ❌ No                |
| **Google Recommended** | ✅ Yes                  | ❌ No                |

## 🔐 **Security Considerations**

1. **App Check**: Enabled in production
2. **Authentication**: Required for all functions
3. **Service Account**: Limited to Google Play API access
4. **Audit Logging**: All actions logged for compliance

## 📚 **Additional Resources**

- [Google Play RTDN Documentation](https://developer.android.com/google/play/billing/lifecycle)
- [Pub/Sub Setup Guide](https://cloud.google.com/pubsub/docs/quickstart-console)
- [Google Play Developer API](https://developers.google.com/android-publisher/api-ref)

---

**⚠️ IMPORTANT**: RTDN will NOT work until you complete Step 2 (Google Play Console configuration). This is the most common cause of RTDN failures!
