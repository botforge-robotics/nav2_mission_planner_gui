const { onCall } = require("firebase-functions/v2/https");
const { onMessagePublished } = require("firebase-functions/v2/pubsub");
const admin = require("firebase-admin");
const config = require("./config");
const { ensureAuthenticated, ensureAccountMatches } = require("./auth");
const {
  createSuccessResponse,
  createErrorResponse,
  validateRequiredFields
} = require("./utils/response");

const db = admin.firestore();

// Google Play API client (will be initialized when needed)
let googlePlayClient = null;

function getGooglePlayClient() {
  if (!googlePlayClient) {
    // Initialize Google Play Developer API client
    // This requires proper service account setup with Google Play API access
    const { google } = require("googleapis");
    const auth = new google.auth.GoogleAuth({
      scopes: ["https://www.googleapis.com/auth/androidpublisher"],
      keyFile: process.env.GOOGLE_APPLICATION_CREDENTIALS || "./service-account-play-nav2.json"
    });

    googlePlayClient = google.androidpublisher({
      version: "v3",
      auth: auth
    });
  }
  return googlePlayClient;
}




/**
 * Check payment status with Google Play Console (for manual refresh)
 * This replaces RTDN and allows manual verification of payment status
 */
exports.checkPaymentStatus = onCall(
  { enforceAppCheck: config.enableAppCheck },
  async (request) => {
    try {
      console.log("�� checkPaymentStatus called with data:", JSON.stringify(request.data, null, 2));

      const data = request.data || {};
      const authErr = await ensureAuthenticated(request);
      if (authErr) return authErr;

      const validationError = validateRequiredFields(data, ["accountId"]);
      if (validationError) return validationError;

      const { accountId } = data;
      const mismatch = ensureAccountMatches(request, accountId);
      if (mismatch) return mismatch;

      console.log(`🔍 Checking payment status for account: ${accountId}`);

      // Find the most recent pending payment for this user
      const recentPaymentQuery = await db.collection(config.collections.payments)
        .where("accountId", "==", accountId)
        .orderBy("createdAt", "desc")
        .limit(1)
        .get();

      if (recentPaymentQuery.empty) {
        console.log("✅ No payments found - show regular buy screen");
        return createSuccessResponse({
          paymentStatus: "no_payments",
          latestPayment: null,
          message: "No payments found - show regular buy screen"
        }, "No payments found");
      }

      const paymentDoc = recentPaymentQuery.docs[0];
      const payment = paymentDoc.data();

      console.log(`📊 Found latest payment: ${payment.paymentId}, current status: ${payment.status}`);

      // If payment is already completed/failed, return current status
      if (payment.status !== "pending") {
        console.log(`📊 Latest payment status: ${payment.status} - not pending`);

        if (payment.status === "cancelled") {
          return createSuccessResponse({
            paymentStatus: "cancelled",
            latestPayment: {
              paymentId: payment.paymentId,
              status: payment.status,
              productId: payment.productId,
              createdAt: payment.createdAt,
              purchaseToken: payment.verificationData?.serverVerificationData || null,
              orderId: payment.orderId,
              amount: null, // Not stored in current payment structure
              currency: null, // Not stored in current payment structure
              licenseType: null, // Not stored in current payment structure
              message: "Last payment was cancelled - show trial screen with info"
            },
            message: "Last payment was cancelled - show trial screen with info"
          }, "Last payment was cancelled");
        } else if (payment.status === "paid") {
          return createSuccessResponse({
            paymentStatus: "paid",
            latestPayment: {
              paymentId: payment.paymentId,
              status: payment.status,
              productId: payment.productId,
              createdAt: payment.createdAt,
              purchaseToken: payment.verificationData?.serverVerificationData || null,
              orderId: payment.orderId,
              amount: null, // Not stored in current payment structure
              currency: null, // Not stored in current payment structure
              licenseType: null, // Not stored in current payment structure
              message: "Payment was successful - license should be active"
            },
            message: "Payment was successful - license should be active"
          }, "Payment was successful");
        } else {
          // failed, refunded, etc.
          return createSuccessResponse({
            paymentStatus: payment.status,
            latestPayment: {
              paymentId: payment.paymentId,
              status: payment.status,
              productId: payment.productId,
              createdAt: payment.createdAt,
              purchaseToken: payment.verificationData?.serverVerificationData || null,
              orderId: payment.orderId,
              amount: null, // Not stored in current payment structure
              currency: null, // Not stored in current payment structure
              licenseType: null, // Not stored in current payment structure
              message: `Last payment ${payment.status} - show appropriate screen`
            },
            message: `Last payment ${payment.status}`
          }, `Last payment ${payment.status}`);
        }
      }

      // Check if we have a purchase token to verify
      if (!payment.verificationData?.serverVerificationData) {
        console.log("⚠️ Payment has no purchase token - payment may still be pending");
        return createSuccessResponse({
          paymentStatus: "pending",
          latestPayment: {
            paymentId: payment.paymentId,
            status: "pending",
            productId: payment.productId,
            createdAt: payment.createdAt,
            purchaseToken: payment.verificationData?.serverVerificationData || null,
            orderId: payment.orderId,
            amount: null, // Not stored in current payment structure
            currency: null, // Not stored in current payment structure
            licenseType: null, // Not stored in current payment structure
            message: "Payment pending in Google Play - no verification token yet"
          },
          message: "Payment is pending - show pending screen"
        }, "Payment is pending");
      }

      // Verify with Google Play Console using serverVerificationData
      console.log("🔄 Verifying payment with Google Play Console...");
      console.log("🔍 Using serverVerificationData:", payment.verificationData.serverVerificationData);
      const verificationResult = await verifyWithGooglePlay(
        payment.verificationData.serverVerificationData,
        payment.productId
      );
      console.log("✅ Google Play verification result:", verificationResult);

      // Update payment status based on verification result
      let newStatus = "error";
      let shouldActivateLicense = false;

      if (verificationResult.status === "paid") { // PURCHASED
        newStatus = "paid";
        shouldActivateLicense = true;
      } else if (verificationResult.status === "pending") { // PENDING
        newStatus = "pending";
      } else if (verificationResult.status === "cancelled") { // CANCELLED
        newStatus = "cancelled";
      } else {
        newStatus = "failed";
      }

      console.log(`🔄 Updating payment status: ${payment.status} → ${newStatus}`);

      // Update payment status
      await paymentDoc.ref.update({
        status: newStatus,
        updatedAt: new Date(),
        verificationLog: admin.firestore.FieldValue.arrayUnion({
          ts: new Date(),
          status: newStatus,
          notes: "Manual verification with Google Play Console",
          source: "manual_refresh"
        })
      });

      // Handle license activation if payment completed
      if (shouldActivateLicense && newStatus === "paid") {
        console.log("✅ Activating license for paid purchase");
        await updatePaymentAndAccountStatus(
          payment.accountId,
          payment.deviceId,
          payment.paymentId,
          "paid"
        );
      } else if (newStatus === "cancelled" || newStatus === "failed") {
        console.log("🔄 Reverting license status for:", newStatus);
        // For cancelled/failed payments, update account status directly without transaction
        await updateAccountStatusForPaymentFailure(payment.accountId, newStatus);
      }

      // Log audit entry
      await db.collection(config.collections.audit).add({
        action: "payment_status_checked",
        actor: "user",
        accountId: accountId,
        deviceId: payment.deviceId,
        paymentId: payment.paymentId,
        details: {
          oldStatus: payment.status,
          newStatus,
          reason: "Manual payment status check",
          source: "manual_refresh"
        },
        timestamp: new Date()
      });

      console.log(`✅ Payment status updated: ${newStatus}`);

      // Return the updated status in the expected format
      if (newStatus === "pending") {
        return createSuccessResponse({
          paymentStatus: "pending",
          latestPayment: {
            paymentId: payment.paymentId,
            status: newStatus,
            productId: payment.productId,
            createdAt: payment.createdAt,
            purchaseToken: payment.verificationData?.serverVerificationData || null,
            orderId: payment.orderId,
            amount: null, // Not stored in current payment structure
            currency: null, // Not stored in current payment structure
            licenseType: null, // Not stored in current payment structure
            message: "Payment is still pending - show pending screen"
          },
          message: "Payment is pending - show pending screen"
        }, "Payment is still pending");
      } else {
        // Payment is no longer pending, return the final status
        return createSuccessResponse({
          paymentStatus: newStatus,
          latestPayment: {
            paymentId: payment.paymentId,
            status: newStatus,
            productId: payment.productId,
            createdAt: payment.createdAt,
            purchaseToken: payment.verificationData?.serverVerificationData || null,
            orderId: payment.orderId,
            amount: null, // Not stored in current payment structure
            currency: null, // Not stored in current payment structure
            licenseType: null, // Not stored in current payment structure
            message: `Payment status: ${newStatus}`
          },
          message: `Payment status: ${newStatus}`
        }, `Payment status: ${newStatus}`);
      }

    } catch (error) {
      console.error("checkPaymentStatus error:", error);
      return createErrorResponse(500, "Internal server error");
    }
  });



