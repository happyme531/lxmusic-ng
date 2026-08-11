package dev.happyme531.clxmidiplayer.ng

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.view.Gravity
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.view.WindowInsets
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.view.animation.DecelerateInterpolator
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterSurfaceView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.roundToInt

internal class PlayerOverlayHost(
    private val service: LxMusicAccessibilityService,
    private val windowManager: WindowManager,
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var flutterEngine: FlutterEngine? = null
    private var flutterView: FlutterView? = null
    private var controlChannel: MethodChannel? = null
    private var layoutParams: WindowManager.LayoutParams? = null
    private var session: Map<String, Any?> = defaultSession()
    private var resizeModeEnabled = false
    private var targetPickerActive = false
    private var windowAttached = false
    private var windowMode = WindowMode.compact
    private var dockedSide: DockSide? = null
    private var preDockWindowState: RestorableWindowState? = null
    private var requestedWidthDp = COMPACT_WIDTH_DP
    private var requestedHeightDp = COMPACT_HEIGHT_DP
    private var resizeAnimator: ValueAnimator? = null
    private var lifecycleGeneration = 0L
    private var pendingHide: Runnable? = null

    fun show(arguments: Map<String, Any?>): Map<String, Any?> {
        lifecycleGeneration += 1
        cancelPendingHide()
        session = parseSession(arguments)
        if (isVisible()) {
            controlChannel?.invokeMethod("updateSession", session)
            return mapOf("status" to "updated")
        }

        // A failed/aborted initialization must not leave an engine around for
        // the next show request to accidentally reuse.
        if (flutterEngine != null || flutterView != null || controlChannel != null) {
            releaseCurrentContent()
        }

        val density = service.resources.displayMetrics.density
        requestedWidthDp = COMPACT_WIDTH_DP
        requestedHeightDp = COMPACT_HEIGHT_DP
        windowMode = WindowMode.compact
        resizeModeEnabled = false
        targetPickerActive = false
        dockedSide = null
        preDockWindowState = null
        val safeBounds = normalWindowBounds()
        val width = dp(COMPACT_WIDTH_DP, density).coerceAtMost(safeBounds.width())
        val height = dp(COMPACT_HEIGHT_DP, density).coerceAtMost(safeBounds.height())
        val params = WindowManager.LayoutParams(
            width,
            height,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = (safeBounds.centerX() - width / 2).coerceIn(
                safeBounds.left,
                max(safeBounds.left, safeBounds.right - width),
            )
            y = (safeBounds.top + dp(64f, density)).coerceIn(
                safeBounds.top,
                max(safeBounds.top, safeBounds.bottom - height),
            )
            setTitle("LxMusic player overlay")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }

        var engine: FlutterEngine? = null
        var view: FlutterView? = null
        var channel: MethodChannel? = null
        var viewAdded = false
        try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(service.applicationContext)
            loader.ensureInitializationComplete(service.applicationContext, null)

            engine = FlutterEngine(service.applicationContext)
            channel = MethodChannel(
                engine.dartExecutor.binaryMessenger,
                CONTROL_CHANNEL,
            ).also { it.setMethodCallHandler(::handleControlCall) }
            val surface = FlutterSurfaceView(service, true)
            view = FlutterView(service, surface).apply {
                setBackgroundColor(Color.TRANSPARENT)
                attachToFlutterEngine(engine)
            }
            installNativeDragHandler(view)

            flutterEngine = engine
            flutterView = view
            controlChannel = channel
            layoutParams = params

            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(
                    loader.findAppBundlePath(),
                    DART_ENTRYPOINT,
                ),
            )
            engine.lifecycleChannel.appIsResumed()
            windowManager.addView(view, params)
            viewAdded = true
            windowAttached = true
            clampAndUpdate(updateWindow = false)
        } catch (error: Exception) {
            if (view != null && (viewAdded || view.isAttachedToWindow)) {
                removeView(view)
            }
            clearCurrentReferences(engine, view, channel)
            disposeFlutterContent(engine, view, channel)
            return mapOf(
                "status" to "error",
                "message" to
                    "无法创建播放器悬浮窗：${error.message ?: error.javaClass.simpleName}",
            )
        }
        return mapOf("status" to "shown")
    }

    fun hide() {
        lifecycleGeneration += 1
        cancelPendingHide()
        releaseCurrentContent()
    }

    fun snapshotSession(): Map<String, Any?> = HashMap(session)

    fun updateSession(arguments: Map<String, Any?>) {
        session = parseSession(arguments)
        if (isVisible()) {
            controlChannel?.invokeMethod("updateSession", session)
        }
    }

    fun updateFromPlaybackEvent(event: Map<String, Any?>) {
        val type = event["type"] as? String ?: return
        if (type !in TERMINAL_PLAYBACK_EVENTS) return
        session = session + buildMap<String, Any?> {
            put("isPlaying", false)
            put("playbackStatus", type)
            (event["positionMs"] as? Number)?.toLong()?.let {
                put("positionMs", it)
            }
            if (type == "error") {
                put("playbackError", event["message"] as? String ?: "自动演奏已停止。")
            }
        }
        if (isVisible()) {
            controlChannel?.invokeMethod("updateSession", session)
        }
    }

    fun isVisible(): Boolean =
        windowAttached && flutterView != null && layoutParams != null

    fun currentBoundsPx(): Rect? {
        val view = flutterView ?: return null
        if (!isVisible()) return null
        val location = IntArray(2)
        view.getLocationOnScreen(location)
        val width = view.width.takeIf { it > 0 } ?: layoutParams?.width ?: return null
        val height = view.height.takeIf { it > 0 } ?: layoutParams?.height ?: return null
        if (width <= 0 || height <= 0) return null
        return Rect(location[0], location[1], location[0] + width, location[1] + height)
    }

    fun onConfigurationChanged() {
        if (isVisible()) {
            animateToRequestedSize()
        }
    }

    private fun handleControlCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getInitialSession" -> result.success(session)
            "resize" -> {
                val arguments = call.arguments as? Map<*, *>
                val widthDp = (arguments?.get("widthDp") as? Number)?.toFloat()
                val heightDp = (arguments?.get("heightDp") as? Number)?.toFloat()
                if (widthDp == null || heightDp == null) {
                    result.error("invalid_size", "悬浮窗尺寸无效。", null)
                    return
                }
                if (!widthDp.isFinite() || !heightDp.isFinite() || widthDp <= 0 || heightDp <= 0) {
                    result.error("invalid_size", "悬浮窗尺寸无效。", null)
                    return
                }
                var replied = false
                resize(widthDp, heightDp) { outcome ->
                    if (!replied) {
                        replied = true
                        when (outcome) {
                            ResizeOutcome.completed -> result.success(null)
                            ResizeOutcome.cancelled -> result.error(
                                "resize_cancelled",
                                "悬浮窗尺寸动画已取消。",
                                null,
                            )
                        }
                    }
                }
            }
            "moveBy" -> {
                val arguments = call.arguments as? Map<*, *>
                val deltaX = (arguments?.get("deltaX") as? Number)?.toFloat()
                val deltaY = (arguments?.get("deltaY") as? Number)?.toFloat()
                if (deltaX == null || deltaY == null) {
                    result.error("invalid_delta", "悬浮窗移动距离无效。", null)
                    return
                }
                if (!deltaX.isFinite() || !deltaY.isFinite()) {
                    result.error("invalid_delta", "悬浮窗移动距离无效。", null)
                    return
                }
                moveBy(deltaX, deltaY)
                result.success(null)
            }
            "setResizeMode" -> {
                val arguments = call.arguments as? Map<*, *>
                resizeModeEnabled =
                    arguments?.get("enabled") == true && windowMode == WindowMode.expanded
                result.success(null)
            }
            "setTargetPickerActive" -> {
                val arguments = call.arguments as? Map<*, *>
                setTargetPickerActive(arguments?.get("active") == true)
                result.success(null)
            }
            "playerAction" -> {
                val arguments = call.arguments as? Map<*, *>
                if (arguments == null) {
                    result.error("invalid_action", "播放器操作格式无效。", null)
                    return
                }
                val action = arguments.entries.associate { (key, value) ->
                    key.toString() to value
                }
                handlePlayerAction(action, result)
            }
            "close" -> {
                LxMusicAccessibilityService.stopPlayback(notify = true)
                result.success(null)
                scheduleHide()
            }
            else -> result.notImplemented()
        }
    }

    private fun handlePlayerAction(
        action: Map<String, Any?>,
        result: MethodChannel.Result,
    ) {
        val actionType = action["type"] as? String
        if (actionType == null) {
            result.error("invalid_action", "播放器操作缺少类型。", null)
            return
        }
        val dispatchedAction = action + (
            "deadlineUnixMs" to System.currentTimeMillis() + PLAYER_ACTION_TIMEOUT_MS
        )
        val localFallback = applyLocalPlaybackSafety(actionType, action)
        if (localFallback == null) {
            PlayerOverlayCoordinator.dispatch(dispatchedAction, result)
            return
        }
        PlayerOverlayCoordinator.dispatch(
            dispatchedAction,
            object : MethodChannel.Result {
                override fun success(value: Any?) {
                    result.success(value)
                }

                override fun error(code: String, message: String?, details: Any?) {
                    if (code in LOCAL_FALLBACK_ERROR_CODES) {
                        result.success(localFallback)
                    } else {
                        result.error(code, message, details)
                    }
                }

                override fun notImplemented() {
                    result.success(localFallback)
                }
            },
        )
    }

    /**
     * Applies the native safety boundary before asking the primary Flutter
     * engine to update library/player state. The returned snapshot is only used
     * when that engine is unavailable; it must never claim playback is still
     * active after native gesture scheduling has been stopped or paused.
     */
    private fun applyLocalPlaybackSafety(
        actionType: String,
        action: Map<String, Any?>,
    ): Map<String, Any?>? {
        val nativeState = LxMusicAccessibilityService.playbackState()
        val isPlaying = session["isPlaying"] == true || nativeState["status"] == "playing"
        return when (actionType) {
            "prepareTargetSelection" -> {
                val paused = LxMusicAccessibilityService.pausePlayback()
                updateLocalPlaybackSession(
                    isPlaying = false,
                    positionMs = (paused["positionMs"] as? Number)?.toLong(),
                )
            }
            "selectTarget" -> {
                LxMusicAccessibilityService.stopPlayback()
                null
            }
            "togglePlayback" -> {
                if (!isPlaying) return null
                val paused = LxMusicAccessibilityService.pausePlayback()
                updateLocalPlaybackSession(
                    isPlaying = false,
                    positionMs = (paused["positionMs"] as? Number)?.toLong(),
                )
            }
            "stop" -> {
                LxMusicAccessibilityService.stopPlayback()
                updateLocalPlaybackSession(isPlaying = false, positionMs = 0L)
            }
            "seek", "position" -> {
                LxMusicAccessibilityService.pausePlayback()
                val durationMs = (session["durationMs"] as? Number)?.toLong()?.coerceAtLeast(0L)
                val requested = (action["positionMs"] as? Number)?.toLong()
                val positionMs = if (requested != null && durationMs != null) {
                    requested.coerceIn(0L, durationMs)
                } else {
                    requested
                }
                updateLocalPlaybackSession(isPlaying = false, positionMs = positionMs)
            }
            "setSpeed" -> {
                LxMusicAccessibilityService.pausePlayback()
                val requestedSpeed = (action["speed"] as? Number)?.toDouble()
                updateLocalPlaybackSession(
                    isPlaying = false,
                    speed = requestedSpeed?.coerceIn(0.5, 2.0),
                )
            }
            "setTranspose" -> {
                LxMusicAccessibilityService.pausePlayback()
                val transpose = (action["transpose"] as? Number)?.toInt()?.coerceIn(-24, 24)
                updateLocalPlaybackSession(
                    isPlaying = false,
                    extra = mapOf("transpose" to transpose),
                )
            }
            "setTimingOffset" -> {
                LxMusicAccessibilityService.pausePlayback()
                val offset = (action["timingOffsetMs"] as? Number)?.toInt()?.coerceIn(-200, 200)
                updateLocalPlaybackSession(
                    isPlaying = false,
                    extra = mapOf("timingOffsetMs" to offset),
                )
            }
            "setTouchDuration" -> {
                LxMusicAccessibilityService.pausePlayback()
                val percent = (action["touchDurationPercent"] as? Number)
                    ?.toInt()
                    ?.coerceIn(40, 120)
                updateLocalPlaybackSession(
                    isPlaying = false,
                    extra = mapOf("touchDurationPercent" to percent),
                )
            }
            "setDurationMode" -> {
                LxMusicAccessibilityService.pausePlayback()
                val durationMode = (action["durationMode"] as? String)
                    ?.takeIf(DURATION_MODES::contains)
                updateLocalPlaybackSession(
                    isPlaying = false,
                    extra = mapOf("durationMode" to durationMode),
                )
            }
            "previous", "next", "selectTrack" -> {
                LxMusicAccessibilityService.stopPlayback()
                updateLocalPlaybackSession(isPlaying = false, positionMs = 0L)
            }
            else -> null
        }
    }

    private fun updateLocalPlaybackSession(
        isPlaying: Boolean,
        positionMs: Long? = null,
        speed: Double? = null,
        extra: Map<String, Any?> = emptyMap(),
    ): Map<String, Any?> {
        session = session + buildMap<String, Any?> {
            put("isPlaying", isPlaying)
            if (positionMs != null) put("positionMs", positionMs)
            if (speed != null) put("speed", speed)
            for ((key, value) in extra) {
                if (value != null) put(key, value)
            }
        }
        return session
    }

    private fun resize(
        widthDp: Float,
        heightDp: Float,
        onComplete: (ResizeOutcome) -> Unit,
    ) {
        resizeModeEnabled = false
        val nextMode = modeForSize(widthDp, heightDp)
        if (nextMode == WindowMode.edgeDocked && windowMode != WindowMode.edgeDocked) {
            rememberPreDockWindowState()
        }
        windowMode = nextMode
        when (nextMode) {
            WindowMode.edgeDocked -> {
                requestedWidthDp = EDGE_DOCKED_WIDTH_DP
                requestedHeightDp = MINI_HEIGHT_DP
                if (dockedSide == null) {
                    dockedSide = nearestDockSide()
                }
            }
            WindowMode.mini -> {
                requestedWidthDp = MINI_WIDTH_DP
                requestedHeightDp = MINI_HEIGHT_DP
                dockedSide = null
                preDockWindowState = null
            }
            WindowMode.compact -> {
                requestedWidthDp = widthDp.coerceIn(MIN_NORMAL_WIDTH_DP, MAX_WIDTH_DP)
                requestedHeightDp = heightDp.coerceIn(MIN_NORMAL_HEIGHT_DP, MAX_HEIGHT_DP)
                dockedSide = null
                preDockWindowState = null
            }
            WindowMode.expanded -> {
                requestedWidthDp = widthDp.coerceIn(MIN_NORMAL_WIDTH_DP, MAX_WIDTH_DP)
                requestedHeightDp = heightDp.coerceIn(MIN_NORMAL_HEIGHT_DP, MAX_HEIGHT_DP)
                dockedSide = null
                preDockWindowState = null
            }
        }
        animateToRequestedSize(onComplete)
    }

    private fun moveBy(deltaXDp: Float, deltaYDp: Float) {
        if (resizeModeEnabled) return
        val params = layoutParams ?: return
        val density = service.resources.displayMetrics.density
        cancelResizeAnimation()
        params.x += dp(deltaXDp, density)
        params.y += dp(deltaYDp, density)
        clampAndUpdate(updateWindow = true)
    }

    private fun installNativeDragHandler(view: FlutterView) {
        val density = service.resources.displayMetrics.density
        val touchSlop = ViewConfiguration.get(service).scaledTouchSlop.toFloat()
        var dragging = false
        var resizing = false
        var downRawX = 0f
        var downRawY = 0f
        var downWindowX = 0
        var downWindowY = 0
        var downWindowWidth = 0
        var downWindowHeight = 0

        view.setOnTouchListener { _, event ->
            val params = layoutParams ?: return@setOnTouchListener false
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    if (resizeModeEnabled && isResizeHandle(event.x, event.y, params, density)) {
                        cancelResizeAnimation()
                        resizing = true
                        downRawX = event.rawX
                        downRawY = event.rawY
                        downWindowWidth = params.width
                        downWindowHeight = params.height
                        return@setOnTouchListener true
                    }
                    if (resizeModeEnabled || !isDragHandle(event.x, density)) {
                        return@setOnTouchListener false
                    }
                    cancelResizeAnimation()
                    dragging = true
                    downRawX = event.rawX
                    downRawY = event.rawY
                    downWindowX = params.x
                    downWindowY = params.y
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    if (resizing) {
                        resizeFromGesture(
                            params = params,
                            downWidth = downWindowWidth,
                            downHeight = downWindowHeight,
                            deltaX = event.rawX - downRawX,
                            deltaY = event.rawY - downRawY,
                        )
                        return@setOnTouchListener true
                    }
                    if (!dragging) return@setOnTouchListener false
                    if (windowMode != WindowMode.edgeDocked) {
                        params.x = downWindowX + (event.rawX - downRawX).roundToInt()
                    }
                    params.y = downWindowY + (event.rawY - downRawY).roundToInt()
                    clampAndUpdate(updateWindow = true)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (resizing) {
                        resizing = false
                        return@setOnTouchListener true
                    }
                    if (!dragging) return@setOnTouchListener false
                    val moved = hypot(event.rawX - downRawX, event.rawY - downRawY)
                    dragging = false
                    if (moved <= touchSlop) {
                        handleDragHandleClick()
                    } else if (windowMode != WindowMode.edgeDocked) {
                        dockIfNearEdge()
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    if (resizing) {
                        resizing = false
                        return@setOnTouchListener true
                    }
                    if (!dragging) return@setOnTouchListener false
                    dragging = false
                    true
                }
                else -> resizing || dragging
            }
        }
    }

    private fun isResizeHandle(
        localX: Float,
        localY: Float,
        params: WindowManager.LayoutParams,
        density: Float,
    ): Boolean {
        if (windowMode != WindowMode.expanded || targetPickerActive) return false
        val handleSize = dp(RESIZE_HANDLE_SIZE_DP, density)
        return localX >= params.width - handleSize && localY >= params.height - handleSize
    }

    private fun resizeFromGesture(
        params: WindowManager.LayoutParams,
        downWidth: Int,
        downHeight: Int,
        deltaX: Float,
        deltaY: Float,
    ) {
        val view = flutterView ?: return
        if (downWidth <= 0 || downHeight <= 0) return
        val density = service.resources.displayMetrics.density
        val bounds = normalWindowBounds()
        val minWidth = dp(RESIZE_MIN_WIDTH_DP, density)
        val minHeight = dp(RESIZE_MIN_HEIGHT_DP, density)
        val maxWidth = minOf(
            dp(MAX_WIDTH_DP, density),
            (bounds.right - params.x).coerceAtLeast(minWidth),
        )
        val maxHeight = minOf(
            dp(MAX_HEIGHT_DP, density),
            (bounds.bottom - params.y).coerceAtLeast(minHeight),
        )
        params.width = (downWidth + deltaX).roundToInt().coerceIn(minWidth, maxWidth)
        params.height = (downHeight + deltaY).roundToInt().coerceIn(minHeight, maxHeight)
        requestedWidthDp = params.width / density
        requestedHeightDp = params.height / density
        updateViewLayout(view, params)
    }

    private fun isDragHandle(
        localX: Float,
        density: Float,
    ): Boolean {
        if (targetPickerActive) return false
        return when (windowMode) {
            WindowMode.edgeDocked -> true
            WindowMode.mini -> localX >= dp(MINI_HANDLE_START_DP, density)
            WindowMode.compact,
            WindowMode.expanded,
            -> localX <= dp(COMPACT_HANDLE_END_DP, density)
        }
    }

    private fun setTargetPickerActive(active: Boolean) {
        targetPickerActive = active
        val view = flutterView ?: return
        val params = layoutParams ?: return
        params.flags = if (active) {
            params.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv()
        } else {
            params.flags or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
        }
        params.softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING
        if (active) {
            view.isFocusableInTouchMode = true
            view.requestFocus()
        } else {
            view.clearFocus()
            val inputMethodManager = service.getSystemService(InputMethodManager::class.java)
            inputMethodManager?.hideSoftInputFromWindow(view.windowToken, 0)
        }
        updateViewLayout(view, params)
    }

    private fun handleDragHandleClick() {
        when (windowMode) {
            WindowMode.edgeDocked -> undockToPrevious()
            WindowMode.mini -> sendOverlayCommand("expandFromMini")
            WindowMode.compact -> sendOverlayCommand("collapseToMini")
            WindowMode.expanded -> sendOverlayCommand("collapseToMini")
        }
    }

    private fun dockIfNearEdge() {
        val params = layoutParams ?: return
        val bounds = normalWindowBounds()
        val threshold = dp(DOCK_THRESHOLD_DP, service.resources.displayMetrics.density)
        val leftDistance = params.x - bounds.left
        val rightDistance = bounds.right - (params.x + params.width)
        val side = when {
            leftDistance <= threshold && leftDistance <= rightDistance -> DockSide.left
            rightDistance <= threshold -> DockSide.right
            else -> return
        }

        rememberPreDockWindowState()
        dockedSide = side
        windowMode = WindowMode.edgeDocked
        requestedWidthDp = EDGE_DOCKED_WIDTH_DP
        requestedHeightDp = MINI_HEIGHT_DP
        val expectedGeneration = lifecycleGeneration
        // Shrinking is content-first: Dart swaps to the edge affordance before
        // the host starts reducing the surface.
        sendOverlayCommand(
            command = "dockToEdge",
            extras = mapOf("side" to side.name),
        ) {
            mainHandler.postDelayed(
                {
                    if (
                        lifecycleGeneration == expectedGeneration &&
                        isVisible() &&
                        windowMode == WindowMode.edgeDocked &&
                        dockedSide == side
                    ) {
                        animateToRequestedSize()
                    }
                },
                DOCK_CONTENT_FRAME_DELAY_MS,
            )
        }
    }

    private fun rememberPreDockWindowState() {
        if (windowMode == WindowMode.edgeDocked || preDockWindowState != null) return
        preDockWindowState = RestorableWindowState(
            widthDp = requestedWidthDp,
            heightDp = requestedHeightDp,
            mode = windowMode,
        )
    }

    private fun undockToPrevious() {
        if (windowMode != WindowMode.edgeDocked) return
        val restore = preDockWindowState ?: RestorableWindowState(
            widthDp = COMPACT_WIDTH_DP,
            heightDp = COMPACT_HEIGHT_DP,
            mode = WindowMode.compact,
        )
        windowMode = restore.mode
        requestedWidthDp = restore.widthDp
        requestedHeightDp = restore.heightDp
        dockedSide = null
        preDockWindowState = null
        // Expanding is window-first so the restored controls never have to lay
        // out inside the 44dp edge surface.
        animateToRequestedSize { outcome ->
            if (outcome == ResizeOutcome.completed) {
                sendOverlayCommand("undockToPrevious")
            }
        }
    }

    private fun sendOverlayCommand(
        command: String,
        extras: Map<String, Any?> = emptyMap(),
        onDelivered: (() -> Unit)? = null,
    ) {
        val channel = controlChannel
        if (channel == null) {
            onDelivered?.invoke()
            return
        }
        var delivered = false
        fun finishDelivery() {
            if (delivered) return
            delivered = true
            onDelivered?.invoke()
        }
        try {
            channel.invokeMethod(
                "updateSession",
                mapOf("command" to command) + extras,
                if (onDelivered == null) {
                    null
                } else {
                    object : MethodChannel.Result {
                        override fun success(result: Any?) = finishDelivery()

                        override fun error(
                            errorCode: String,
                            errorMessage: String?,
                            errorDetails: Any?,
                        ) = finishDelivery()

                        override fun notImplemented() = finishDelivery()
                    }
                },
            )
        } catch (_: Exception) {
            // The Dart isolate may be detaching while the native gesture ends.
            finishDelivery()
        }
    }

    private fun clampAndUpdate(updateWindow: Boolean) {
        val view = flutterView ?: return
        val params = layoutParams ?: return
        val bounds = normalWindowBounds()
        val safeBounds = safeWindowBounds()
        params.width = params.width.coerceAtMost(bounds.width())
        params.height = params.height.coerceAtMost(bounds.height())
        params.x = dockedX(params, safeBounds) ?: params.x.coerceIn(
            bounds.left,
            max(bounds.left, bounds.right - params.width),
        )
        params.y = params.y.coerceIn(
            bounds.top,
            max(bounds.top, bounds.bottom - params.height),
        )
        if (!updateWindow) return
        updateViewLayout(view, params)
    }

    private fun animateToRequestedSize(
        onComplete: (ResizeOutcome) -> Unit = { _ -> },
    ) {
        val view = flutterView
        val params = layoutParams
        if (!windowAttached || view == null || params == null) {
            onComplete(ResizeOutcome.cancelled)
            return
        }

        val bounds = normalWindowBounds()
        val safeBounds = safeWindowBounds()
        val density = service.resources.displayMetrics.density
        val targetWidth = dp(requestedWidthDp, density)
            .coerceAtLeast(1)
            .coerceAtMost(bounds.width())
        val targetHeight = dp(requestedHeightDp, density)
            .coerceAtLeast(1)
            .coerceAtMost(bounds.height())
        val centerX = params.x + params.width / 2f
        val centerY = params.y + params.height / 2f
        val targetX = dockedX(targetWidth, safeBounds) ?: (centerX - targetWidth / 2f)
            .roundToInt()
            .coerceIn(bounds.left, max(bounds.left, bounds.right - targetWidth))
        val targetY = (centerY - targetHeight / 2f)
            .roundToInt()
            .coerceIn(bounds.top, max(bounds.top, bounds.bottom - targetHeight))
        animateWindow(
            view = view,
            params = params,
            target = WindowFrame(targetWidth, targetHeight, targetX, targetY),
            onComplete = onComplete,
        )
    }

    private fun animateWindow(
        view: FlutterView,
        params: WindowManager.LayoutParams,
        target: WindowFrame,
        onComplete: (ResizeOutcome) -> Unit,
    ) {
        cancelResizeAnimation()
        val start = WindowFrame(params.width, params.height, params.x, params.y)
        if (start == target) {
            onComplete(ResizeOutcome.completed)
            return
        }

        var completed = false
        var cancelled = false
        lateinit var animator: ValueAnimator
        fun finishOnce(outcome: ResizeOutcome) {
            if (completed) return
            completed = true
            onComplete(outcome)
        }

        animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = RESIZE_DURATION_MS
            interpolator = DecelerateInterpolator(1.8f)
            addUpdateListener { valueAnimator ->
                if (
                    flutterView !== view ||
                    layoutParams !== params ||
                    !windowAttached
                ) {
                    return@addUpdateListener
                }
                val fraction = valueAnimator.animatedFraction
                params.width = lerp(start.width, target.width, fraction)
                params.height = lerp(start.height, target.height, fraction)
                params.x = lerp(start.x, target.x, fraction)
                params.y = lerp(start.y, target.y, fraction)
                updateViewLayout(view, params)
            }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationCancel(animation: Animator) {
                    cancelled = true
                    if (resizeAnimator === animator) resizeAnimator = null
                    finishOnce(ResizeOutcome.cancelled)
                }

                override fun onAnimationEnd(animation: Animator) {
                    if (!cancelled && flutterView === view && layoutParams === params && windowAttached) {
                        params.width = target.width
                        params.height = target.height
                        params.x = target.x
                        params.y = target.y
                        updateViewLayout(view, params)
                    }
                    if (resizeAnimator === animator) resizeAnimator = null
                    finishOnce(
                        if (cancelled) ResizeOutcome.cancelled else ResizeOutcome.completed,
                    )
                }
            })
        }
        resizeAnimator = animator
        try {
            animator.start()
        } catch (_: Exception) {
            if (resizeAnimator === animator) resizeAnimator = null
            finishOnce(ResizeOutcome.cancelled)
        }
    }

    private fun cancelResizeAnimation() {
        val animator = resizeAnimator ?: return
        resizeAnimator = null
        animator.cancel()
    }

    private fun safeWindowBounds(): Rect {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val metrics = windowManager.currentWindowMetrics
            val rawBounds = Rect(metrics.bounds)
            val insets = metrics.windowInsets.getInsetsIgnoringVisibility(
                WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout(),
            )
            val left = rawBounds.left + insets.left
            val top = rawBounds.top + insets.top
            val right = rawBounds.right - insets.right
            val bottom = rawBounds.bottom - insets.bottom
            if (right > left && bottom > top) {
                return Rect(left, top, right, bottom)
            }
            return Rect(rawBounds)
        }

        @Suppress("DEPRECATION")
        val metrics = DisplayMetrics().also {
            windowManager.defaultDisplay.getRealMetrics(it)
        }
        return Rect(0, 0, metrics.widthPixels, metrics.heightPixels)
    }

    private fun normalWindowBounds(): Rect {
        val safe = safeWindowBounds()
        val margin = dp(SAFE_MARGIN_DP, service.resources.displayMetrics.density)
        if (safe.width() <= margin * 2 || safe.height() <= margin * 2) {
            return safe
        }
        return Rect(
            safe.left + margin,
            safe.top + margin,
            safe.right - margin,
            safe.bottom - margin,
        )
    }

    private fun dockedX(
        params: WindowManager.LayoutParams,
        bounds: Rect,
    ): Int? = dockedX(params.width, bounds)

    private fun dockedX(width: Int, bounds: Rect): Int? {
        val side = dockedSide ?: return null
        if (windowMode != WindowMode.edgeDocked) return null
        val visibleWidth = dp(
            EDGE_VISIBLE_WIDTH_DP,
            service.resources.displayMetrics.density,
        ).coerceAtMost(width)
        return when (side) {
            DockSide.left -> bounds.left - (width - visibleWidth)
            DockSide.right -> bounds.right - visibleWidth
        }
    }

    private fun nearestDockSide(): DockSide {
        val params = layoutParams ?: return DockSide.right
        val bounds = normalWindowBounds()
        val centerX = params.x + params.width / 2
        return if (centerX <= bounds.centerX()) DockSide.left else DockSide.right
    }

    private fun modeForSize(widthDp: Float, heightDp: Float): WindowMode = when {
        widthDp <= EDGE_MODE_MAX_WIDTH_DP && heightDp <= MINI_MODE_MAX_HEIGHT_DP -> {
            WindowMode.edgeDocked
        }
        widthDp <= MINI_MODE_MAX_WIDTH_DP && heightDp <= MINI_MODE_MAX_HEIGHT_DP -> {
            WindowMode.mini
        }
        heightDp <= COMPACT_MODE_MAX_HEIGHT_DP -> WindowMode.compact
        else -> WindowMode.expanded
    }

    private fun scheduleHide() {
        cancelPendingHide()
        val expectedGeneration = lifecycleGeneration
        val runnable = Runnable {
            pendingHide = null
            if (lifecycleGeneration != expectedGeneration) return@Runnable
            lifecycleGeneration += 1
            releaseCurrentContent()
        }
        pendingHide = runnable
        mainHandler.post(runnable)
    }

    private fun cancelPendingHide() {
        pendingHide?.let(mainHandler::removeCallbacks)
        pendingHide = null
    }

    private fun releaseCurrentContent() {
        cancelResizeAnimation()
        val engine = flutterEngine
        val view = flutterView
        val channel = controlChannel
        val attached = windowAttached
        flutterEngine = null
        flutterView = null
        controlChannel = null
        layoutParams = null
        windowAttached = false
        resizeModeEnabled = false
        targetPickerActive = false
        dockedSide = null
        preDockWindowState = null
        if (attached && view != null) {
            removeView(view)
        }
        disposeFlutterContent(engine, view, channel)
    }

    private fun clearCurrentReferences(
        engine: FlutterEngine?,
        view: FlutterView?,
        channel: MethodChannel?,
    ) {
        if (flutterEngine === engine) flutterEngine = null
        if (flutterView === view) flutterView = null
        if (controlChannel === channel) controlChannel = null
        layoutParams = null
        windowAttached = false
        resizeModeEnabled = false
        targetPickerActive = false
    }

    private fun removeView(view: FlutterView) {
        try {
            windowManager.removeViewImmediate(view)
        } catch (_: Exception) {
            // Android may already have detached the accessibility overlay.
        }
    }

    private fun disposeFlutterContent(
        engine: FlutterEngine?,
        view: FlutterView?,
        channel: MethodChannel?,
    ) {
        try {
            channel?.setMethodCallHandler(null)
        } catch (_: Exception) {
            // The binary messenger may already be detached.
        }
        try {
            view?.setOnTouchListener(null)
            view?.detachFromFlutterEngine()
        } catch (_: Exception) {
            // Continue destroying the engine even after a partial attach failure.
        }
        if (engine != null) {
            try {
                engine.lifecycleChannel.appIsDetached()
            } catch (_: Exception) {
                // The lifecycle channel can already be closed during teardown.
            }
            try {
                engine.destroy()
            } catch (_: Exception) {
                // Do not retain a failed, partially initialized engine.
            }
        }
    }

    private fun updateViewLayout(
        view: FlutterView,
        params: WindowManager.LayoutParams,
    ) {
        try {
            windowManager.updateViewLayout(view, params)
        } catch (_: Exception) {
            // The window can disappear while the Flutter isolate is shutting down.
        }
    }

    private fun parseSession(arguments: Map<String, Any?>): Map<String, Any?> {
        val title = (arguments["title"] as? String)
            ?.trim()
            ?.takeIf(String::isNotEmpty)
            ?: "暂无曲目"
        val durationMs = (arguments["durationMs"] as? Number)
            ?.toLong()
            ?.coerceAtLeast(1L)
            ?: 1L
        val profileLabel = (arguments["profileLabel"] as? String)
            ?.trim()
            ?.takeIf(String::isNotEmpty)
            ?: "未选择键位"
        return arguments + mapOf(
            "title" to title,
            "durationMs" to durationMs,
            "profileLabel" to profileLabel,
        )
    }

    private fun defaultSession(): Map<String, Any?> = mapOf(
        "title" to "暂无曲目",
        "positionMs" to 0L,
        "durationMs" to 1L,
        "isPlaying" to false,
        "speed" to 1.0,
        "profileLabel" to "未选择键位",
    )

    private fun dp(value: Float, density: Float): Int = (value * density).roundToInt()

    private fun lerp(start: Int, end: Int, fraction: Float): Int =
        (start + (end - start) * fraction).roundToInt()

    private data class WindowFrame(
        val width: Int,
        val height: Int,
        val x: Int,
        val y: Int,
    )

    private data class RestorableWindowState(
        val widthDp: Float,
        val heightDp: Float,
        val mode: WindowMode,
    )

    private enum class WindowMode { mini, edgeDocked, compact, expanded }

    private enum class DockSide { left, right }

    private enum class ResizeOutcome { completed, cancelled }

    private companion object {
        const val CONTROL_CHANNEL =
            "dev.happyme531.clxmidiplayer.ng/player_overlay/control"
        const val DART_ENTRYPOINT = "playerOverlayMain"
        const val COMPACT_WIDTH_DP = 420f
        const val COMPACT_HEIGHT_DP = 82f
        const val MINI_WIDTH_DP = 104f
        const val MINI_HEIGHT_DP = 58f
        const val EDGE_DOCKED_WIDTH_DP = 44f
        const val EDGE_VISIBLE_WIDTH_DP = 24f
        const val SAFE_MARGIN_DP = 8f
        const val DOCK_THRESHOLD_DP = 4f
        const val MINI_HANDLE_START_DP = 57f
        const val COMPACT_HANDLE_END_DP = 34f
        const val RESIZE_HANDLE_SIZE_DP = 52f
        const val RESIZE_MIN_WIDTH_DP = 360f
        const val RESIZE_MIN_HEIGHT_DP = 205f
        const val MIN_NORMAL_WIDTH_DP = 100f
        const val MIN_NORMAL_HEIGHT_DP = 48f
        const val MAX_WIDTH_DP = 520f
        const val MAX_HEIGHT_DP = 360f
        const val EDGE_MODE_MAX_WIDTH_DP = 60f
        const val MINI_MODE_MAX_WIDTH_DP = 160f
        val LOCAL_FALLBACK_ERROR_CODES = setOf(
            "main_engine_unavailable",
            "main_engine_timeout",
            "main_engine_dispatch_failed",
        )
        val TERMINAL_PLAYBACK_EVENTS = setOf("completed", "error", "stopped")
        val DURATION_MODES = setOf("shortPress", "repeatedTap", "longPress")
        const val MINI_MODE_MAX_HEIGHT_DP = 80f
        const val COMPACT_MODE_MAX_HEIGHT_DP = 90f
        const val RESIZE_DURATION_MS = 210L
        const val DOCK_CONTENT_FRAME_DELAY_MS = 16L
        const val PLAYER_ACTION_TIMEOUT_MS = 5_000L
    }
}
