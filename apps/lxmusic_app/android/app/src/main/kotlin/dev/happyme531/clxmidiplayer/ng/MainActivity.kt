package dev.happyme531.clxmidiplayer.ng

import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.system.Os
import android.system.OsConstants
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var playerOverlayChannel: MethodChannel? = null
    private var accessibilityPlaybackChannel: MethodChannel? = null
    private var externalFileOpenChannel: MethodChannel? = null
    private var crashTestChannel: MethodChannel? = null
    private var crashReportChannel: MethodChannel? = null
    private val crashReportPrompt by lazy { CrashReportPrompt(this) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        consumeExternalFileIntent(intent)
    }

    override fun onDestroy() {
        crashReportPrompt.close()
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        consumeExternalFileIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CALIBRATION_CHANNEL,
        ).setMethodCallHandler(::handleCalibrationCall)
        playerOverlayChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PLAYER_OVERLAY_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler(::handlePlayerOverlayCall)
            PlayerOverlayCoordinator.attach(channel)
        }
        accessibilityPlaybackChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ACCESSIBILITY_PLAYBACK_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler(::handleAccessibilityPlaybackCall)
            AccessibilityPlaybackCoordinator.attach(channel)
        }
        externalFileOpenChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ExternalFileOpenCoordinator.CHANNEL_NAME,
        ).also { channel ->
            channel.setMethodCallHandler(::handleExternalFileOpenCall)
            ExternalFileOpenCoordinator.attach(channel)
        }
        crashTestChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CRASH_TEST_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler(::handleCrashTestCall)
        }
        crashReportChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CRASH_REPORT_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler(crashReportPrompt::handleCall)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        playerOverlayChannel?.let { channel ->
            PlayerOverlayCoordinator.detach(channel)
            channel.setMethodCallHandler(null)
        }
        playerOverlayChannel = null
        accessibilityPlaybackChannel?.let { channel ->
            AccessibilityPlaybackCoordinator.detach(channel)
            channel.setMethodCallHandler(null)
        }
        accessibilityPlaybackChannel = null
        externalFileOpenChannel?.let { channel ->
            ExternalFileOpenCoordinator.detach(channel)
            channel.setMethodCallHandler(null)
        }
        externalFileOpenChannel = null
        crashTestChannel?.setMethodCallHandler(null)
        crashTestChannel = null
        crashReportChannel?.setMethodCallHandler(null)
        crashReportChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun handleCrashTestCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "crashKotlin" -> {
                result.success(null)
                window.decorView.post {
                    throw IllegalStateException("LxMusic-NG manual Kotlin crash-report test")
                }
            }
            "crashNativeSigsegv" -> {
                result.success(null)
                window.decorView.post {
                    // Send a real fatal native signal so this test exercises
                    // Sentry NDK, not the Flutter plugin's Java exception helper.
                    Os.kill(android.os.Process.myPid(), OsConstants.SIGSEGV)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun consumeExternalFileIntent(intent: Intent?) {
        if (intent != null && ExternalFileOpenCoordinator.enqueue(this, intent)) {
            setIntent(Intent())
        }
    }

    private fun handleExternalFileOpenCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "consumePendingFiles" -> result.success(
                ExternalFileOpenCoordinator.consumePending(),
            )
            "releaseCachedFiles" -> {
                val paths = call.argument<List<String>>("paths").orEmpty()
                ExternalFileOpenCoordinator.releaseCachedFiles(this, paths)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun handleAccessibilityPlaybackCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "getState" -> result.success(LxMusicAccessibilityService.playbackState())
            "start" -> {
                @Suppress("UNCHECKED_CAST")
                val request = call.arguments as? Map<String, Any?>
                if (request == null) {
                    result.success(errorResult("invalid_request", "演奏请求格式无效。"))
                    return
                }
                result.success(LxMusicAccessibilityService.startPlayback(request))
            }
            "pause" -> result.success(LxMusicAccessibilityService.pausePlayback())
            "stop" -> result.success(LxMusicAccessibilityService.stopPlayback())
            else -> result.notImplemented()
        }
    }

    private fun handlePlayerOverlayCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getState" -> result.success(playerOverlayState())
            "openAccessibilitySettings" -> {
                startActivity(
                    Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    },
                )
                result.success(null)
            }
            "showOverlay" -> {
                if (!isCalibrationServiceEnabled()) {
                    result.success(errorResult("accessibility_disabled", "无障碍服务尚未启用。"))
                    return
                }
                @Suppress("UNCHECKED_CAST")
                val request = call.arguments as? Map<String, Any?>
                if (request == null) {
                    result.success(errorResult("invalid_request", "悬浮播放器请求格式无效。"))
                    return
                }
                result.success(LxMusicAccessibilityService.showPlayerOverlay(request))
            }
            "hideOverlay" -> {
                LxMusicAccessibilityService.hidePlayerOverlay()
                result.success(null)
            }
            "updateOverlay" -> {
                @Suppress("UNCHECKED_CAST")
                val request = call.arguments as? Map<String, Any?>
                if (request == null) {
                    result.error("invalid_request", "播放器状态格式无效。", null)
                    return
                }
                LxMusicAccessibilityService.updatePlayerOverlay(request)
                result.success(null)
            }
            else -> result.notImplemented()
        }
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
            "orientationLockSupported" to supportsOrientationLock(),
            "targetOrientation" to preferences.getString(LAST_TARGET_ORIENTATION_KEY, null),
            "targetProfileId" to preferences.getString(LAST_TARGET_PROFILE_ID_KEY, null),
            "targetLayoutId" to preferences.getString(LAST_TARGET_LAYOUT_ID_KEY, null),
            "activeSessionId" to LxMusicAccessibilityService.activeSessionId(),
        )
    }

    private fun supportsOrientationLock(): Boolean =
        Build.VERSION.SDK_INT < 36 || resources.configuration.smallestScreenWidthDp < 600

    private fun playerOverlayState(): Map<String, Any?> = mapOf(
        "supported" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N),
        "accessibilityEnabled" to isCalibrationServiceEnabled(),
        "serviceReady" to LxMusicAccessibilityService.isServiceReady(),
        "overlayVisible" to LxMusicAccessibilityService.isPlayerOverlayVisible(),
    )

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
        const val PLAYER_OVERLAY_CHANNEL =
            "dev.happyme531.clxmidiplayer.ng/player_overlay"
        const val ACCESSIBILITY_PLAYBACK_CHANNEL =
            "dev.happyme531.clxmidiplayer.ng/accessibility_playback"
        const val NATIVE_PREFERENCES = "calibration_native.v1"
        const val PENDING_RESULT_KEY = "pending_result"
        const val LAST_TARGET_ORIENTATION_KEY = "last_target_orientation"
        const val LAST_TARGET_PROFILE_ID_KEY = "last_target_profile_id"
        const val LAST_TARGET_LAYOUT_ID_KEY = "last_target_layout_id"
        const val CRASH_TEST_CHANNEL =
            "dev.happyme531.clxmidiplayer.ng/crash_test"
        const val CRASH_REPORT_CHANNEL =
            "dev.happyme531.clxmidiplayer.ng/crash_report"
    }
}
