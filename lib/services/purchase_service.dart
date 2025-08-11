import 'dart:async';
import 'dart:io' show Platform;

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../providers/licensing_provider.dart';
import 'licensing_service.dart';
import 'play_integrity_service.dart';
import 'secure_storage_service.dart';

class PurchaseService {
  static const Set<String> _productIds = {
    // Test product IDs
    'test13', // Individual (test)
    'test23', // Enterprise (test)
    // Original product IDs (commented out)
    // 'n2mp_individual_lifetime',
    // 'n2mp_enterprise_lifetime',
  };

  static final Map<String, ProductDetails> _detailsCache = {};
  static Completer<void>? _currentPurchaseCompleter;
  static StreamSubscription<List<PurchaseDetails>>?
      _currentPurchaseSubscription;

  // Cancel any ongoing purchase
  static void cancelCurrentPurchase() {
    _currentPurchaseSubscription?.cancel();
    if (_currentPurchaseCompleter != null &&
        !_currentPurchaseCompleter!.isCompleted) {
      _currentPurchaseCompleter!.complete();
    }
    _currentPurchaseCompleter = null;
    _currentPurchaseSubscription = null;
  }

  static Future<ProductDetails?> _getProductDetails(String productId) async {
    print('🔍 Querying product details for: $productId');
    final response =
        await InAppPurchase.instance.queryProductDetails(<String>{productId});

    print('📦 Query response:');
    print('   Not found IDs: ${response.notFoundIDs}');
    print('   Product details count: ${response.productDetails.length}');

    if (response.notFoundIDs.isNotEmpty) {
      print('❌ Product not found: $productId');
      return null;
    }
    final products = response.productDetails;
    if (products.isEmpty) {
      print('❌ No products returned');
      return null;
    }

    // Since we requested a single id, the first should be our product
    final product = products.first;
    print('✅ Product found: ${product.title}');
    print('   ID: ${product.id}');
    print('   Price: ${product.price}');
    print('   Raw Price: ${product.rawPrice}');
    print('   Currency: ${product.currencyCode}');

    _detailsCache[productId] = product;
    return product;
  }

  // Public helper to fetch and cache details
  static Future<ProductDetails?> getProductDetails(String productId) async {
    if (_detailsCache.containsKey(productId)) return _detailsCache[productId];
    return _getProductDetails(productId);
  }

  static Future<String?> getPriceString(String productId) async {
    final details = await getProductDetails(productId);
    if (details != null) {
      print('💰 Product: $productId');
      print('   Raw Price: ${details.rawPrice}');
      print('   Price: ${details.price}');
      print('   Currency Code: ${details.currencyCode}');
      print('   Title: ${details.title}');
      print('   Description: ${details.description}');
    }
    return details?.price;
  }

  /// Get the Google Play Store account currently logged in on the device
  /// This is different from the Firebase Auth account used in the app
  static Future<String?> getPlayStoreAccount() async {
    if (!Platform.isAndroid) return null;

    try {
      // Unfortunately, there's no direct API to get the Play Store account
      // We'll need to rely on the stored account information
      final packageInfo = await PackageInfo.fromPlatform();
      print('📱 Package name: ${packageInfo.packageName}');

      // We can only know the Play Store account after a purchase is made
      return null;
    } catch (e) {
      print('⚠️ Error getting Play Store account: $e');
      return null;
    }
  }

