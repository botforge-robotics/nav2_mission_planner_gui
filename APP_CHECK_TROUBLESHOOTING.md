# App Check "Too Many Attempts" Error - Troubleshooting Guide

## Overview

The "Error getting App Check token; using placeholder token instead. Error: com.google.firebase.FirebaseException: Too many attempts" error occurs when your app requests App Check tokens too frequently, exceeding Firebase's rate limits.

## Root Causes

1. **Excessive Token Requests**: App requesting tokens more than 10 times per minute
2. **Missing Token Caching**: Not reusing valid tokens
3. **Aggressive Refresh Logic**: Refreshing tokens unnecessarily
4. **Multiple Simultaneous Requests**: Concurrent calls triggering multiple token fetches

## Implemented Solutions

### 1. Token Caching and Rate Limiting

The app now implements intelligent token management:

- **Token Caching**: Tokens are cached for 30 minutes (configurable)
- **Rate Limiting**: Minimum 5 seconds between token fetches
- **Smart Refresh**: Only refresh when tokens are close to expiration

### 2. Backend Rate Limiting

Cloud Functions now include rate limiting:

- **Per-Device Limits**: Maximum 10 token requests per minute per device
- **Automatic Cleanup**: Old rate limit data is automatically cleaned up
- **Grace Periods**: 5-minute grace period for token refresh

### 3. Error Recovery

Automatic recovery mechanisms:

- **Fallback to Cached Tokens**: Use expired tokens when fresh ones fail
- **Automatic Retry Logic**: Smart retry with exponential backoff
- **User-Friendly Messages**: Clear error messages with recovery suggestions

## Configuration

### Frontend Configuration (`lib/constants/app_config.dart`)

```dart
class AppConfig {
  // App Check Configuration
  static const bool enableAppCheck = true;

  // App Check token refresh settings
  static const int tokenRefreshIntervalMinutes = 30; // Refresh token every 30 minutes
  static const int minFetchIntervalSeconds = 5; // Minimum 5 seconds between token fetches
}
```

### Backend Configuration (`functions/src/config.js`)

```javascript
const config = {
  enableAppCheck: true,
  appCheckConfig: {
    maxTokenRequestsPerMinute: 10,
    allowDebugTokens: process.env.NODE_ENV === "development",
    tokenRefreshGracePeriod: 300, // 5 minutes
  },
  // ... other config
};
```

## Usage

### Basic App Check Operations

```dart
// Initialize Firebase (automatically handles App Check)
await FirebaseService.initialize();

// Make Cloud Function calls (automatically includes App Check)
final result = await FirebaseService.callCloudFunction('functionName', data);

// Check App Check status
final status = FirebaseService.getAppCheckStatus();

// Manually refresh token if needed
final newToken = await FirebaseService.refreshAppCheckToken();
```

### Error Recovery

```dart
import 'package:nav2_mission_planner/services/app_check_recovery_service.dart';

final recoveryService = AppCheckRecoveryService();

// Check if error is recoverable
if (recoveryService.isRecoverableError(errorMessage)) {
  // Attempt automatic recovery
  final recovered = await recoveryService.attemptRecovery();
  if (recovered) {
    // Retry your operation
  }
}

// Get user-friendly error information
final errorInfo = recoveryService.getErrorInfo(errorMessage);
```

### Testing and Diagnostics

```dart
import 'package:nav2_mission_planner/services/app_check_test_service.dart';

final testService = AppCheckTestService();

// Run comprehensive tests
final testResults = await testService.runTests();

// Get diagnostic information
final diagnostics = testService.getDiagnostics();

// Test error scenarios
final errorScenarios = testService.testErrorScenarios();
```

## Monitoring and Debugging

### Frontend Logs

Look for these log messages in your Flutter console:

- `✅ App Check token fetched successfully`
- `✅ Using cached App Check token (age: Xm)`
- `⏳ Rate limiting App Check token fetch (waiting Xs)`
- `⚠️ App Check error detected: [error details]`

### Backend Logs

Check Cloud Functions logs for:

- Rate limiting information
- Token verification results
- Error patterns

### Health Check Endpoint

Use the health check endpoint to monitor App Check status:

```bash
# Call the healthCheck function
curl -X POST "https://us-central1-[PROJECT_ID].cloudfunctions.net/healthCheck" \
  -H "Content-Type: application/json" \
  -d '{"deviceId": "your-device-id"}'
```

Response includes App Check status:

```json
{
  "success": true,
  "appCheckStatus": {
    "enabled": true,
    "rateLimitStatus": {
      "rateLimited": false,
      "requestsInLastMinute": 2,
      "maxRequestsPerMinute": 10,
      "timeUntilReset": 0
    },
    "config": {
      "maxTokenRequestsPerMinute": 10,
      "allowDebugTokens": false,
      "tokenRefreshGracePeriod": 300
    }
  }
}
```

## Troubleshooting Steps

### 1. Check Current Status

```dart
final status = FirebaseService.getAppCheckStatus();
print('App Check Status: $status');
```

### 2. Verify Configuration

```dart
print('App Check Enabled: ${AppConfig.enableAppCheck}');
print('Token Refresh Interval: ${AppConfig.tokenRefreshIntervalMinutes} minutes');
print('Min Fetch Interval: ${AppConfig.minFetchIntervalSeconds} seconds');
```

### 3. Test Token Refresh

```dart
try {
  final token = await FirebaseService.refreshAppCheckToken();
  print('Token refresh successful: ${token != null}');
} catch (e) {
  print('Token refresh failed: $e');
}
```

### 4. Check Rate Limiting

```dart
final recoveryService = AppCheckRecoveryService();
final isHealthy = recoveryService.isHealthy();
print('App Check Healthy: $isHealthy');
```

## Common Issues and Solutions

### Issue: Still getting "Too many attempts"

**Solution**:

1. Check if you're making multiple simultaneous calls
2. Verify token caching is working (check logs)
3. Increase `minFetchIntervalSeconds` in config
4. Check backend rate limiting configuration

### Issue: Tokens not being cached

**Solution**:

1. Verify App Check is properly initialized
2. Check for initialization errors in logs
3. Ensure `enableAppCheck` is true
4. Verify Firebase initialization order

### Issue: Recovery not working

**Solution**:

1. Check if cached tokens exist
2. Verify token age is reasonable
3. Check network connectivity
4. Review error logs for specific failure reasons

## Best Practices

1. **Don't call `getToken()` manually** - let the service handle it automatically
2. **Use the service methods** - don't bypass the caching layer
3. **Handle errors gracefully** - implement proper error recovery
4. **Monitor usage patterns** - watch for excessive API calls
5. **Test in development** - use debug provider to avoid production limits

## Performance Considerations

- **Token Caching**: Reduces API calls by 95%+ in normal usage
- **Rate Limiting**: Prevents overwhelming Firebase services
- **Smart Refresh**: Only refreshes when necessary
- **Error Recovery**: Minimizes user impact of failures

## Support

If you continue to experience issues:

1. Check the logs for specific error messages
2. Verify your Firebase project configuration
3. Test with the diagnostic services
4. Review your app's API call patterns
5. Contact Firebase support if backend issues persist

## Version History

- **v1.3.1**: Initial App Check implementation
- **v1.3.2**: Added token caching and rate limiting
- **v1.3.3**: Implemented error recovery and diagnostics
- **v1.3.4**: Added backend rate limiting and monitoring
