package com.anniekaydee.subtitle_app

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.view.KeyEvent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Native side of Tap Sync ("ແຕະໃຫ້ຕົງ"):
 *  - volume keys as a tap button (only while the Tap Sync screen enables it),
 *  - detect Bluetooth audio output (adds 100–300 ms latency → warn the user).
 *
 * Method channel: com.anniekaydee.subtitle_app/tapsync
 *  Dart → native: setVolumeKeyCapture {enabled}, isBluetoothOutput
 *  native → Dart: volumeKey {down: Boolean}
 */
class TapSyncBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    var channel: MethodChannel? = null
    private var captureVolumeKeys = false

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setVolumeKeyCapture" -> {
                captureVolumeKeys = call.argument<Boolean>("enabled") ?: false
                result.success(null)
            }
            "isBluetoothOutput" -> result.success(isBluetoothOutput())
            else -> result.notImplemented()
        }
    }

    /** Returns true when the key event was consumed (volume does not change). */
    fun handleKeyEvent(event: KeyEvent): Boolean {
        if (!captureVolumeKeys) return false
        val code = event.keyCode
        if (code != KeyEvent.KEYCODE_VOLUME_UP && code != KeyEvent.KEYCODE_VOLUME_DOWN) {
            return false
        }
        when (event.action) {
            KeyEvent.ACTION_DOWN -> if (event.repeatCount == 0) {
                channel?.invokeMethod("volumeKey", mapOf("down" to true))
            }
            KeyEvent.ACTION_UP -> channel?.invokeMethod("volumeKey", mapOf("down" to false))
        }
        return true
    }

    private fun isBluetoothOutput(): Boolean {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val bt = mutableSetOf(
                AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                bt.add(AudioDeviceInfo.TYPE_BLE_HEADSET)
                bt.add(AudioDeviceInfo.TYPE_BLE_SPEAKER)
            }
            return am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { it.type in bt }
        }
        @Suppress("DEPRECATION")
        return am.isBluetoothA2dpOn || am.isBluetoothScoOn
    }
}
