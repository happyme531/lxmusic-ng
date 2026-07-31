package dev.happyme531.clxmidiplayer.ng

import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CALIBRATION_CHANNEL,
        ).setMethodCallHandler(::handleCalibrationCall)
    }

    private fun handleCalibrationCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getState" -> result.success(calibrationState())
            "findLaunchableTargets" -> {
                val hints = call.argument<List<String>>("packageNameHints").orEmpty()
                result.success(CalibrationPlatformSupport.findLaunchableTargets(this, hints))
            }
            "openAccessibilitySettings" -> {
                startActivity(
                    Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    },
                )
                result.success(null)
            }
            "startSession" -> {
                if (!isCalibrationServiceEnabled()) {
                    result.success(errorResult("accessibility_disabled", "无障碍服务尚未启用。"))
                    return
                }
                @Suppress("UNCHECKED_CAST")
                val request = call.arguments as? Map<String, Any?>
                if (request == null) {
                    result.success(errorResult("invalid_request", "校准请求格式无效。"))
                    return
                }
                result.success(LxMusicAccessibilityService.startCalibration(request))
            }
            "cancelSession" -> {
                LxMusicAccessibilityService.cancelCalibration()
                result.success(null)
            }
            "consumePendingResult" -> {
                val preferences = getSharedPreferences(NATIVE_PREFERENCES, MODE_PRIVATE)
                val raw = preferences.getString(PENDING_RESULT_KEY, null)
                if (raw == null) {
                    result.success(null)
                } else {
                    preferences.edit().remove(PENDING_RESULT_KEY).apply()
                    result.success(CalibrationPlatformSupport.jsonObjectToMap(raw))
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun calibrationState(): Map<String, Any?> {
        val display = CalibrationPlatformSupport.displayInfo(this)
        val preferences = getSharedPreferences(NATIVE_PREFERENCES, MODE_PRIVATE)
        return mapOf(
            "supported" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N),
            "accessibilityEnabled" to isCalibrationServiceEnabled(),
            "apiLevel" to Build.VERSION.SDK_INT,
            "deviceId" to CalibrationPlatformSupport.stableDeviceId(this),
            "deviceDisplayName" to CalibrationPlatformSupport.deviceDisplayName(),
            "viewportWidthPx" to display.widthPx,
            "viewportHeightPx" to display.heightPx,
            "density" to display.density,
            "displayRotation" to display.rotation,
            "targetOrientation" to preferences.getString(LAST_TARGET_ORIENTATION_KEY, null),
            "targetProfileId" to preferences.getString(LAST_TARGET_PROFILE_ID_KEY, null),
            "targetLayoutId" to preferences.getString(LAST_TARGET_LAYOUT_ID_KEY, null),
            "activeSessionId" to LxMusicAccessibilityService.activeSessionId(),
        )
    }

    private fun isCalibrationServiceEnabled(): Boolean {
        val expected = ComponentName(this, LxMusicAccessibilityService::class.java)
        val enabled = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ).orEmpty()
        return enabled.split(':').any { flattened ->
            ComponentName.unflattenFromString(flattened) == expected
        }
    }

    private fun errorResult(code: String, message: String): Map<String, Any?> =
        mapOf(
            "status" to "error",
            "errorCode" to code,
            "message" to message,
        )

    companion object {
        const val CALIBRATION_CHANNEL =
            "dev.happyme531.clxmidiplayer.ng/calibration"
        const val NATIVE_PREFERENCES = "calibration_native.v1"
        const val PENDING_RESULT_KEY = "pending_result"
        const val LAST_TARGET_ORIENTATION_KEY = "last_target_orientation"
        const val LAST_TARGET_PROFILE_ID_KEY = "last_target_profile_id"
        const val LAST_TARGET_LAYOUT_ID_KEY = "last_target_layout_id"
    }
}
