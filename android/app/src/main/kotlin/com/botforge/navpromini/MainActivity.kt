package com.botforge.navpromini

import android.hardware.input.InputManager
import android.os.Bundle
import android.os.Handler
import android.view.KeyEvent
import android.view.MotionEvent
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.flame_engine.gamepads_android.GamepadsCompatibleActivity

class MainActivity: FlutterActivity(), GamepadsCompatibleActivity {
    private val WIDEVINE_CHANNEL = "widevine_service"
    private var keyListener: ((KeyEvent) -> Boolean)? = null
    private var motionListener: ((MotionEvent) -> Boolean)? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Enable edge-to-edge for Android 15 compatibility
        WindowCompat.setDecorFitsSystemWindows(window, false)
    }

    override fun dispatchGenericMotionEvent(motionEvent: MotionEvent): Boolean {
        if (motionListener?.invoke(motionEvent) == true) {
            return true
        }
        return super.dispatchGenericMotionEvent(motionEvent)
    }

    override fun dispatchKeyEvent(keyEvent: KeyEvent): Boolean {
        if (keyListener?.invoke(keyEvent) == true) {
            return true
        }
        return super.dispatchKeyEvent(keyEvent)
    }

    override fun registerInputDeviceListener(
        listener: InputManager.InputDeviceListener, handler: Handler?
    ) {
        val inputManager = getSystemService(INPUT_SERVICE) as InputManager
        inputManager.registerInputDeviceListener(listener, handler)
    }

    override fun registerKeyEventHandler(handler: (KeyEvent) -> Boolean) {
        keyListener = handler
    }

    override fun registerMotionEventHandler(handler: (MotionEvent) -> Boolean) {
        motionListener = handler
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
    }
}