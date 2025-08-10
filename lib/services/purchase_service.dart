import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

import '../providers/licensing_provider.dart';
import 'licensing_service.dart';
import 'play_integrity_service.dart';

class PurchaseService {
  static const Set<String> _productIds = {
    // Match server config productMap keys
    'n2mp_individual_lifetime',
    'n2mp_enterprise_lifetime',
  };

  static Future<ProductDetails?> _getProductDetails(String productId) async {
    final response =
        await InAppPurchase.instance.queryProductDetails(<String>{productId});
    if (response.notFoundIDs.isNotEmpty) {
      return null;
    }
    final products = response.productDetails;
    if (products.isEmpty) return null;
    // Since we requested a single id, the first should be our product
    return products.first;
  }

  static Future<void> buyProduct(String productId,
      {required LicensingProvider licensingProvider}) async {
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

    final purchaseParam = PurchaseParam(productDetails: product);

    final completer = Completer<void>();
    late final StreamSubscription<List<PurchaseDetails>> sub;
    sub = InAppPurchase.instance.purchaseStream.listen((purchases) async {
      try {
        for (final purchase in purchases) {
          if (purchase.productID != productId) continue;
          switch (purchase.status) {
            case PurchaseStatus.pending:
              // do nothing, wait
              break;
            case PurchaseStatus.error:
              if (!completer.isCompleted) {
                completer.completeError(
                    Exception(purchase.error?.message ?? 'Purchase failed'));
              }
              break;
            case PurchaseStatus.canceled:
              if (!completer.isCompleted) {
                completer.completeError(Exception('Purchase cancelled'));
              }
              break;
            case PurchaseStatus.purchased:
            case PurchaseStatus.restored:
              // On Android, use serverVerificationData as purchaseToken
              final purchaseToken =
                  purchase.verificationData.serverVerificationData;
              try {
                final res = await LicensingService.verifyGooglePurchase(
                  purchaseToken: purchaseToken,
                  productId: productId,
                );
                if (res['success'] != true) {
                  throw Exception(
                      res['error']?['message'] ?? 'Verification failed');
                }
                await licensingProvider.refresh();
              } finally {
                // Always complete the purchase to finalize in Play
                await InAppPurchase.instance.completePurchase(purchase);
              }
              if (!completer.isCompleted) completer.complete();
              break;
          }
        }
      } catch (e) {
        if (!completer.isCompleted) completer.completeError(e);
      }
    });

    try {
      final ok = await InAppPurchase.instance.buyNonConsumable(
        purchaseParam: purchaseParam,
      );
      if (!ok) {
        sub.cancel();
        throw Exception('Failed to start purchase');
      }
      // Wait for purchase update / verification result
      await completer.future.timeout(const Duration(minutes: 2));
    } finally {
      await sub.cancel();
    }
  }
}