// REMOVE THE ENTIRE handlePlayRtdn FUNCTION (lines 276-400 approximately)

/**
 * Verify purchase with Google Play API
 */
async function verifyWithGooglePlay(purchaseToken, productId) {
  try {
    const client = getGooglePlayClient();

    // Get purchase details from Google Play
    const response = await client.purchases.products.get({
      packageName: config.packageName,
      productId: productId,
      token: purchaseToken
    });

    const purchase = response.data;
    console.log("🔍 Google Play API response:", purchase);

    // Determine status based on Google Play purchase state
    switch (purchase.purchaseState) {
    case 0: // Purchased
      return { status: "paid", details: purchase };
    case 1: // Canceled
      return { status: "cancelled", details: purchase };
    case 2: // Pending
      return { status: "pending", details: purchase };
    default:
      console.log(`⚠️ Unknown purchase state: ${purchase.purchaseState}`);
      return { status: "failed", details: purchase };
    }

  } catch (error) {
    console.error("Google Play API error:", error);
    throw new Error("Failed to verify purchase with Google Play");
  }
}

/**
 * Update account status for payment failures without using transactions
 * This avoids the "reads before writes" transaction error
 */
async function updateAccountStatusForPaymentFailure(accountId, status) {
  try {
    const now = new Date();
    const accountRef = db.collection(config.collections.accounts).doc(accountId);

    console.log(`🔄 Updating account ${accountId} status to: ${status}`);

    await accountRef.set({
      accountId,
      licenseStatus: "trial_expired", // Revert to trial expired state
      lastVerified: now,
      updatedAt: now
    }, { merge: true });

    console.log(`✅ Account ${accountId} status updated to ${status}`);
  } catch (error) {
    console.error("❌ Error updating account status for payment failure:", error);
    throw error;
  }
}

