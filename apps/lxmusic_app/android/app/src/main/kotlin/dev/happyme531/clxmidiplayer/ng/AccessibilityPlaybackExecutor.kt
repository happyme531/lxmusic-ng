package dev.happyme531.clxmidiplayer.ng

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.res.Configuration
import android.graphics.Path
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import kotlin.math.max
import kotlin.math.roundToLong

/**
 * Schedules calibrated tap-only executable plans on Android's monotonic clock.
 *
 * Android has no side-effect-free API for cancelling a dispatched gesture.
 * Short and repeated-tap modes therefore remain the safest defaults. Native
 * hold mode accepts the compiler's bounded per-point durations; pause/stop
 * takes effect after the currently dispatched gesture completes.
 */
internal class AccessibilityPlaybackExecutor(
    private val service: AccessibilityService,
    private val foregroundPackage: () -> String?,
    private val overlayBounds: () -> Rect?,
    private val calibrationActive: () -> Boolean,
) {
    private val handler = Handler(Looper.getMainLooper())
    private var generation = 0L
    private var plan: PlaybackPlan? = null
    private var scheduledActions = emptyList<PlaybackAction>()
    private var nextActionIndex = 0
    private var pendingRunnable: Runnable? = null
    private var inFlightGeneration: Long? = null
    private var playbackId: String? = null
    private var playing = false
    private var originPlanMs = 0L
    private var originRealtimeMs = 0L
    private var speed = 1.0
    private var timingOffsetMs = 0L
    private var expectedOrientation: String? = null
    private var expectedPhysicalWidthPx = 0
    private var expectedPhysicalHeightPx = 0
    private var expectedDisplayRotation = -1
    private var expectedViewport: PlaybackViewport? = null
    private var tapDurationMs = DEFAULT_TAP_DURATION_MS

    fun start(arguments: Map<String, Any?>): Map<String, Any?> {
        cancelScheduling(clearPlan = false)
        val parsed = try {
            PlaybackPlan.from(arguments["plan"] as? Map<*, *>)
        } catch (error: IllegalArgumentException) {
            return error("invalid_plan", error.message ?: "演奏计划格式无效。")
        }
        val requestedId = (arguments["playbackId"] as? String)
            ?.takeIf(String::isNotBlank)
            ?: return error("invalid_playback_id", "缺少演奏会话 ID。")
        val requestedPosition = (arguments["positionMs"] as? Number)
            ?.toLong()
            ?.coerceIn(0L, parsed.totalDurationMs)
            ?: 0L
        val requestedSpeed = (arguments["speed"] as? Number)?.toDouble() ?: 1.0
        if (!requestedSpeed.isFinite() || requestedSpeed !in MIN_SPEED..MAX_SPEED) {
            return error("invalid_speed", "播放速度必须在 0.5 到 2.0 之间。")
        }
        val requestedTimingOffset = (arguments["timingOffsetMs"] as? Number)
            ?.toLong()
            ?.takeIf { it in MIN_TIMING_OFFSET_MS..MAX_TIMING_OFFSET_MS }
            ?: return error("invalid_timing_offset", "时序补偿必须在 -200ms 到 200ms 之间。")
        val orientation = (arguments["orientation"] as? String)
            ?.takeIf { it == "portrait" || it == "landscape" }
            ?: return error("invalid_orientation", "演奏计划缺少有效的屏幕方向。")
        val physicalWidthPx = (arguments["physicalWidthPx"] as? Number)
            ?.toInt()
            ?.takeIf { it > 0 }
            ?: return error("invalid_display", "演奏计划缺少有效的屏幕宽度。")
        val physicalHeightPx = (arguments["physicalHeightPx"] as? Number)
            ?.toInt()
            ?.takeIf { it > 0 }
            ?: return error("invalid_display", "演奏计划缺少有效的屏幕高度。")
        val displayRotation = (arguments["displayRotation"] as? Number)
            ?.toInt()
            ?.takeIf { it in 0..3 }
            ?: return error("invalid_display", "演奏计划缺少有效的屏幕旋转值。")
        val viewport = try {
            PlaybackViewport.from(
                arguments["viewportPx"] as? List<*>,
                physicalWidthPx,
                physicalHeightPx,
            )
        } catch (error: IllegalArgumentException) {
            return error("invalid_viewport", error.message ?: "校准可视区域无效。")
        }
        val requestedTapDuration = (arguments["tapDurationMs"] as? Number)
            ?.toLong()
            ?.coerceIn(MIN_TAP_DURATION_MS, MAX_TAP_DURATION_MS)
            ?: DEFAULT_TAP_DURATION_MS
        val nextActions = try {
            parsed.actionsFrom(requestedPosition)
        } catch (error: IllegalArgumentException) {
            return error("invalid_plan", error.message ?: "演奏计划触点分组无效。")
        }

        playbackId = requestedId
        plan = parsed
        playing = false
        originPlanMs = requestedPosition
        originRealtimeMs = 0L
        speed = requestedSpeed
        timingOffsetMs = requestedTimingOffset
        expectedOrientation = orientation
        expectedPhysicalWidthPx = physicalWidthPx
        expectedPhysicalHeightPx = physicalHeightPx
        expectedDisplayRotation = displayRotation
        expectedViewport = viewport
        tapDurationMs = requestedTapDuration

        val safetyError = validateExecutionTarget()
        if (safetyError != null) {
            clearSession()
            return safetyError
        }

        scheduledActions = nextActions
        nextActionIndex = 0
        playing = true
        originRealtimeMs = SystemClock.elapsedRealtime()
        val currentGeneration = generation
        scheduleNext(currentGeneration)
        Log.i(TAG, "start id=$requestedId from=${requestedPosition}ms actions=${scheduledActions.size}")
        return mapOf(
            "status" to "started",
            "playbackId" to requestedId,
            "positionMs" to requestedPosition,
        )
    }

    fun pause(): Map<String, Any?> {
        val currentPosition = currentPositionMs()
        cancelScheduling(clearPlan = false)
        originPlanMs = currentPosition
        originRealtimeMs = SystemClock.elapsedRealtime()
        playing = false
        return mapOf(
            "status" to "paused",
            "playbackId" to playbackId,
            "positionMs" to currentPosition,
        )
    }

    fun stop(notify: Boolean = false): Map<String, Any?> {
        val stoppedId = playbackId
        val stoppedPosition = currentPositionMs()
        val hadSession = plan != null
        cancelScheduling(clearPlan = true)
        Log.i(TAG, "stop id=$stoppedId")
        if (notify && hadSession) {
            AccessibilityPlaybackCoordinator.emit(
                mapOf(
                    "type" to "stopped",
                    "playbackId" to stoppedId,
                    "positionMs" to stoppedPosition,
                ),
            )
        }
        return mapOf(
            "status" to "stopped",
            "playbackId" to stoppedId,
            "positionMs" to stoppedPosition,
        )
    }

    fun state(): Map<String, Any?> = mapOf(
        "status" to if (playing) "playing" else if (plan != null) "paused" else "stopped",
        "playbackId" to playbackId,
        "positionMs" to currentPositionMs(),
        "foregroundPackage" to foregroundPackage(),
    )

    fun shutdown() {
        cancelScheduling(clearPlan = true)
    }

    private fun scheduleNext(expectedGeneration: Long) {
        if (!playing || expectedGeneration != generation) return
        // Android cancels an already-dispatched gesture when another one is
        // dispatched. Wait for the system callback even across generations so
        // a quick pause/restart cannot cancel the final tap from the old plan.
        if (inFlightGeneration != null) return
        if (nextActionIndex >= scheduledActions.size) {
            val remainingPlanMs = max(
                0L,
                (plan?.totalDurationMs ?: originPlanMs) - currentPositionMs(),
            )
            schedule(expectedGeneration, scaledDelay(remainingPlanMs)) {
                complete(expectedGeneration)
            }
            return
        }
        val action = scheduledActions[nextActionIndex]
        schedule(
            expectedGeneration,
            AccessibilityPlaybackTiming.delayUntilPlanTime(
                nowRealtimeMs = SystemClock.elapsedRealtime(),
                originRealtimeMs = originRealtimeMs,
                originPlanMs = originPlanMs,
                targetPlanMs = action.atMs,
                speed = speed,
                wallClockOffsetMs = timingOffsetMs,
            ),
        ) {
            if (!playing || expectedGeneration != generation) return@schedule
            val targetError = validateExecutionTarget()
            if (targetError != null) {
                fail(
                    code = targetError["errorCode"] as String,
                    message = targetError["message"] as String,
                    expectedGeneration = expectedGeneration,
                )
                return@schedule
            }
            if (!dispatch(action, expectedGeneration)) return@schedule
            nextActionIndex += 1
        }
    }

    private fun schedule(
        expectedGeneration: Long,
        delayMs: Long,
        callback: () -> Unit,
    ) {
        val runnable = Runnable {
            pendingRunnable = null
            if (expectedGeneration == generation) callback()
        }
        pendingRunnable = runnable
        handler.postDelayed(runnable, delayMs)
    }

    private fun dispatch(action: PlaybackAction, expectedGeneration: Long): Boolean {
        val viewport = expectedViewport
            ?: run {
                fail("invalid_viewport", "演奏会话缺少校准可视区域。", expectedGeneration)
                return false
            }
        val builder = GestureDescription.Builder()
        val gestureTapDuration =
            AccessibilityPlaybackTiming.tapDurationForGesture(tapDurationMs)
        val currentOverlayBounds = overlayBounds()
        try {
            for (point in action.points) {
                if (!viewport.contains(point.x, point.y)) {
                    fail("coordinate_out_of_bounds", "键位坐标超出校准可视区域。", expectedGeneration)
                    return false
                }
                if (currentOverlayBounds != null &&
                    point.x >= currentOverlayBounds.left &&
                    point.x < currentOverlayBounds.right &&
                    point.y >= currentOverlayBounds.top &&
                    point.y < currentOverlayBounds.bottom
                ) {
                    fail(
                        "coordinate_covered_by_overlay",
                        "键位坐标被播放器悬浮窗遮挡，请先移动悬浮窗。",
                        expectedGeneration,
                    )
                    return false
                }
                val path = Path().apply { moveTo(point.x, point.y) }
                builder.addStroke(
                    GestureDescription.StrokeDescription(
                        path,
                        scaledDelay(point.delayMs),
                        point.durationMs?.let { durationMs ->
                            max(1L, scaledDelay(durationMs))
                        } ?: gestureTapDuration,
                    ),
                )
            }
        } catch (error: IllegalArgumentException) {
            fail("gesture_build_failed", "无法构造触控手势：${error.message}", expectedGeneration)
            return false
        }

        inFlightGeneration = expectedGeneration
        val accepted = try {
            service.dispatchGesture(
                builder.build(),
                object : AccessibilityService.GestureResultCallback() {
                    override fun onCompleted(gestureDescription: GestureDescription?) {
                        finishGesture(expectedGeneration, cancelled = false)
                    }

                    override fun onCancelled(gestureDescription: GestureDescription?) {
                        finishGesture(expectedGeneration, cancelled = true)
                    }
                },
                handler,
            )
        } catch (error: Exception) {
            if (inFlightGeneration == expectedGeneration) {
                inFlightGeneration = null
            }
            fail(
                "gesture_dispatch_failed",
                "无法派发触控手势：${error.message ?: error.javaClass.simpleName}",
                expectedGeneration,
            )
            return false
        }
        if (!accepted) {
            if (inFlightGeneration == expectedGeneration) {
                inFlightGeneration = null
            }
            fail("gesture_rejected", "系统拒绝了触控手势。", expectedGeneration)
        }
        return accepted
    }

    private fun finishGesture(expectedGeneration: Long, cancelled: Boolean) {
        if (inFlightGeneration != expectedGeneration) return
        inFlightGeneration = null
        if (expectedGeneration == generation) {
            if (!playing) return
            if (cancelled) {
                fail("gesture_cancelled", "系统取消了触控手势。", expectedGeneration)
            } else {
                scheduleNext(expectedGeneration)
            }
            return
        }
        // pause/stop may have advanced the generation while the bounded tap was
        // finishing. A newer start waits here instead of cancelling that tap.
        if (playing) scheduleNext(generation)
    }

    private fun complete(expectedGeneration: Long) {
        if (expectedGeneration != generation || !playing) return
        val completedId = playbackId
        playing = false
        originPlanMs = plan?.totalDurationMs ?: originPlanMs
        originRealtimeMs = SystemClock.elapsedRealtime()
        pendingRunnable = null
        AccessibilityPlaybackCoordinator.emit(
            mapOf(
                "type" to "completed",
                "playbackId" to completedId,
                "positionMs" to originPlanMs,
            ),
        )
    }

    private fun fail(code: String, message: String, expectedGeneration: Long) {
        if (expectedGeneration != generation) return
        val failedId = playbackId
        val failedPosition = currentPositionMs()
        cancelScheduling(clearPlan = false)
        originPlanMs = failedPosition
        originRealtimeMs = SystemClock.elapsedRealtime()
        playing = false
        Log.e(TAG, "failure id=$failedId code=$code message=$message")
        AccessibilityPlaybackCoordinator.emit(
            mapOf(
                "type" to "error",
                "playbackId" to failedId,
                "errorCode" to code,
                "message" to message,
                "positionMs" to failedPosition,
            ),
        )
    }

    private fun validateExecutionTarget(): Map<String, Any?>? {
        if (calibrationActive()) {
            return error("calibration_active", "请先结束当前键位校准。")
        }
        val actualOrientation = when (service.resources.configuration.orientation) {
            Configuration.ORIENTATION_LANDSCAPE -> "landscape"
            Configuration.ORIENTATION_PORTRAIT -> "portrait"
            else -> null
        }
        if (actualOrientation == null || actualOrientation != expectedOrientation) {
            return error("orientation_mismatch", "当前屏幕方向与键位校准不一致。")
        }
        val display = CalibrationPlatformSupport.displayInfo(service)
        if (display.widthPx != expectedPhysicalWidthPx ||
            display.heightPx != expectedPhysicalHeightPx ||
            display.rotation != expectedDisplayRotation
        ) {
            return error("display_mismatch", "当前屏幕尺寸或旋转与键位校准不一致。")
        }
        return null
    }

    private fun currentPositionMs(): Long {
        val currentPlan = plan ?: return 0L
        if (!playing) return originPlanMs.coerceIn(0L, currentPlan.totalDurationMs)
        val elapsed = max(0L, SystemClock.elapsedRealtime() - originRealtimeMs)
        return (originPlanMs + elapsed * speed)
            .roundToLong()
            .coerceIn(0L, currentPlan.totalDurationMs)
    }

    private fun scaledDelay(planDurationMs: Long): Long =
        max(0L, (planDurationMs / speed).roundToLong())

    private fun cancelScheduling(clearPlan: Boolean) {
        generation += 1
        pendingRunnable?.let(handler::removeCallbacks)
        pendingRunnable = null
        playing = false
        if (clearPlan) clearSession()
    }

    private fun clearSession() {
        plan = null
        scheduledActions = emptyList()
        nextActionIndex = 0
        playbackId = null
        originPlanMs = 0L
        originRealtimeMs = 0L
        expectedOrientation = null
        expectedPhysicalWidthPx = 0
        expectedPhysicalHeightPx = 0
        expectedDisplayRotation = -1
        expectedViewport = null
        timingOffsetMs = 0L
    }

    private fun error(code: String, message: String): Map<String, Any?> = mapOf(
        "status" to "error",
        "errorCode" to code,
        "message" to message,
    )

    internal data class PlaybackPoint(
        val x: Float,
        val y: Float,
        val delayMs: Long,
        val durationMs: Long? = null,
    )

    private data class PlaybackViewport(
        val left: Float,
        val top: Float,
        val right: Float,
        val bottom: Float,
    ) {
        fun contains(x: Float, y: Float): Boolean =
            x >= left && y >= top && x < right && y < bottom

        companion object {
            fun from(raw: List<*>?, widthPx: Int, heightPx: Int): PlaybackViewport {
                require(raw?.size == 4) { "校准可视区域格式无效。" }
                val values = raw.map {
                    (it as? Number)?.toFloat()
                        ?: throw IllegalArgumentException("校准可视区域坐标无效。")
                }
                require(values.all(Float::isFinite)) { "校准可视区域坐标无效。" }
                val viewport = PlaybackViewport(
                    left = values[0],
                    top = values[1],
                    right = values[2],
                    bottom = values[3],
                )
                require(
                    viewport.left >= 0f &&
                        viewport.top >= 0f &&
                        viewport.right <= widthPx.toFloat() &&
                        viewport.bottom <= heightPx.toFloat() &&
                        viewport.left < viewport.right &&
                        viewport.top < viewport.bottom,
                ) { "校准可视区域超出屏幕范围。" }
                return viewport
            }
        }
    }

    internal data class PlaybackAction(
        val atMs: Long,
        val points: List<PlaybackPoint>,
    )

    internal data class PlaybackPlan(
        val totalDurationMs: Long,
        val actions: List<PlaybackAction>,
    ) {
        /**
         * Trims a plan for seek/resume while retaining every compiler action
         * as one Android gesture descriptor. The compiler deliberately uses
         * point delays inside a short batch; flattening those delays into
         * separate descriptors makes sub-tap-duration notes wait for the
         * previous dispatch callback and drift late.
         */
        fun actionsFrom(positionMs: Long): List<PlaybackAction> {
            val result = mutableListOf<PlaybackAction>()
            for (action in actions) {
                val retained = action.points.mapNotNull { point ->
                    val absoluteStart = action.atMs + point.delayMs
                    if (absoluteStart < positionMs) {
                        null
                    } else {
                        absoluteStart to point
                    }
                }
                if (retained.isEmpty()) continue
                val rebasedAtMs = retained.minOf { it.first }
                result += PlaybackAction(
                    atMs = rebasedAtMs,
                    points = retained.map { (absoluteStart, point) ->
                        point.copy(delayMs = absoluteStart - rebasedAtMs)
                    },
                )
            }
            return result
        }

        companion object {
            fun from(raw: Map<*, *>?): PlaybackPlan {
                require(raw != null) { "缺少演奏计划。" }
                require(raw["backendId"] == "android-accessibility") {
                    "演奏计划 backendId 无效。"
                }
                val totalDurationMs = (raw["totalDurationMs"] as? Number)?.toLong()
                    ?: throw IllegalArgumentException("缺少计划总时长。")
                require(totalDurationMs in 0L..MAX_PLAN_DURATION_MS) { "计划总时长无效。" }
                val rawActions = raw["actions"] as? List<*>
                    ?: throw IllegalArgumentException("缺少计划动作。")
                require(rawActions.size <= MAX_ACTION_COUNT) { "计划动作数量过多。" }
                var previousAtMs = -1L
                val actions = rawActions.map { rawAction ->
                    val map = rawAction as? Map<*, *>
                        ?: throw IllegalArgumentException("计划动作格式无效。")
                    val kind = map["kind"] as? String
                    require(kind == "touchPoints" || kind == "touchGesture") {
                        "当前执行器仅支持 touchPoints 或 touchGesture。"
                    }
                    val atMs = (map["atMs"] as? Number)?.toLong()
                        ?: throw IllegalArgumentException("动作时间无效。")
                    require(atMs >= previousAtMs && atMs <= totalDurationMs) {
                        "计划动作时间未排序或超出总时长。"
                    }
                    previousAtMs = atMs
                    val payload = map["payload"] as? Map<*, *>
                        ?: throw IllegalArgumentException("动作 payload 无效。")
                    require(payload["calibrated"] == true) { "动作尚未完成坐标校准。" }
                    val rawPoints = payload["points"] as? List<*>
                        ?: throw IllegalArgumentException("动作缺少触点。")
                    require(rawPoints.isNotEmpty() && rawPoints.size <= MAX_POINT_COUNT) {
                        "单次动作触点数量无效。"
                    }
                    val points = rawPoints.map { rawPoint ->
                        val point = rawPoint as? Map<*, *>
                            ?: throw IllegalArgumentException("触点格式无效。")
                        val x = (point["x"] as? Number)?.toFloat()
                            ?: throw IllegalArgumentException("触点 X 坐标无效。")
                        val y = (point["y"] as? Number)?.toFloat()
                            ?: throw IllegalArgumentException("触点 Y 坐标无效。")
                        val delayMs = (point["delayMs"] as? Number)?.toLong()
                            ?: throw IllegalArgumentException("触点延迟无效。")
                        val durationMs = if (kind == "touchGesture") {
                            (point["durationMs"] as? Number)?.toLong()
                                ?: throw IllegalArgumentException("长按触点时长无效。")
                        } else {
                            null
                        }
                        require(x.isFinite() && y.isFinite() && delayMs >= 0L) {
                            "触点坐标或延迟无效。"
                        }
                        val maximumDelayMs = if (kind == "touchGesture") {
                            MAX_GESTURE_SPAN_MS
                        } else {
                            MAX_BATCH_POINT_DELAY_MS
                        }
                        require(delayMs <= maximumDelayMs) {
                            "单次动作触点延迟超过安全上限。"
                        }
                        if (durationMs != null) {
                            require(durationMs in MIN_HOLD_DURATION_MS..MAX_HOLD_DURATION_MS) {
                                "长按触点时长超过安全上限。"
                            }
                            require(delayMs + durationMs <= MAX_GESTURE_SPAN_MS) {
                                "长按动作总时长超过安全上限。"
                            }
                        }
                        require(atMs + delayMs <= totalDurationMs) { "触点超出计划总时长。" }
                        PlaybackPoint(
                            x = x,
                            y = y,
                            delayMs = delayMs,
                            durationMs = durationMs,
                        )
                    }
                    PlaybackAction(atMs = atMs, points = points)
                }
                return PlaybackPlan(totalDurationMs = totalDurationMs, actions = actions)
            }
        }
    }

    private companion object {
        const val TAG = "LxPlaybackExecutor"
        const val MAX_ACTION_COUNT = 100_000
        const val MAX_POINT_COUNT = 10
        const val MAX_PLAN_DURATION_MS = 6L * 60L * 60L * 1000L
        const val MIN_SPEED = 0.5
        const val MAX_SPEED = 2.0
        const val MIN_TIMING_OFFSET_MS = -200L
        const val MAX_TIMING_OFFSET_MS = 200L
        const val MIN_TAP_DURATION_MS = 5L
        const val DEFAULT_TAP_DURATION_MS = 12L
        const val MAX_TAP_DURATION_MS = 80L
        const val MAX_BATCH_POINT_DELAY_MS = 32L
        const val MIN_HOLD_DURATION_MS = 5L
        const val MAX_HOLD_DURATION_MS = 10_000L
        const val MAX_GESTURE_SPAN_MS = 30_000L
    }
}

/** Pure timing helpers kept separate from Android clock access for unit tests. */
internal object AccessibilityPlaybackTiming {
    fun delayUntilPlanTime(
        nowRealtimeMs: Long,
        originRealtimeMs: Long,
        originPlanMs: Long,
        targetPlanMs: Long,
        speed: Double,
        wallClockOffsetMs: Long,
    ): Long {
        val planDeltaMs = max(0L, targetPlanMs - originPlanMs)
        val scaledPlanDeltaMs = (planDeltaMs / speed).roundToLong()
        val targetRealtimeMs = originRealtimeMs + scaledPlanDeltaMs + wallClockOffsetMs
        return max(0L, targetRealtimeMs - nowRealtimeMs)
    }

    /** Tap duration is a physical device duration and is independent of speed. */
    fun tapDurationForGesture(requestedTapDurationMs: Long): Long =
        max(1L, requestedTapDurationMs)
}

internal object AccessibilityPlaybackSafety {
    fun calibrationActive(
        hasSession: Boolean,
        hasCompactOverlay: Boolean,
        hasFullOverlay: Boolean,
    ): Boolean = hasSession || hasCompactOverlay || hasFullOverlay
}
