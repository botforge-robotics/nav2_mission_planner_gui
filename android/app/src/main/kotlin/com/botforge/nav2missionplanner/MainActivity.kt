package com.botforge.nav2missionplanner

import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class MainActivity: FlutterActivity() {
    private val WIDEVINE_CHANNEL = "widevine_service"
    private val PLAY_INTEGRITY_CHANNEL = "play_integrity"

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
    }
}