/**
 * Update payment and account status after verification
 * Handles all possible payment status transitions
 */
async function updatePaymentAndAccountStatus(accountId, deviceId, paymentId, status) {
  const now = new Date();
  console.log(`🔄 Updating payment ${paymentId} status to: ${status}`);

  await db.runTransaction(async (tx) => {
    const paymentRef = db.collection(config.collections.payments).doc(paymentId);
    const accountRef = db.collection(config.collections.accounts).doc(accountId);
    const deviceRef = db.collection(config.collections.devices).doc(deviceId);

    // PERFORM ALL READS FIRST (before any writes)
    let paymentData = null;
    let accountData = null;

    if (status === "paid" || status === "cancelled") {
      // Get the payment document to access productId (for paid) or check current status (for cancelled)
      const paymentDoc = await tx.get(paymentRef);
      paymentData = paymentDoc.data();

      // Get current account status for cancellation checks
      const accountSnap = await tx.get(accountRef);
      accountData = accountSnap.exists ? accountSnap.data() : null;
    }

    // NOW PERFORM ALL WRITES
    // Update payment status and add verification log
    tx.update(paymentRef, {
      status: status,
      updatedAt: now,
      verificationLog: admin.firestore.FieldValue.arrayUnion({
        ts: now,
        status: status,
        notes: "Status updated via automatic processing"
      })
    });

    // Handle different payment statuses
    if (status === "paid") {
      // Payment successful - activate license
      console.log(`🔑 Activating license for account ${accountId}`);

      const productId = paymentData?.productId;

      // Map product to license type (fallback to premium if mapping not found)
      let licenseType = "premium"; // Default fallback
      if (productId && config.productMap && config.productMap[productId]) {
        licenseType = config.productMap[productId].licenseType || "premium";
      }

      console.log(`🔑 Product ID: ${productId}, License Type: ${licenseType}`);
      // Update account with active license
      tx.set(accountRef, {
        accountId,
        licenseStatus: "active",
        licenseType: licenseType, // Set license type based on product
        linkedDeviceId: deviceId,
        lastVerified: now,
        offlineAllowedUntil: new Date(now.getTime() + 24 * 60 * 60 * 1000), // 1 day offline access
        lastPaymentId: paymentId,
        licenseStart: now,
        licenseEnd: new Date(now.getTime() + 365 * 24 * 60 * 60 * 1000), // 1 year license
        updatedAt: now
      }, { merge: true });

      // Update device with active license
      tx.set(deviceRef, {
        deviceId,
        accountId,
        lastLinked: now,
        licenseActive: true,
        updatedAt: now
      }, { merge: true });

      console.log(`✅ License activated for account ${accountId}`);

    } else if (status === "cancelled") {
      // Payment cancelled - check if license was active before revoking
      const currentLicenseStatus = accountData?.licenseStatus;

      if (currentLicenseStatus === "active" || currentLicenseStatus === "licensed") {
        // License was active - revoke it
        console.log(`❌ Payment cancelled for account ${accountId} - revoking active license`);

        tx.update(accountRef, {
          licenseStatus: "license_revoked",
          licenseRevoked: true,
          revocationReason: "payment_cancelled",
          revocationDate: now,
          lastVerified: now,
          updatedAt: now
        });

        // Revoke device license
        tx.update(deviceRef, {
          licenseActive: false,
          licenseRevoked: true,
          updatedAt: now
        });

        console.log(`🚫 License revoked for account ${accountId} due to payment cancellation`);
      } else {
        // License wasn't active - no need to revoke
        console.log(`ℹ️ Payment cancelled for account ${accountId} -
          license not active (${currentLicenseStatus}), skipping revocation`);

        // Just update the account to reflect cancelled payment
        tx.set(accountRef, {
          accountId,
          licenseStatus: "trial_expired", // Revert to trial expired state
          lastVerified: now,
          updatedAt: now
        }, { merge: true });
      }

    } else if (status === "failed") {
      // Payment failed - no license activation
      console.log(`❌ Payment failed for account ${accountId} - no license activation`);

      // Update account to reflect failed payment
      tx.set(accountRef, {
        accountId,
        licenseStatus: "trial_expired", // Revert to trial expired state
        lastVerified: now,
        updatedAt: now
      }, { merge: true });

    } else if (status === "refunded" || status === "chargeback") {
      // Payment refunded/chargeback - check if license was active before revoking
      const currentLicenseStatus = accountData?.licenseStatus;

      if (currentLicenseStatus === "active" || currentLicenseStatus === "licensed") {
        // License was active - revoke it
        console.log(`🚫 Payment ${status} for account ${accountId} - revoking active license`);

        tx.update(accountRef, {
          licenseStatus: "license_revoked",
          licenseRevoked: true,
          revocationReason: status,
          revocationDate: now,
          lastVerified: now,
          updatedAt: now
        });

        // Revoke device license
        tx.update(deviceRef, {
          licenseActive: false,
          licenseRevoked: true,
          updatedAt: now
        });

        console.log(`🚫 License revoked for account ${accountId} due to ${status}`);
      } else {
        // License wasn't active - no need to revoke
        console.log(`ℹ️ Payment ${status} for account ${accountId} -
          license not active (${currentLicenseStatus}), skipping revocation`);

        // Just update the account to reflect refunded payment
        tx.set(accountRef, {
          accountId,
          licenseStatus: "trial_expired", // Revert to trial expired state
          lastVerified: now,
          updatedAt: now
        }, { merge: true });
      }

    } else {
      // Other statuses (error, etc.) - no license activation
      console.log(`⚠️ Payment status ${status} for account ${accountId} - no license activation`);

      // Update account to reflect unknown status
      tx.set(accountRef, {
        accountId,
        licenseStatus: "trial_expired", // Revert to trial expired state
        lastVerified: now,
        updatedAt: now
      }, { merge: true });
    }
  });

  console.log(`✅ Payment ${paymentId} status updated to ${status} and database records updated`);
}

