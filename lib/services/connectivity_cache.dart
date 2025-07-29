import 'dart:async';

class ConnectivityCache {
  static bool? _cachedOnlineStatus;
  static DateTime? _lastConnectivityCheck;
  static const Duration _cacheDuration = Duration(minutes: 5);

  // Prevent multiple simultaneous connectivity checks
  static bool _isChecking = false;
  static Completer<bool>? _pendingCheck;

  // Get cached connectivity status or perform new check
  static Future<bool> getConnectivityStatus(
      Future<bool> Function() connectivityCheck) async {
    final now = DateTime.now();

    // Check if we have a cached result that's still valid
    if (_cachedOnlineStatus != null && _lastConnectivityCheck != null) {
      final timeSinceLastCheck = now.difference(_lastConnectivityCheck!);
      if (timeSinceLastCheck < _cacheDuration) {
        print(
            '💾 ConnectivityCache: Using cached status: $_cachedOnlineStatus (${timeSinceLastCheck.inSeconds}s ago)');
        return _cachedOnlineStatus!;
      }
    }

    // If there's already a check in progress, wait for it
    if (_isChecking && _pendingCheck != null) {
      print('⏳ ConnectivityCache: Waiting for ongoing connectivity check...');
      return await _pendingCheck!.future;
    }

    // Start new connectivity check
    _isChecking = true;
    _pendingCheck = Completer<bool>();

    print('🔄 ConnectivityCache: Making new connectivity check...');

    try {
      final isOnline = await connectivityCheck();

      // Cache the result
      _cachedOnlineStatus = isOnline;
      _lastConnectivityCheck = now;

      print('💾 ConnectivityCache: Cached connectivity status: $isOnline');

      // Complete the pending check
      _pendingCheck!.complete(isOnline);
      return isOnline;
    } catch (e) {
      print(
          '⚠️ ConnectivityCache: Connectivity check error, using cached status: ${_cachedOnlineStatus ?? false}');
      final fallbackStatus = _cachedOnlineStatus ?? false;

      // Complete the pending check with fallback
      _pendingCheck!.complete(fallbackStatus);
      return fallbackStatus;
    } finally {
      _isChecking = false;
      _pendingCheck = null;
    }
  }

  // Clear the cache (for manual refresh)
  static void clearCache() {
    print('🗑️ ConnectivityCache: Clearing cache');
    _cachedOnlineStatus = null;
    _lastConnectivityCheck = null;
    _isChecking = false;
    _pendingCheck = null;
  }

  // Get cache info for debugging
  static Map<String, dynamic> getCacheInfo() {
    return {
      'cachedStatus': _cachedOnlineStatus,
      'lastCheck': _lastConnectivityCheck?.toIso8601String(),
      'isChecking': _isChecking,
      'hasPendingCheck': _pendingCheck != null,
    };
  }
}
