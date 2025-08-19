package com.botforge.nav2missionplanner

import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import android.content.Context
import android.accounts.Account
import android.accounts.AccountManager
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import android.Manifest

class MainActivity: FlutterActivity() {
    private val WIDEVINE_CHANNEL = "widevine_service"
    private val PLAY_INTEGRITY_CHANNEL = "play_integrity"
    private val CHANNEL = "google_play_service"
    private val PERMISSION_REQUEST_CODE = 123

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Enable edge-to-edge for Android 15 compatibility
        WindowCompat.setDecorFitsSystemWindows(window, false)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Widevine service channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDEVINE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getWidevineId" -> {
                    try {
                        val widevineId = MediaDrmHelper.getWidevineId()
                        result.success(widevineId)
                    } catch (e: Exception) {
                        result.error("WIDEVINE_ERROR", "Failed to get Widevine ID", e.message)
                    }
                }
                "isWidevineSupported" -> {
                    try {
                        val isSupported = MediaDrmHelper.isWidevineSupported()
                        result.success(isSupported)
                    } catch (e: Exception) {
                        result.error("WIDEVINE_ERROR", "Failed to check Widevine support", e.message)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Play Integrity service channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PLAY_INTEGRITY_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getIntegrityToken" -> {
                    CoroutineScope(Dispatchers.Main).launch {
                        try {
                            val playIntegrityHelper = PlayIntegrityHelper(this@MainActivity)
                            val token = playIntegrityHelper.getIntegrityToken()
                            result.success(token)
                        } catch (e: Exception) {
                            result.error("INTEGRITY_ERROR", "Failed to get integrity token", e.message)
                        }
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getGoogleAccountId" -> {
                    getGoogleAccountId(result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun getGoogleAccountId(result: MethodChannel.Result) {
        try {
            // Check if we have the required permission
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.GET_ACCOUNTS)
                != PackageManager.PERMISSION_GRANTED) {

                // Request permission
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.GET_ACCOUNTS),
                    PERMISSION_REQUEST_CODE
                )

                // For now, return a fallback - the permission will be granted on next call
                result.success("PERMISSION_PENDING")
                return
            }

            val accountManager = getSystemService(Context.ACCOUNT_SERVICE) as AccountManager
            val accounts = accountManager.accounts

            // Look for Google accounts
            val googleAccounts = accounts.filter { account ->
                account.type == "com.google" ||
                account.name.contains("@gmail.com") ||
                account.name.contains("@googlemail.com")
            }

            if (googleAccounts.isNotEmpty()) {
                // Return the first Google account found
                val primaryAccount = googleAccounts.first()
                result.success(primaryAccount.name)
            } else {
                // Look for any account that might be Google-related
                val anyAccount = accounts.firstOrNull { account ->
                    account.name.contains("@") &&
                    (account.type.contains("google") || account.type.contains("account"))
                }

                if (anyAccount != null) {
                    result.success(anyAccount.name)
                } else {
                    // No Google accounts found, return device identifier
                    result.success("NO_GOOGLE_ACCOUNT")
                }
            }

        } catch (e: Exception) {
            // Return error information
            result.success("ERROR: ${e.message}")
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode == PERMISSION_REQUEST_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                // Permission granted, can now access accounts
                println("✅ GET_ACCOUNTS permission granted")
            } else {
                // Permission denied
                println("❌ GET_ACCOUNTS permission denied")
            }
        }
    }
}