// REMOVED: Unused revokeLicense function - license revocation is handled in updatePaymentAndAccountStatus



/**
 * Handle Real-time Developer Notifications (RTDN) via Pub/Sub
 * Processes one-time product notifications and updates payment/account status
 */
exports.handlePlayRtdn = onMessagePublished({ topic: config.rtdn.topic }, async (event) => {
  try {
    const dataBuffer = Buffer.from(event.data.message.data || "", "base64");
    const json = JSON.parse(dataBuffer.toString() || "{}");
    console.log("📩 RTDN message received:", JSON.stringify(json));

    // Log the RTDN notification to audit collection for debugging
    await db.collection(config.collections.audit).add({
      action: "rtdn_received",
      timestamp: new Date(),
      rawData: json,
      messageId: event.data.message.messageId || "unknown",
      publishTime: event.data.message.publishTime || "unknown"
    });

    console.log("📝 RTDN notification logged to audit collection");

    // Handle different types of RTDN notifications
    if (json?.oneTimeProductNotification) {
      await handleOneTimeProductNotification(json.oneTimeProductNotification);
    } else if (json?.voidedPurchaseNotification) {
      await handleVoidedPurchaseNotification(json.voidedPurchaseNotification);
    } else if (json?.testNotification) {
      await handleTestNotification(json.testNotification);
    } else {
      console.log("⚠️ RTDN message contains unknown notification type");
      console.log("Available fields:", Object.keys(json));
      return;
    }
  } catch (error) {
    console.error("❌ Error handling RTDN:", error);
  }
});

/**
 * Acknowledges a purchase in Google Play to mark it as complete
 * This prevents "itemAlreadyOwned" errors
 */
async function acknowledgePurchaseInGooglePlay(purchaseToken, productId) {
  try {
    if (!purchaseToken || !productId) {
      console.log("⚠️ Missing purchaseToken or productId for acknowledgment");
      return;
    }

    const client = getGooglePlayClient();

    console.log(`🔄 Acknowledging purchase in Google Play: ${productId}`);

    // Acknowledge the purchase
    await client.purchases.products.acknowledge({
      packageName: config.packageName,
      productId: productId,
      token: purchaseToken
    });

    console.log(`✅ Purchase acknowledged successfully in Google Play: ${productId}`);
  } catch (error) {
    console.error("❌ Error acknowledging purchase in Google Play:", error);
    throw error;
  }
}

