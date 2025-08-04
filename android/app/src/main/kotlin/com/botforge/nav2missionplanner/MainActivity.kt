package com.botforge.nav2missionplanner

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "widevine_service"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
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
    }
}