  /// Get package name for the app
  static Future<String> getPackageName() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.packageName;
  }

  // Update the server with purchase information in the background
  static void _updateServerInBackground(
      String productId, String purchaseToken) async {
    // Get Google account ID
    final googleAccountId = await SecureStorageService.getGoogleAccountId();

    // Try to get Play Store account info
    final playStoreAccount = await getPlayStoreAccount();
    if (playStoreAccount != null) {
      print('📱 Play Store account: $playStoreAccount');
      // Store this for future reference
      await SecureStorageService.storeGoogleAccountId(playStoreAccount);
    }

    // Use Future.delayed to ensure this runs after UI updates
    Future.delayed(const Duration(seconds: 1), () async {
      try {
        print('🔄 Updating server with purchase information');
        print('📱 Using Google account ID: $googleAccountId');

        final result = await LicensingService.updateLicenseOnServer(
          productId: productId,
          purchaseToken: purchaseToken,
          googleAccountId: googleAccountId,
        );

        if (result['success'] == true) {
          print('✅ Server license update successful');
        } else {
          print(
              '⚠️ Server license update failed: ${result['error']?['message']}');
        }
      } catch (e) {
        print('❌ Error updating server license: $e');
      }
    });
  }

  // Restore purchases from Firebase
  static Future<bool> restorePurchases(
      {required LicensingProvider licensingProvider}) async {
    print('🔄 Restoring purchases from Firebase...');

    try {
      // Get the current user's license status from Firebase
      final licenseResult = await LicensingService.getLicenseStatus();

      if (licenseResult['success'] == true) {
        final data = licenseResult['data'];
        final status = data['status'] as String?;

        if (status == 'license_active') {
          // User already has an active license, no need to restore
          print('✅ User already has active license: ${data['licenseType']}');
          return true;
        }
      }

      // No active license found
      print('ℹ️ No active license found to restore');
      return false;
    } catch (e) {
      print('❌ Error during Firebase restore: $e');
      return false;
    }
  }

  static Future<void> buyProduct(String productId,
      {required LicensingProvider licensingProvider,
      bool allowRestore = true}) async {
    if (!_productIds.contains(productId)) {
      throw Exception('Unknown productId');
    }

    final available = await InAppPurchase.instance.isAvailable();
    if (!available) {
      throw Exception('Store not available');
    }

    // Check device integrity before proceeding with purchase
    final integrityValid = await PlayIntegrityService().checkDeviceIntegrity();
    if (!integrityValid) {
      throw Exception(
          'Device integrity check failed. Please ensure you are using a genuine device and app.');
    }

    final product = await _getProductDetails(productId);
    if (product == null) {
      throw Exception('Product unavailable');
    }

    // If allowRestore is true, try to restore purchases first
    if (allowRestore) {
      try {
        print('🔄 Attempting to restore purchases before buying');
        await restorePurchases(licensingProvider: licensingProvider);
        // If we get here without an exception, we might have restored successfully
        // But we'll continue with the purchase flow anyway
      } catch (e) {
        print('⚠️ Restore failed, continuing with purchase: $e');
        // Continue with purchase even if restore fails
      }
    }

    final purchaseParam = PurchaseParam(productDetails: product);

    _currentPurchaseCompleter = Completer<void>();
    bool purchasedHandled = false;
    // Create the purchase listener only once and keep it alive, so late
    // events after returning from Play are still delivered.
    _currentPurchaseSubscription ??=
        InAppPurchase.instance.purchaseStream.listen((purchases) async {
      print('🔄 Purchase stream received ${purchases.length} purchase updates');
      try {
        for (final purchase in purchases) {
          print(
              '📦 Processing purchase: ${purchase.productID} with status: ${purchase.status}');
          if (purchase.productID != productId) {
            print(
                '⏭️ Skipping purchase for different product: ${purchase.productID} != $productId');
            continue;
          }
          print(
              '🎯 Processing purchase for target product: $productId with status: ${purchase.status}');
          switch (purchase.status) {
            case PurchaseStatus.pending:
              // do nothing, wait
              break;
            case PurchaseStatus.error:
              final errorMessage = purchase.error?.message;
              if (errorMessage != null &&
                  errorMessage.contains('already own')) {
                print(
                    '⚠️ User already owns this product. Attempting to restore purchase...');
                try {
                  // Attempt to restore purchases immediately
                  await restorePurchases(licensingProvider: licensingProvider);

                  if (!(_currentPurchaseCompleter?.isCompleted ?? true)) {
                    _currentPurchaseCompleter
                        ?.complete(); // Complete successfully
                  }
                } catch (e) {
                  print('❌ Error during automatic restore: $e');
                  if (!(_currentPurchaseCompleter?.isCompleted ?? true)) {
                    _currentPurchaseCompleter?.completeError(Exception(
                        'You already own this product, but we couldn\'t restore it automatically. Please try restoring purchases.'));
                  }
                }
              } else {
                if (!(_currentPurchaseCompleter?.isCompleted ?? true)) {
                  _currentPurchaseCompleter?.completeError(
                      Exception(purchase.error?.message ?? 'Purchase failed'));
                }
              }
              break;
            case PurchaseStatus.canceled:
              if (!(_currentPurchaseCompleter?.isCompleted ?? true)) {
                _currentPurchaseCompleter
                    ?.completeError(Exception('Purchase cancelled'));
              }
              break;
            case PurchaseStatus.purchased:
            case PurchaseStatus.restored:
              try {
                purchasedHandled = true;
                print('✅ Purchase successful: ${purchase.productID}');
                final purchaseToken =
                    purchase.verificationData.serverVerificationData;

                print('🔑 Setting license active in provider...');
                // Mark the purchase as successful in the provider immediately
                await licensingProvider.setLicenseActive(
                  licenseType: productId.contains('enterprise')
                      ? 'enterprise'
                      : 'individual',
                  productId: productId,
                );
                print('✅ License provider updated successfully');

                // Update the server in the background
                print('🔄 Starting background server update...');
                _updateServerInBackground(productId, purchaseToken);
              } finally {
                // Always complete the purchase to finalize in Play
                // For consumable purchases, this is especially important
                await InAppPurchase.instance.completePurchase(purchase);
                print('✅ Purchase finalized in Play Store');
              }
              if (!(_currentPurchaseCompleter?.isCompleted ?? true)) {
                print('✅ Completing purchase future successfully');
                _currentPurchaseCompleter?.complete();
              }
              break;
          }
        }
      } catch (e) {
        if (!(_currentPurchaseCompleter?.isCompleted ?? true))
          _currentPurchaseCompleter?.completeError(e);
      }
    });

    try {
      // Start non-consumable purchase for lifetime license
      print('🛒 Starting non-consumable purchase...');
      final ok = await InAppPurchase.instance.buyNonConsumable(
        purchaseParam: purchaseParam,
      );
      if (!ok) {
        print('❌ Failed to start non-consumable purchase');
        _currentPurchaseSubscription?.cancel();
        throw Exception('Failed to start purchase');
      }
      print(
          '✅ Non-consumable purchase started successfully, waiting for completion...');
      // Wait for purchase update without timeout
      // Wait for a purchased/restored event from the persistent listener
      await _currentPurchaseCompleter!.future;
      print('✅ Purchase future completed successfully');
      // Fallback: if purchased event did not arrive (rare), attempt restore.
      if (!purchasedHandled) {
        print('🔄 Fallback: calling InAppPurchase.restorePurchases()');
        await InAppPurchase.instance.restorePurchases();
        // Give time for restored events to arrive on the same listener
        await Future.delayed(const Duration(seconds: 2));
      }
    } catch (e) {
      print('❌ Error during purchase: $e');
      rethrow;
    } finally {
      // Do not cancel the subscription here; keep it for late events
      print('🧹 Purchase flow finished (listener kept alive)');
    }
  }
}