// Handle OneTimeProductNotification (purchases, cancellations, refunds, deferrals)
async function handleOneTimeProductNotification(oneTime) {
  const purchaseToken = oneTime?.purchaseToken;
  const productId = oneTime?.sku;
  const notificationType = oneTime?.notificationType;

  if (!purchaseToken || !productId) {
    console.log("⚠️ Missing purchaseToken or productId in OneTimeProductNotification");
    return;
  }

  console.log(`🔍 RTDN processing token=${purchaseToken}, sku=${productId}, type=${notificationType}`);

  console.log(`📊 RTDN notification type: ${notificationType}`);

  // Map RTDN notification type to status (RTDN is more reliable than delayed API calls)
  let status;
  switch (notificationType) {
  case 1: // PURCHASED
    status = "paid";
    break;
  case 2: // CANCELED
    status = "cancelled";
    break;
  case 3: // REFUNDED
    status = "refunded";
    break;
  case 4: // DEFERRED (pending)
    status = "pending";
    break;
  default:
    status = "unknown";
    console.log(`⚠️ Unknown RTDN notification type: ${notificationType}`);
  }

  console.log(`📊 RTDN status mapping: ${notificationType} → ${status}`);

  // Note: We trust RTDN notification type over Google Play API verification
  // because RTDN is real-time and shows actual status changes

  const now = new Date();

  // Get orderId from Google Play API for better tracking
  let orderId = null;
  try {
    console.log("🔍 Fetching orderId from Google Play API...");
    const verification = await verifyWithGooglePlay(purchaseToken, productId);
    orderId = verification.details?.orderId || null;
    console.log(`📊 Google Play API orderId: ${orderId}`);
  } catch (error) {
    console.log("⚠️ Could not fetch orderId from Google Play API:", error.message);
  }

  // Try to find payment by purchaseToken first
  let payQuery = await db.collection(config.collections.payments)
    .where("purchaseToken", "==", purchaseToken)
    .limit(1)
    .get();

  // If not found by purchaseToken, try to find by verificationData.serverVerificationData
  if (payQuery.empty) {
    console.log("🔍 No payment found by purchaseToken, searching by serverVerificationData...");

    // Search for payments where serverVerificationData matches the purchaseToken
    const verificationQuery = await db.collection(config.collections.payments)
      .where("verificationData.serverVerificationData", "==", purchaseToken)
      .limit(1)
      .get();

    if (!verificationQuery.empty) {
      console.log("✅ Found payment by serverVerificationData, updating it...");
      payQuery = verificationQuery;
    } else {
      // Also try to find by orderId if it's a Google Play order
      if (purchaseToken && purchaseToken.startsWith("GPA.")) {
        console.log("🔍 No payment found by serverVerificationData, searching by orderId...");

        const orderIdQuery = await db.collection(config.collections.payments)
          .where("orderId", "==", purchaseToken)
          .limit(1)
          .get();

        if (!orderIdQuery.empty) {
          console.log("✅ Found payment by orderId, updating it...");
          payQuery = orderIdQuery;
        } else {
          console.log("⚠️ No payment found by orderId either");
        }
      }
    }
  }

  // If we still haven't found a payment, try to create/update one
  if (payQuery.empty) {
    console.log("⚠️ No payment record found by purchaseToken. Creating payment document from RTDN.");

    // Try to find a pending payment by productId and status to link it
    const pendingPaymentQuery = await db.collection(config.collections.payments)
      .where("productId", "==", productId)
      .where("status", "==", "pending")
      .limit(1)
      .get();

    if (!pendingPaymentQuery.empty) {
      // Found a pending payment - update it with RTDN info
      const pendingDoc = pendingPaymentQuery.docs[0];
      const pendingData = pendingDoc.data();

      console.log(`🔗 Linking RTDN to existing pending payment: ${pendingDoc.id}`);

      const newStatus = mapRtdnStatusToInternal(status);

      // Check if we should update the status (prevent downgrading successful payments)
      if (shouldUpdatePaymentStatus(pendingData.status, newStatus)) {
        await pendingDoc.ref.update({
          status: newStatus,
          orderId: orderId || pendingData.orderId, // Store orderId from RTDN or keep existing
          rtdnReceived: true,
          rtdnTimestamp: now,
          updatedAt: now,
          verificationLog: admin.firestore.FieldValue.arrayUnion({
            ts: now,
            status: newStatus,
            notes: `Payment status updated from RTDN: ${status}`,
            source: "rtdn"
          })
        });
      } else {
        console.log(`⚠️ Skipping status update for payment ${pendingDoc.id}: ${pendingData.status} → ${newStatus}`);
      }

      // Update account status if we have account info
      if (pendingData.accountId && pendingData.deviceId) {
        await updatePaymentAndAccountStatus(
          pendingData.accountId,
          pendingData.deviceId,
          pendingDoc.id,
          mapRtdnStatusToInternal(status)
        );
      }

      console.log(`✅ RTDN linked to existing payment: ${pendingDoc.id}`);
      return;
    }

    // No pending payment found - don't create orphaned payment documents
    // This prevents duplicate documents for successful payments
    console.log("⚠️ No pending payment found for RTDN. Not creating orphaned document to prevent duplicates.");
    console.log(`📊 RTDN status: ${status}, purchaseToken: ${purchaseToken}, productId: ${productId}`);

    // Log the RTDN processing without creating a document
    await db.collection(config.collections.audit).add({
      action: "rtdn_orphaned_skipped",
      details: {
        purchaseToken,
        productId,
        notificationType,
        status,
        reason: "No pending payment found - preventing duplicate documents"
      },
      timestamp: new Date(),
    });

    // Log the RTDN processing
    await db.collection(config.collections.audit).add({
      action: "rtdn_payment_created",
      details: {
        purchaseToken,
        productId,
        notificationType,
        status
      },
      timestamp: new Date(),
    });

    return; // Exit since we can't update account/device without that info
  }

  // If we found an existing payment, update it
  if (!payQuery.empty) {
    const paymentDoc = payQuery.docs[0];
    const payment = paymentDoc.data();

    console.log(`🔄 Updating existing payment ${paymentDoc.id} with RTDN status: ${status}`);

    const newStatus = mapRtdnStatusToInternal(status);

    // Check if we should update the status (prevent downgrading successful payments)
    if (shouldUpdatePaymentStatus(payment.status, newStatus)) {
      await paymentDoc.ref.update({
        status: newStatus,
        orderId: orderId || payment.orderId, // Store orderId from RTDN or keep existing
        rtdnReceived: true,
        rtdnTimestamp: now,
        updatedAt: now,
        verificationLog: admin.firestore.FieldValue.arrayUnion({
          ts: now,
          status: newStatus,
          notes: `Payment status updated from RTDN: ${status}`,
          source: "rtdn"
        })
      });
    } else {
      console.log(`⚠️ Skipping status update for payment ${paymentDoc.id}: ${payment.status} → ${newStatus}`);
    }

    // Update account status if we have account info
    if (payment.accountId && payment.deviceId) {
      await updatePaymentAndAccountStatus(
        payment.accountId,
        payment.deviceId,
        paymentDoc.id,
        mapRtdnStatusToInternal(status)
      );
    }

    // MARK PURCHASE AS COMPLETE IN GOOGLE PLAY when status is paid or cancelled
    if (newStatus === "paid" || newStatus === "cancelled") {
      try {
        console.log(`🔄 Marking purchase as complete in Google Play for status: ${newStatus}`);

        // Call Google Play API to acknowledge/complete the purchase
        await acknowledgePurchaseInGooglePlay(payment.verificationData?.serverVerificationData, payment.productId);

        console.log("✅ Purchase marked as complete in Google Play");
      } catch (error) {
        console.error("❌ Failed to mark purchase as complete in Google Play:", error);
        // Don't fail the entire RTDN processing if this fails
      }
    }

    console.log(`✅ RTDN processing complete for payment: ${paymentDoc.id}`);
  }
}

