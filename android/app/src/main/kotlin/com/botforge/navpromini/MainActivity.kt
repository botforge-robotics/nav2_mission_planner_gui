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

    override fun isGamepadsInputDevice(device: android.view.InputDevice): Boolean {
        // Check source flags
        val sources = device.sources
        val hasGamepadSource = (sources and android.view.InputDevice.SOURCE_GAMEPAD) == android.view.InputDevice.SOURCE_GAMEPAD ||
                (sources and android.view.InputDevice.SOURCE_JOYSTICK) == android.view.InputDevice.SOURCE_JOYSTICK ||
                (sources and android.view.InputDevice.SOURCE_DPAD) == android.view.InputDevice.SOURCE_DPAD

        // Check if device has any gamepad button keys
        val hasGamepadKeys = device.hasKeys(
            KeyEvent.KEYCODE_BUTTON_A,
            KeyEvent.KEYCODE_BUTTON_B,
            KeyEvent.KEYCODE_BUTTON_X,
            KeyEvent.KEYCODE_BUTTON_Y,
            KeyEvent.KEYCODE_BUTTON_L1,
            KeyEvent.KEYCODE_BUTTON_R1,
            KeyEvent.KEYCODE_BUTTON_START,
            KeyEvent.KEYCODE_BUTTON_SELECT
        ).any { it }

        // Check if device has joystick/motion ranges
        val hasMotionRanges = device.motionRanges.any {
            (it.source and android.view.InputDevice.SOURCE_JOYSTICK) == android.view.InputDevice.SOURCE_JOYSTICK ||
            (it.source and android.view.InputDevice.SOURCE_GAMEPAD) == android.view.InputDevice.SOURCE_GAMEPAD
        }

        // If it explicitly claims gamepad source or has gamepad keys, accept it!
        val isGamepad = hasGamepadSource || hasGamepadKeys || hasMotionRanges
        android.util.Log.i("MainActivity", "isGamepadsInputDevice: ${device.name} (id=${device.id}) -> $isGamepad (source=$sources, keys=$hasGamepadKeys, motion=$hasMotionRanges)")
        return isGamepad
    }

    override fun dispatchGenericMotionEvent(motionEvent: MotionEvent): Boolean {
        val handled = motionListener?.invoke(motionEvent) == true
        if (handled) {
            return true
        }
        return super.dispatchGenericMotionEvent(motionEvent)
    }

    override fun dispatchKeyEvent(keyEvent: KeyEvent): Boolean {
        android.util.Log.d("MainActivity", "dispatchKeyEvent: action=${keyEvent.action}, keyCode=${keyEvent.keyCode} (${KeyEvent.keyCodeToString(keyEvent.keyCode)}), devId=${keyEvent.deviceId}")
        val handled = keyListener?.invoke(keyEvent) == true
        if (handled) {
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