// Helper function to map RTDN status to internal status
// Improved logic to prevent successful payments from being marked as cancelled
function mapRtdnStatusToInternal(status) {
  if (status === "paid") return "paid";
  if (status === "pending") return "pending";
  if (status === "cancelled") return "cancelled";
  if (status === "refunded") return "refunded";
  if (status === "unknown") return "failed";
  return "failed";
}

// Enhanced RTDN processing to prevent incorrect status updates
function shouldUpdatePaymentStatus(currentStatus, newStatus) {
  // Don't downgrade successful payments to cancelled/failed
  if (currentStatus === "paid" || currentStatus === "completed") {
    if (newStatus === "cancelled" || newStatus === "failed") {
      console.log(`⚠️ Preventing status downgrade: ${currentStatus} → ${newStatus}`);
      return false;
    }
  }

  // Allow status upgrades and neutral changes
  return true;
}




// Store all purchase details from Flutter for complete audit trail
exports.storePurchaseDetails = onCall({ enforceAppCheck: config.enableAppCheck }, async (request) => {
  try {
    const { data, auth } = request;

    // Check authentication
    if (!auth) {
      throw new Error("Unauthorized");
    }

    // Log the request for debugging
    console.log("📥 storePurchaseDetails called");
    console.log("📥 Request data:", data);
    console.log("📥 Auth user:", auth.uid);

    if (!data) {
      console.log("❌ Request data is missing");
      throw new Error("Request data is missing");
    }

    const {
      paymentId,
      accountId,
      deviceId,
      productId,
      purchaseId,
      orderId,
      status,
      transactionDate,
      verificationData,
      errorDetails
    } = data;

    if (!accountId || !deviceId || !productId || !status) {
      throw new Error("Missing required fields: accountId, deviceId, productId, status");
    }

    console.log(`📝 Storing purchase details: ${paymentId}, status: ${status}, product: ${productId}`);

    const now = new Date();
    let purchaseTime = now;

    if (transactionDate) {
      console.log(`📅 Processing transactionDate: ${transactionDate} (type: ${typeof transactionDate})`);

      // Handle different timestamp formats
      if (typeof transactionDate === "string") {
        // Check if it's a numeric timestamp (milliseconds since epoch)
        if (/^\d+$/.test(transactionDate)) {
          purchaseTime = new Date(parseInt(transactionDate));
          console.log(`📅 Parsed as milliseconds timestamp: ${purchaseTime.toISOString()}`);
        } else {
          // Try to parse as ISO date string
          purchaseTime = new Date(transactionDate);
          console.log(`📅 Parsed as ISO date string: ${purchaseTime.toISOString()}`);
        }
      } else if (typeof transactionDate === "number") {
        purchaseTime = new Date(transactionDate);
        console.log(`📅 Parsed as numeric timestamp: ${purchaseTime.toISOString()}`);
      }

      // Validate the parsed date
      if (isNaN(purchaseTime.getTime())) {
        console.log("⚠️ Invalid transactionDate, using current time instead");
        purchaseTime = now;
      }
    }

    // Check if payment already exists by orderId or purchaseToken
    let existingPayment = null;
    let existingPaymentId = null;

    if (orderId) {
      // First try to find by orderId
      const orderQuery = await db.collection(config.collections.payments)
        .where("orderId", "==", orderId)
        .limit(1)
        .get();

      if (!orderQuery.empty) {
        existingPayment = orderQuery.docs[0].data();
        existingPaymentId = orderQuery.docs[0].id;
        console.log(`🔍 Found existing payment by orderId: ${existingPaymentId}`);
      }
    }

    // If not found by orderId, try by purchaseToken
    if (!existingPayment && verificationData?.serverVerificationData) {
      const tokenQuery = await db.collection(config.collections.payments)
        .where("verificationData.serverVerificationData", "==", verificationData.serverVerificationData)
        .limit(1)
        .get();

      if (!tokenQuery.empty) {
        existingPayment = tokenQuery.docs[0].data();
        existingPaymentId = tokenQuery.docs[0].id;
        console.log(`🔍 Found existing payment by serverVerificationData: ${existingPaymentId}`);
      }
    }

    if (existingPayment) {
      // Update existing payment document
      console.log(`🔄 Updating existing payment: ${existingPaymentId}`);

      await db.collection(config.collections.payments).doc(existingPaymentId).update({
        status: status,
        lastUpdated: now,
        updatedAt: now,
        verificationData: verificationData || existingPayment.verificationData,
        verificationLog: admin.firestore.FieldValue.arrayUnion({
          ts: now,
          status: status,
          notes: `Purchase status: ${status}`,
          source: "flutter",
          errorDetails: errorDetails || null
        })
      });

      console.log(`✅ Existing payment updated successfully: ${existingPaymentId}`);
    } else {
      // Create new payment document only if none exists
      const paymentData = {
        paymentId,
        accountId,
        deviceId,
        productId,
        purchaseId: purchaseId || null,
        orderId: orderId || null, // Include orderId if provided
        status,
        transactionDate: purchaseTime,
        verificationData: verificationData || null,
        errorDetails: errorDetails || null,
        lastUpdated: now,
        createdAt: now,
        updatedAt: now,
        verificationLog: [{
          ts: now,
          status: status,
          notes: `Purchase status: ${status}`,
          source: "flutter",
          errorDetails: errorDetails || null
        }]
      };

      // Store in payments collection
      await db.collection(config.collections.payments).doc(paymentId).set(paymentData);
      console.log(`✅ New payment created successfully: ${paymentId}`);
    }

    // If status is "completed", activate license
    if (status === "completed") {
      console.log(`🔑 Activating license for account ${accountId}`);

      // Update account with active license
      await db.collection(config.collections.accounts).doc(accountId).update({
        licenseType: "individual",
        licenseStart: now,
        lastVerified: now,
        offlineAllowedUntil: new Date(now.getTime() + 24 * 60 * 60 * 1000), // 1 day offline access
        lastPaymentId: paymentId,
        updatedAt: now
      });

      // Update device with active license
      await db.collection(config.collections.devices).doc(deviceId).update({
        licenseActive: true,
        lastLinked: now,
        updatedAt: now
      });

      console.log(`✅ License activated for account ${accountId}`);
    }

    // Log the storage
    await db.collection(config.collections.audit).add({
      action: "purchase_details_stored",
      details: {
        paymentId,
        accountId,
        deviceId,
        productId,
        status,
        source: "flutter"
      },
      timestamp: new Date(),
    });

    console.log(`✅ Purchase details stored successfully: ${paymentId}`);
    return { success: true, paymentId };

  } catch (error) {
    console.error("❌ Error storing purchase details:", error);
    throw new Error(`Failed to store purchase details: ${error.message}`);
  }
});

// Handle VoidedPurchaseNotification (refunds, chargebacks, voided purchases)
async function handleVoidedPurchaseNotification(voidedPurchase) {
  const purchaseToken = voidedPurchase?.purchaseToken;
  const orderId = voidedPurchase?.orderId;
  const productType = voidedPurchase?.productType;
  const refundType = voidedPurchase?.refundType;

  if (!purchaseToken) {
    console.log("⚠️ Missing purchaseToken in VoidedPurchaseNotification");
    return;
  }

  console.log(
    `🔍 Processing voided purchase: token=${purchaseToken}, ` +
    `orderId=${orderId}, productType=${productType}, refundType=${refundType}`
  );

  // Map refund type to status
  let status;
  switch (refundType) {
  case 1: // REFUND_TYPE_FULL_REFUND
    status = "refunded";
    break;
  case 2: // REFUND_TYPE_QUANTITY_BASED_PARTIAL_REFUND
    status = "partially_refunded";
    break;
  default:
    status = "voided";
  }

  console.log(`📊 Voided purchase status mapping: ${refundType} → ${status}`);

  // Find existing payment record by multiple search strategies
  let paymentDoc = null;
  let payment = null;

  // Strategy 1: Search by purchaseToken field
  let payQuery = await db.collection(config.collections.payments)
    .where("purchaseToken", "==", purchaseToken)
    .limit(1)
    .get();

  if (!payQuery.empty) {
    paymentDoc = payQuery.docs[0];
    payment = paymentDoc.data();
    console.log(`✅ Found payment by purchaseToken field: ${paymentDoc.id}`);
  } else {
    // Strategy 2: Search by verificationData.serverVerificationData
    console.log("🔍 No payment found by purchaseToken, searching by serverVerificationData...");

    payQuery = await db.collection(config.collections.payments)
      .where("verificationData.serverVerificationData", "==", purchaseToken)
      .limit(1)
      .get();

    if (!payQuery.empty) {
      paymentDoc = payQuery.docs[0];
      payment = paymentDoc.data();
      console.log(`✅ Found payment by serverVerificationData: ${paymentDoc.id}`);
    } else {
      // Strategy 3: Search by orderId (for Google Play orders)
      if (orderId && orderId.startsWith("GPA.")) {
        console.log("🔍 No payment found by serverVerificationData, searching by orderId...");

        payQuery = await db.collection(config.collections.payments)
          .where("orderId", "==", orderId)
          .limit(1)
          .get();

        if (!payQuery.empty) {
          paymentDoc = payQuery.docs[0];
          payment = paymentDoc.data();
          console.log(`✅ Found payment by orderId: ${paymentDoc.id}`);
        }
      }
    }
  }

  if (paymentDoc && payment) {
    // Found existing payment - update it instead of creating duplicate
    console.log(`🔄 Updating existing payment ${paymentDoc.id} to ${status}`);

    // Update payment status
    await paymentDoc.ref.update({
      status: status,
      refundType: refundType,
      rtdnReceived: true,
      rtdnTimestamp: new Date(),
      updatedAt: new Date(),
      verificationLog: admin.firestore.FieldValue.arrayUnion({
        ts: new Date(),
        status: status,
        notes: `Payment voided via RTDN: refundType=${refundType}, productType=${productType}`,
        source: "rtdn_voided"
      })
    });

    // MARK PURCHASE AS COMPLETE IN GOOGLE PLAY for refunds
    if (status === "refunded" || status === "partially_refunded") {
      try {
        console.log("🔄 Marking refunded purchase as complete in Google Play");

        await acknowledgePurchaseInGooglePlay(payment.purchaseToken ||
          payment.verificationData?.serverVerificationData, payment.productId);

        console.log("✅ Refunded purchase marked as complete in Google Play");
      } catch (error) {
        console.error("❌ Failed to mark refunded purchase as complete:", error);
      }
    }

    // Update account status if we have account info
    if (payment.accountId && payment.deviceId) {
      await updatePaymentAndAccountStatus(
        payment.accountId,
        payment.deviceId,
        paymentDoc.id,
        status
      );
    }

    console.log(`✅ Existing payment updated to ${status}: ${paymentDoc.id}`);
  } else {
    // No existing payment found - this should be rare but handle gracefully
    console.log(`⚠️ No payment record found for voided purchase token: ${purchaseToken}`);
    console.log("🔍 Searched by: purchaseToken, serverVerificationData, and orderId");

    // Only create orphaned record if we have minimal required data
    if (orderId && orderId.startsWith("GPA.")) {
      console.log(`📝 Creating orphaned voided payment record for order: ${orderId}`);

      const paymentId = `PAY-VOIDED-${Date.now()}-${purchaseToken.substring(0, 8)}`;
      const now = new Date();

      const paymentData = {
        paymentId,
        purchaseToken,
        orderId: orderId,
        status: status,
        refundType: refundType,
        productType: productType,
        rtdnReceived: true,
        rtdnTimestamp: now,
        createdAt: now,
        updatedAt: now,
        verificationLog: [{
          ts: now,
          status: status,
          notes: `Voided purchase from RTDN: refundType=${refundType}, productType=${productType}`,
          source: "rtdn_voided"
        }]
      };

      await db.collection(config.collections.payments).doc(paymentId).set(paymentData);
      console.log(`✅ Created orphaned voided payment record: ${paymentId}`);
    } else {
      console.log("⚠️ Insufficient data to create orphaned voided payment record");
    }
  }

  // Log the voided purchase processing
  await db.collection(config.collections.audit).add({
    action: "rtdn_voided_purchase_processed",
    details: {
      purchaseToken,
      orderId,
      productType,
      refundType,
      status,
      existingPaymentFound: !!(paymentDoc && payment),
      paymentId: paymentDoc ? paymentDoc.id : null
    },
    timestamp: new Date(),
  });
}

// Handle TestNotification (for debugging and testing)
async function handleTestNotification(testNotification) {
  const version = testNotification?.version;

  console.log(`🧪 Test notification received: version=${version}`);

  // Log test notification to audit collection
  await db.collection(config.collections.audit).add({
    action: "rtdn_test_notification",
    details: {
      version: version || "unknown",
      type: "test"
    },
    timestamp: new Date(),
  });

  console.log("✅ Test notification processed and logged");
}
