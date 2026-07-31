package dev.happyme531.clxmidiplayer.ng

import android.accessibilityservice.AccessibilityService
import android.content.res.ColorStateList
import android.content.Context
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowInsets
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import java.time.Instant
import kotlin.math.hypot
import kotlin.math.max

class LxMusicAccessibilityService : AccessibilityService() {
    private lateinit var windowManager: WindowManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private var compactOverlay: View? = null
    private var compactOverlayParams: WindowManager.LayoutParams? = null
    private var calibrationOverlay: CalibrationOverlayView? = null
    private var session: CalibrationSession? = null
    private var foregroundPackage: String? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        instance = this
        val active = session
        clearOverlays()
        if (active != null) {
            showCompactOverlay(active)
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            val candidate = event.packageName?.toString()
            if (candidate != null &&
                candidate != packageName &&
                candidate != "com.android.systemui"
            ) {
                foregroundPackage = candidate
            }
        }
    }

    override fun onInterrupt() {
        // Android calls this when accessibility feedback should stop. This
        // service produces no spoken/haptic feedback, and app switching is a
        // normal part of calibration, so the active overlay must stay alive.
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        // The compact overlay is intentionally orientation-agnostic. Only the
        // target game's configuration at expansion time establishes direction.
        val active = session ?: return
        if (calibrationOverlay != null) {
            val nextOrientation = orientationForConfiguration(newConfig)
            if (nextOrientation != null && nextOrientation != active.orientation) {
                finishSession(
                    status = "error",
                    errorCode = "orientation_changed",
                    message = "校准过程中游戏发生了横竖屏切换，请重新开始校准。",
                )
                return
            }
        }
        compactOverlay?.let { overlay ->
            compactOverlayParams?.let { params ->
                overlay.post { clampCompactOverlay(overlay, params) }
            }
        }
        calibrationOverlay?.refreshViewport()
    }

    override fun onDestroy() {
        clearOverlays()
        session = null
        if (instance === this) {
            instance = null
        }
        super.onDestroy()
    }

    private fun beginSession(arguments: Map<String, Any?>): Map<String, Any?> {
        if (session != null) {
            return errorResult("session_active", "已有校准会话正在运行。")
        }
        val parsed = try {
            CalibrationSession.from(arguments)
        } catch (error: IllegalArgumentException) {
            return errorResult("invalid_request", error.message ?: "校准请求无效。")
        }
        clearOverlays()
        foregroundPackage = null
        session = parsed
        return try {
            showCompactOverlay(parsed)
            parsed.targetPackageName?.let { packageName ->
                mainHandler.postDelayed(
                    { CalibrationPlatformSupport.launchPackage(this, packageName) },
                    300,
                )
            }
            mapOf(
                "status" to "started",
                "sessionId" to parsed.sessionId,
            )
        } catch (error: Exception) {
            clearOverlays()
            session = null
            errorResult(
                "overlay_create_failed",
                "无法创建校准悬浮层：${error.message ?: error.javaClass.simpleName}",
            )
        }
    }

    private fun showCompactOverlay(active: CalibrationSession) {
        val density = resources.displayMetrics.density
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8f, density), dp(7f, density), dp(8f, density), dp(7f, density))
            background = roundedBackground(
                color = Color.argb(238, 35, 39, 44),
                radius = dp(18f, density).toFloat(),
                strokeColor = Color.argb(45, 255, 255, 255),
                strokeWidth = dp(1f, density),
            )
            elevation = dp(10f, density).toFloat()
        }

        val dragArea = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, 0, dp(10f, density), 0)
            contentDescription = "拖动校准悬浮条"
        }
        dragArea.addView(
            DragGripView(this, density),
            LinearLayout.LayoutParams(dp(28f, density), dp(44f, density)),
        )
        dragArea.addView(
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER_VERTICAL
                addView(
                    TextView(this@LxMusicAccessibilityService).apply {
                        setTextColor(Color.WHITE)
                        textSize = 12f
                        setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL))
                        maxLines = 1
                        text = "${active.profileDisplayName} · ${active.layoutDisplayName}"
                    },
                )
                addView(
                    TextView(this@LxMusicAccessibilityService).apply {
                        setTextColor(Color.argb(170, 255, 255, 255))
                        textSize = 10f
                        maxLines = 1
                        text = "按住此处移动"
                    },
                )
            },
            LinearLayout.LayoutParams(dp(132f, density), LinearLayout.LayoutParams.WRAP_CONTENT),
        )
        container.addView(dragArea)
        container.addView(
            compactActionView(
                text = "开始校准",
                textColor = Color.rgb(19, 45, 40),
                backgroundColor = Color.rgb(99, 211, 188),
                width = dp(82f, density),
                density = density,
            ) { showFullOverlay() },
        )
        container.addView(
            TextView(this).apply {
                gravity = Gravity.CENTER
                text = "×"
                setTextColor(Color.WHITE)
                textSize = 24f
                contentDescription = "取消校准"
                isClickable = true
                background = roundedBackground(
                    color = Color.argb(28, 255, 255, 255),
                    radius = dp(12f, density).toFloat(),
                )
                setOnClickListener {
                    finishSession(status = "cancelled", message = "用户取消了校准。")
                }
            },
            LinearLayout.LayoutParams(dp(40f, density), dp(40f, density)).apply {
                marginStart = dp(6f, density)
            },
        )

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = dp(16f, density)
            y = dp(64f, density)
        }
        makeCompactOverlayDraggable(dragArea, container, params)
        windowManager.addView(container, params)
        compactOverlay = container
        compactOverlayParams = params
        container.post {
            val metrics = resources.displayMetrics
            params.x = ((metrics.widthPixels - container.width) / 2).coerceAtLeast(dp(8f, density))
            clampCompactOverlay(container, params)
        }
    }

    private fun showFullOverlay() {
        val active = session ?: return
        if (foregroundPackage == null) {
            Toast.makeText(this, "请先切换到目标游戏，再展开校准。", Toast.LENGTH_SHORT).show()
            return
        }
        val targetOrientation = orientationForConfiguration(resources.configuration)
        if (targetOrientation == null) {
            Toast.makeText(this, "无法读取游戏内横竖屏方向，请稍后重试。", Toast.LENGTH_SHORT).show()
            return
        }
        active.orientation = targetOrientation
        getSharedPreferences(MainActivity.NATIVE_PREFERENCES, MODE_PRIVATE)
            .edit()
            .putString(MainActivity.LAST_TARGET_ORIENTATION_KEY, targetOrientation)
            .putString(MainActivity.LAST_TARGET_PROFILE_ID_KEY, active.profileId)
            .putString(MainActivity.LAST_TARGET_LAYOUT_ID_KEY, active.layoutId)
            .apply()
        compactOverlay?.let(::removeOverlay)
        compactOverlay = null
        compactOverlayParams = null
        if (calibrationOverlay != null) {
            return
        }
        val overlay = CalibrationOverlayView(
            context = this,
            session = active,
            onSave = ::saveCalibration,
            onCancel = {
                finishSession(status = "cancelled", message = "用户取消了校准。")
            },
        )
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
        }
        windowManager.addView(overlay, params)
        calibrationOverlay = overlay
    }

    private fun saveCalibration(bounds: CalibrationBounds) {
        val active = session ?: return
        val orientation = active.orientation ?: run {
            finishSession(
                status = "error",
                errorCode = "target_viewport_unavailable",
                message = "尚未获取到游戏画面范围，请重新展开校准层。",
            )
            return
        }
        val display = CalibrationPlatformSupport.displayInfo(this)
        val currentOrientation = orientationForConfiguration(resources.configuration)
        if (currentOrientation != orientation) {
            finishSession(
                status = "error",
                errorCode = "orientation_changed",
                message = "横竖屏方向已变化，请重新开始校准。",
            )
            return
        }
        val now = Instant.now().toString()
        val appVersion = try {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, 0).versionName.orEmpty()
        } catch (_: Exception) {
            ""
        }
        val calibration = mapOf<String, Any?>(
            "schemaVersion" to 1,
            "profileId" to active.profileId,
            "layoutId" to active.layoutId,
            "deviceId" to CalibrationPlatformSupport.stableDeviceId(this),
            "orientation" to orientation,
            "leftTop" to listOf(bounds.left, bounds.top),
            "rightBottom" to listOf(bounds.right, bounds.bottom),
            "viewport" to listOf(bounds.viewportLeft, bounds.viewportTop, bounds.viewportRight, bounds.viewportBottom),
            "capturedAt" to now,
            "metadata" to mapOf(
                "physicalWidthPx" to display.widthPx,
                "physicalHeightPx" to display.heightPx,
                "viewportWidthPx" to (bounds.viewportRight - bounds.viewportLeft),
                "viewportHeightPx" to (bounds.viewportBottom - bounds.viewportTop),
                "density" to display.density,
                "displayRotation" to display.rotation,
                "foregroundPackage" to foregroundPackage,
                "manufacturer" to android.os.Build.MANUFACTURER,
                "model" to android.os.Build.MODEL,
                "deviceDisplayName" to CalibrationPlatformSupport.deviceDisplayName(),
                "appVersion" to appVersion,
                "capturedAt" to now,
            ),
        )
        finishSession(
            status = "saved",
            calibration = calibration,
            message = "校准已保存。",
        )
    }

    private fun finishSession(
        status: String,
        errorCode: String? = null,
        message: String? = null,
        calibration: Map<String, Any?>? = null,
        returnToApp: Boolean = true,
    ) {
        val active = session
        if (active == null && compactOverlay == null && calibrationOverlay == null) {
            return
        }
        val result = mutableMapOf<String, Any?>(
            "status" to status,
            "sessionId" to active?.sessionId,
        )
        errorCode?.let { result["errorCode"] = it }
        message?.let { result["message"] = it }
        calibration?.let { result["calibration"] = it }
        getSharedPreferences(MainActivity.NATIVE_PREFERENCES, MODE_PRIVATE)
            .edit()
            .putString(
                MainActivity.PENDING_RESULT_KEY,
                CalibrationPlatformSupport.mapToJsonObject(result).toString(),
            )
            .apply()
        clearOverlays()
        session = null
        if (message != null) {
            Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
        }
        if (returnToApp) {
            CalibrationPlatformSupport.launchMainActivity(this)
        }
    }

    private fun clearOverlays() {
        compactOverlay?.let(::removeOverlay)
        calibrationOverlay?.let(::removeOverlay)
        compactOverlay = null
        compactOverlayParams = null
        calibrationOverlay = null
    }

    private fun compactActionView(
        text: String,
        textColor: Int,
        backgroundColor: Int,
        width: Int,
        density: Float,
        onClick: () -> Unit,
    ): TextView = TextView(this).apply {
        gravity = Gravity.CENTER
        this.text = text
        setTextColor(textColor)
        textSize = 12f
        setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL))
        contentDescription = text
        isClickable = true
        background = roundedBackground(
            color = backgroundColor,
            radius = dp(12f, density).toFloat(),
        )
        setOnClickListener { onClick() }
        layoutParams = LinearLayout.LayoutParams(width, dp(40f, density))
    }

    private fun makeCompactOverlayDraggable(
        dragArea: View,
        overlay: View,
        params: WindowManager.LayoutParams,
    ) {
        var downRawX = 0f
        var downRawY = 0f
        var downX = 0
        var downY = 0
        dragArea.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downRawX = event.rawX
                    downRawY = event.rawY
                    downX = params.x
                    downY = params.y
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    params.x = downX + (event.rawX - downRawX).toInt()
                    params.y = downY + (event.rawY - downRawY).toInt()
                    clampCompactOverlay(overlay, params)
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> true
                else -> false
            }
        }
    }

    private fun clampCompactOverlay(
        overlay: View,
        params: WindowManager.LayoutParams,
    ) {
        if (overlay.width <= 0 || overlay.height <= 0) return
        val metrics = resources.displayMetrics
        val margin = dp(8f, metrics.density)
        params.x = params.x.coerceIn(margin, max(margin, metrics.widthPixels - overlay.width - margin))
        params.y = params.y.coerceIn(margin, max(margin, metrics.heightPixels - overlay.height - margin))
        try {
            windowManager.updateViewLayout(overlay, params)
        } catch (_: Exception) {
            // The overlay may be in the process of being removed.
        }
    }

    private fun removeOverlay(view: View) {
        try {
            windowManager.removeViewImmediate(view)
        } catch (_: Exception) {
            // The window may already have been removed by Android.
        }
    }

    private fun errorResult(code: String, message: String): Map<String, Any?> =
        mapOf(
            "status" to "error",
            "errorCode" to code,
            "message" to message,
        )

    companion object {
        @Volatile
        private var instance: LxMusicAccessibilityService? = null

        fun startCalibration(arguments: Map<String, Any?>): Map<String, Any?> =
            instance?.beginSession(arguments)
                ?: mapOf(
                    "status" to "error",
                    "errorCode" to "service_unavailable",
                    "message" to "无障碍服务尚未连接，请关闭后重新启用。",
                )

        fun cancelCalibration() {
            instance?.finishSession(
                status = "cancelled",
                message = "校准已取消。",
            )
        }

        fun activeSessionId(): String? = instance?.session?.sessionId
    }
}

private data class CalibrationReferenceKey(
    val keyId: String,
    val normX: Float,
    val normY: Float,
)

private data class CalibrationSession(
    val sessionId: String,
    val profileId: String,
    val layoutId: String,
    val profileDisplayName: String,
    val layoutDisplayName: String,
    var orientation: String?,
    val keys: List<CalibrationReferenceKey>,
    val targetPackageName: String?,
    val previousCalibration: PreviousCalibration?,
) {
    companion object {
        fun from(arguments: Map<String, Any?>): CalibrationSession {
            fun requiredString(key: String): String =
                (arguments[key] as? String)?.takeIf(String::isNotBlank)
                    ?: throw IllegalArgumentException("缺少字段 $key。")

            val rawKeys = arguments["keys"] as? List<*>
                ?: throw IllegalArgumentException("缺少键位参考点。")
            val keys = rawKeys.map { raw ->
                val map = raw as? Map<*, *>
                    ?: throw IllegalArgumentException("键位参考点格式无效。")
                CalibrationReferenceKey(
                    keyId = map["keyId"] as? String
                        ?: throw IllegalArgumentException("键位 ID 无效。"),
                    normX = (map["normX"] as? Number)?.toFloat()
                        ?: throw IllegalArgumentException("键位 X 坐标无效。"),
                    normY = (map["normY"] as? Number)?.toFloat()
                        ?: throw IllegalArgumentException("键位 Y 坐标无效。"),
                )
            }
            val previousCalibration = PreviousCalibration.from(
                arguments["previousCalibration"] as? Map<*, *>,
            )
            return CalibrationSession(
                sessionId = requiredString("sessionId"),
                profileId = requiredString("profileId"),
                layoutId = requiredString("layoutId"),
                profileDisplayName = requiredString("profileDisplayName"),
                layoutDisplayName = requiredString("layoutDisplayName"),
                orientation = null,
                keys = keys,
                targetPackageName = (arguments["targetPackageName"] as? String)
                    ?.takeIf(String::isNotBlank),
                previousCalibration = previousCalibration,
            )
        }
    }
}

private data class PreviousCalibration(
    val orientation: String,
    val left: Float,
    val top: Float,
    val right: Float,
    val bottom: Float,
) {
    companion object {
        fun from(raw: Map<*, *>?): PreviousCalibration? {
            if (raw == null) return null
            val orientation = (raw["orientation"] as? String)
                ?.takeIf { it == "portrait" || it == "landscape" }
                ?: return null
            val leftTop = raw["leftTop"] as? List<*> ?: return null
            val rightBottom = raw["rightBottom"] as? List<*> ?: return null
            val left = (leftTop.getOrNull(0) as? Number)?.toFloat() ?: return null
            val top = (leftTop.getOrNull(1) as? Number)?.toFloat() ?: return null
            val right = (rightBottom.getOrNull(0) as? Number)?.toFloat() ?: return null
            val bottom = (rightBottom.getOrNull(1) as? Number)?.toFloat() ?: return null
            if (left >= right || top >= bottom) return null
            return PreviousCalibration(orientation, left, top, right, bottom)
        }
    }
}

private data class CalibrationBounds(
    val left: Float,
    val top: Float,
    val right: Float,
    val bottom: Float,
    val viewportLeft: Float,
    val viewportTop: Float,
    val viewportRight: Float,
    val viewportBottom: Float,
)

private class CalibrationOverlayView(
    context: Context,
    private val session: CalibrationSession,
    private val onSave: (CalibrationBounds) -> Unit,
    private val onCancel: () -> Unit,
) : View(context) {
    private val density = resources.displayMetrics.density
    private val minimumSize = dp(48f, density).toFloat()
    private val visibleHandleRadius = dp(15f, density).toFloat()
    private val handleHitRadius = dp(28f, density).toFloat()
    private val handleOffset = dp(34f, density).toFloat()
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(235, 83, 211, 190)
        style = Paint.Style.STROKE
        strokeWidth = dp(2f, density).toFloat()
    }
    private val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = dp(11f, density).toFloat()
        textAlign = Paint.Align.CENTER
        setShadowLayer(dp(2f, density).toFloat(), 0f, dp(1f, density).toFloat(), Color.BLACK)
    }
    private val toolbarTitlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = dp(12f, density).toFloat()
        textAlign = Paint.Align.LEFT
        typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
    }
    private val actionTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textSize = dp(12f, density).toFloat()
        textAlign = Paint.Align.CENTER
        typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
    }
    private var left = 0f
    private var top = 0f
    private var right = 0f
    private var bottom = 0f
    private var initialized = false
    private var activeHandle = Handle.none
    private var leftTopHandleX = 0f
    private var leftTopHandleY = 0f
    private var rightBottomHandleX = 0f
    private var rightBottomHandleY = 0f
    private var handleTouchStartX = 0f
    private var handleTouchStartY = 0f
    private var dragStartLeft = 0f
    private var dragStartTop = 0f
    private var dragStartRight = 0f
    private var dragStartBottom = 0f
    private var pressedButton = ActionButton.none
    private var draggingToolbar = false
    private var toolbarDragOffsetX = 0f
    private var toolbarDragOffsetY = 0f
    private var toolbarInitialized = false
    private val saveButton = RectF()
    private val resetButton = RectF()
    private val cancelButton = RectF()
    private val toolbar = RectF()
    private val toolbarDragArea = RectF()
    private val viewport = Rect()

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        requestApplyInsets()
    }

    override fun onApplyWindowInsets(insets: WindowInsets): WindowInsets {
        updateViewport(insets)
        return super.onApplyWindowInsets(insets)
    }

    fun refreshViewport() {
        requestLayout()
        requestApplyInsets()
        post { rootWindowInsets?.let(::updateViewport) }
    }

    override fun onSizeChanged(width: Int, height: Int, oldWidth: Int, oldHeight: Int) {
        super.onSizeChanged(width, height, oldWidth, oldHeight)
        rootWindowInsets?.let(::updateViewport) ?: requestApplyInsets()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.drawColor(Color.argb(20, 24, 28, 32))

        paint.style = Paint.Style.FILL
        paint.color = Color.argb(20, 83, 211, 190)
        canvas.drawRoundRect(
            RectF(left, top, right, bottom),
            dp(10f, density).toFloat(),
            dp(10f, density).toFloat(),
            paint,
        )
        canvas.drawRoundRect(
            RectF(left, top, right, bottom),
            dp(10f, density).toFloat(),
            dp(10f, density).toFloat(),
            borderPaint,
        )

        paint.color = Color.argb(225, 83, 211, 190)
        for (key in session.keys) {
            val x = left + (right - left) * key.normX
            val y = top + (bottom - top) * key.normY
            canvas.drawCircle(x, y, dp(4f, density).toFloat(), paint)
            canvas.drawText(key.keyId, x, y - dp(8f, density), labelPaint)
        }

        updateHandlePositions()
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = dp(1.5f, density).toFloat()
        paint.color = Color.argb(205, 255, 198, 49)
        canvas.drawLine(left, top, leftTopHandleX, leftTopHandleY, paint)
        canvas.drawLine(right, bottom, rightBottomHandleX, rightBottomHandleY, paint)
        drawTarget(canvas, left, top)
        drawTarget(canvas, right, bottom)

        paint.style = Paint.Style.FILL
        paint.color = Color.argb(70, 255, 198, 49)
        canvas.drawCircle(
            leftTopHandleX,
            leftTopHandleY,
            visibleHandleRadius + dp(5f, density),
            paint,
        )
        canvas.drawCircle(
            rightBottomHandleX,
            rightBottomHandleY,
            visibleHandleRadius + dp(5f, density),
            paint,
        )
        paint.color = Color.rgb(255, 198, 49)
        canvas.drawCircle(leftTopHandleX, leftTopHandleY, visibleHandleRadius, paint)
        canvas.drawCircle(rightBottomHandleX, rightBottomHandleY, visibleHandleRadius, paint)
        labelPaint.color = Color.BLACK
        canvas.drawText(
            "↖",
            leftTopHandleX,
            leftTopHandleY + dp(4f, density),
            labelPaint,
        )
        canvas.drawText(
            "↘",
            rightBottomHandleX,
            rightBottomHandleY + dp(4f, density),
            labelPaint,
        )
        labelPaint.color = Color.WHITE

        paint.color = Color.argb(238, 35, 39, 44)
        canvas.drawRoundRect(
            toolbar,
            dp(18f, density).toFloat(),
            dp(18f, density).toFloat(),
            paint,
        )
        paint.color = Color.argb(42, 255, 255, 255)
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = dp(1f, density).toFloat()
        canvas.drawRoundRect(
            toolbar,
            dp(18f, density).toFloat(),
            dp(18f, density).toFloat(),
            paint,
        )
        paint.style = Paint.Style.FILL
        drawDragGrip(canvas)
        drawToolbarText(canvas)
        drawActionButton(
            canvas = canvas,
            bounds = resetButton,
            text = "重置",
            background = Color.argb(30, 255, 255, 255),
            foreground = Color.argb(220, 255, 255, 255),
            action = ActionButton.reset,
        )
        drawActionButton(
            canvas = canvas,
            bounds = cancelButton,
            text = "取消",
            background = Color.argb(28, 244, 119, 126),
            foreground = Color.rgb(255, 184, 188),
            action = ActionButton.cancel,
        )
        drawActionButton(
            canvas = canvas,
            bounds = saveButton,
            text = "完成",
            background = Color.rgb(99, 211, 188),
            foreground = Color.rgb(19, 45, 40),
            action = ActionButton.save,
        )
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        val location = IntArray(2)
        getLocationOnScreen(location)
        val x = event.rawX - location[0]
        val y = event.rawY - location[1]
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                updateHandlePositions()
                pressedButton = buttonAt(x, y)
                draggingToolbar = pressedButton == ActionButton.none && toolbarDragArea.contains(x, y)
                if (draggingToolbar) {
                    toolbarDragOffsetX = x - toolbar.left
                    toolbarDragOffsetY = y - toolbar.top
                }
                activeHandle = if (pressedButton == ActionButton.none && !draggingToolbar) {
                    when {
                        hypot(x - leftTopHandleX, y - leftTopHandleY) <= handleHitRadius -> {
                            Handle.leftTop
                        }
                        hypot(x - rightBottomHandleX, y - rightBottomHandleY) <= handleHitRadius -> {
                            Handle.rightBottom
                        }
                        else -> Handle.none
                    }
                } else {
                    Handle.none
                }
                if (activeHandle != Handle.none) {
                    handleTouchStartX = x
                    handleTouchStartY = y
                    dragStartLeft = left
                    dragStartTop = top
                    dragStartRight = right
                    dragStartBottom = bottom
                }
                invalidate()
                return activeHandle != Handle.none ||
                    pressedButton != ActionButton.none ||
                    draggingToolbar
            }
            MotionEvent.ACTION_MOVE -> {
                if (draggingToolbar) {
                    moveToolbar(
                        x - toolbarDragOffsetX,
                        y - toolbarDragOffsetY,
                    )
                } else {
                    when (activeHandle) {
                        Handle.leftTop -> {
                            left = (dragStartLeft + x - handleTouchStartX).coerceIn(
                                viewport.left.toFloat(),
                                max(viewport.left.toFloat(), right - minimumSize),
                            )
                            top = (dragStartTop + y - handleTouchStartY).coerceIn(
                                viewport.top.toFloat(),
                                max(viewport.top.toFloat(), bottom - minimumSize),
                            )
                        }
                        Handle.rightBottom -> {
                            right = (dragStartRight + x - handleTouchStartX).coerceIn(
                                left + minimumSize,
                                viewport.right.toFloat(),
                            )
                            bottom = (dragStartBottom + y - handleTouchStartY).coerceIn(
                                top + minimumSize,
                                viewport.bottom.toFloat(),
                            )
                        }
                        Handle.none -> Unit
                    }
                }
                invalidate()
                return activeHandle != Handle.none || draggingToolbar || pressedButton != ActionButton.none
            }
            MotionEvent.ACTION_UP -> {
                val releasedButton = buttonAt(x, y)
                if (pressedButton != ActionButton.none && pressedButton == releasedButton) {
                    when (pressedButton) {
                        ActionButton.save -> save(location)
                        ActionButton.reset -> resetBounds(usePrevious = false)
                        ActionButton.cancel -> onCancel()
                        ActionButton.none -> Unit
                    }
                }
                activeHandle = Handle.none
                pressedButton = ActionButton.none
                draggingToolbar = false
                invalidate()
                return true
            }
            MotionEvent.ACTION_CANCEL -> {
                activeHandle = Handle.none
                pressedButton = ActionButton.none
                draggingToolbar = false
                invalidate()
                return true
            }
        }
        return false
    }

    private fun save(location: IntArray) {
        val originX = location[0].toFloat()
        val originY = location[1].toFloat()
        onSave(
            CalibrationBounds(
                left = left + originX,
                top = top + originY,
                right = right + originX,
                bottom = bottom + originY,
                viewportLeft = originX + viewport.left,
                viewportTop = originY + viewport.top,
                viewportRight = originX + viewport.right,
                viewportBottom = originY + viewport.bottom,
            ),
        )
    }

    private fun resetBounds(usePrevious: Boolean) {
        val location = IntArray(2)
        getLocationOnScreen(location)
        val previous = session.previousCalibration
            ?.takeIf { it.orientation == session.orientation }
        if (usePrevious && previous != null) {
            left = previous.left - location[0]
            top = previous.top - location[1]
            right = previous.right - location[0]
            bottom = previous.bottom - location[1]
            clampBounds()
        } else {
            left = viewport.left + viewport.width() * 0.25f
            top = viewport.top + viewport.height() * 0.25f
            right = viewport.left + viewport.width() * 0.75f
            bottom = viewport.top + viewport.height() * 0.75f
        }
        invalidate()
    }

    private fun clampBounds() {
        if (viewport.width() <= 0 || viewport.height() <= 0) return
        left = left.coerceIn(viewport.left.toFloat(), max(viewport.left.toFloat(), viewport.right - minimumSize))
        top = top.coerceIn(viewport.top.toFloat(), max(viewport.top.toFloat(), viewport.bottom - minimumSize))
        right = right.coerceIn(left + minimumSize, viewport.right.toFloat())
        bottom = bottom.coerceIn(top + minimumSize, viewport.bottom.toFloat())
    }

    private fun updateHandlePositions() {
        if (viewport.width() <= 0 || viewport.height() <= 0) {
            leftTopHandleX = left
            leftTopHandleY = top
            rightBottomHandleX = right
            rightBottomHandleY = bottom
            return
        }
        val safeRadius = visibleHandleRadius + dp(5f, density)
        val minX = viewport.left + safeRadius
        val maxX = viewport.right - safeRadius
        val minY = viewport.top + safeRadius
        val maxY = viewport.bottom - safeRadius
        leftTopHandleX = offsetHandleCoordinate(left, -1f, minX, maxX)
        leftTopHandleY = offsetHandleCoordinate(top, -1f, minY, maxY)
        rightBottomHandleX = offsetHandleCoordinate(right, 1f, minX, maxX)
        rightBottomHandleY = offsetHandleCoordinate(bottom, 1f, minY, maxY)
    }

    private fun offsetHandleCoordinate(
        origin: Float,
        preferredDirection: Float,
        minimum: Float,
        maximum: Float,
    ): Float {
        if (maximum <= minimum) return origin
        val preferred = origin + preferredDirection * handleOffset
        if (preferred in minimum..maximum) return preferred
        val flipped = origin - preferredDirection * handleOffset
        if (flipped in minimum..maximum) return flipped
        return preferred.coerceIn(minimum, maximum)
    }

    private fun drawTarget(canvas: Canvas, x: Float, y: Float) {
        val ringRadius = dp(5f, density).toFloat()
        val innerArm = dp(7f, density).toFloat()
        val outerArm = dp(10f, density).toFloat()
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = dp(1.5f, density).toFloat()
        paint.color = Color.argb(235, 255, 226, 132)
        canvas.drawCircle(x, y, ringRadius, paint)
        canvas.drawLine(x - outerArm, y, x - innerArm, y, paint)
        canvas.drawLine(x + innerArm, y, x + outerArm, y, paint)
        canvas.drawLine(x, y - outerArm, x, y - innerArm, paint)
        canvas.drawLine(x, y + innerArm, x, y + outerArm, paint)
    }

    private fun layoutToolbar() {
        val margin = dp(12f, density).toFloat()
        val toolbarWidth = minOf(
            dp(376f, density).toFloat(),
            viewport.width() - margin * 2,
        )
        val toolbarHeight = dp(52f, density).toFloat()
        if (!toolbarInitialized) {
            val toolbarTop = viewport.top + margin
            toolbar.set(
                viewport.exactCenterX() - toolbarWidth / 2,
                toolbarTop,
                viewport.exactCenterX() + toolbarWidth / 2,
                toolbarTop + toolbarHeight,
            )
            toolbarInitialized = true
        } else {
            toolbar.set(
                toolbar.left,
                toolbar.top,
                toolbar.left + toolbarWidth,
                toolbar.top + toolbarHeight,
            )
            clampToolbar()
        }
        layoutToolbarContents()
    }

    private fun layoutToolbarContents() {
        val edgePadding = dp(8f, density).toFloat()
        val gap = dp(5f, density).toFloat()
        val buttonTop = toolbar.centerY() - dp(18f, density)
        val buttonBottom = buttonTop + dp(36f, density)
        val saveWidth = dp(62f, density).toFloat()
        val secondaryWidth = dp(52f, density).toFloat()

        saveButton.set(
            toolbar.right - edgePadding - saveWidth,
            buttonTop,
            toolbar.right - edgePadding,
            buttonBottom,
        )
        cancelButton.set(
            saveButton.left - gap - secondaryWidth,
            buttonTop,
            saveButton.left - gap,
            buttonBottom,
        )
        resetButton.set(
            cancelButton.left - gap - secondaryWidth,
            buttonTop,
            cancelButton.left - gap,
            buttonBottom,
        )
        toolbarDragArea.set(
            toolbar.left,
            toolbar.top,
            resetButton.left - gap / 2,
            toolbar.bottom,
        )
    }

    private fun moveToolbar(desiredLeft: Float, desiredTop: Float) {
        if (viewport.width() <= 0 || viewport.height() <= 0) return
        val margin = dp(6f, density).toFloat()
        val minLeft = viewport.left + margin
        val maxLeft = max(minLeft, viewport.right - margin - toolbar.width())
        val minTop = viewport.top + margin
        val maxTop = max(minTop, viewport.bottom - margin - toolbar.height())
        toolbar.offsetTo(
            desiredLeft.coerceIn(minLeft, maxLeft),
            desiredTop.coerceIn(minTop, maxTop),
        )
        layoutToolbarContents()
    }

    private fun clampToolbar() {
        moveToolbar(toolbar.left, toolbar.top)
    }

    private fun updateViewport(insets: WindowInsets) {
        if (width <= 0 || height <= 0) return
        val next = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val safe = insets.getInsets(
                WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout(),
            )
            Rect(safe.left, safe.top, width - safe.right, height - safe.bottom)
        } else {
            @Suppress("DEPRECATION")
            Rect(
                insets.systemWindowInsetLeft,
                insets.systemWindowInsetTop,
                width - insets.systemWindowInsetRight,
                height - insets.systemWindowInsetBottom,
            )
        }
        if (next.width() <= 0 || next.height() <= 0) return
        val viewportChanged = viewport != next
        viewport.set(next)
        layoutToolbar()
        if (!initialized) {
            resetBounds(usePrevious = true)
            initialized = true
        } else if (viewportChanged) {
            clampBounds()
        }
        invalidate()
    }

    private fun drawDragGrip(canvas: Canvas) {
        paint.color = Color.argb(145, 255, 255, 255)
        paint.style = Paint.Style.FILL
        val centerX = toolbar.left + dp(17f, density)
        val centerY = toolbar.centerY()
        val columnGap = dp(5f, density).toFloat()
        val rowGap = dp(6f, density).toFloat()
        val radius = dp(1.4f, density).toFloat()
        for (column in -1..1 step 2) {
            for (row in -1..1) {
                canvas.drawCircle(
                    centerX + column * columnGap / 2,
                    centerY + row * rowGap,
                    radius,
                    paint,
                )
            }
        }
    }

    private fun drawToolbarText(canvas: Canvas) {
        val textLeft = toolbar.left + dp(34f, density)
        val maxWidth = max(0f, resetButton.left - dp(8f, density) - textLeft)
        val title = "${shortOrientationLabel(session.orientation)} · 十字对准角键"
        canvas.drawText(
            fitText(title, toolbarTitlePaint, maxWidth),
            textLeft,
            toolbar.centerY() - (toolbarTitlePaint.ascent() + toolbarTitlePaint.descent()) / 2,
            toolbarTitlePaint,
        )
    }

    private fun drawActionButton(
        canvas: Canvas,
        bounds: RectF,
        text: String,
        background: Int,
        foreground: Int,
        action: ActionButton,
    ) {
        paint.color = if (pressedButton == action) {
            Color.argb(
                minOf(255, Color.alpha(background) + 28),
                Color.red(background),
                Color.green(background),
                Color.blue(background),
            )
        } else {
            background
        }
        paint.style = Paint.Style.FILL
        canvas.drawRoundRect(
            bounds,
            dp(12f, density).toFloat(),
            dp(12f, density).toFloat(),
            paint,
        )
        actionTextPaint.color = foreground
        canvas.drawText(
            text,
            bounds.centerX(),
            bounds.centerY() - (actionTextPaint.ascent() + actionTextPaint.descent()) / 2,
            actionTextPaint,
        )
    }

    private fun fitText(text: String, textPaint: Paint, maxWidth: Float): String {
        if (maxWidth <= 0f) return ""
        if (textPaint.measureText(text) <= maxWidth) return text
        val ellipsis = "…"
        val ellipsisWidth = textPaint.measureText(ellipsis)
        if (ellipsisWidth >= maxWidth) return ellipsis
        var end = text.length
        while (end > 0 && textPaint.measureText(text, 0, end) + ellipsisWidth > maxWidth) {
            end -= 1
        }
        return text.substring(0, end) + ellipsis
    }

    private fun buttonAt(x: Float, y: Float): ActionButton = when {
        saveButton.contains(x, y) -> ActionButton.save
        resetButton.contains(x, y) -> ActionButton.reset
        cancelButton.contains(x, y) -> ActionButton.cancel
        else -> ActionButton.none
    }

    private enum class Handle { none, leftTop, rightBottom }
    private enum class ActionButton { none, save, reset, cancel }
}

private fun dp(value: Float, density: Float): Int = (value * density + 0.5f).toInt()

private class DragGripView(
    context: Context,
    private val density: Float,
) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(150, 255, 255, 255)
        style = Paint.Style.FILL
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val columnGap = dp(6f, density).toFloat()
        val rowGap = dp(7f, density).toFloat()
        val radius = dp(1.5f, density).toFloat()
        for (column in -1..1 step 2) {
            for (row in -1..1) {
                canvas.drawCircle(
                    width / 2f + column * columnGap / 2,
                    height / 2f + row * rowGap,
                    radius,
                    paint,
                )
            }
        }
    }
}

private fun roundedBackground(
    color: Int,
    radius: Float,
    strokeColor: Int? = null,
    strokeWidth: Int = 0,
): GradientDrawable =
    GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        cornerRadius = radius
        setColor(ColorStateList.valueOf(color))
        if (strokeColor != null && strokeWidth > 0) {
            setStroke(strokeWidth, strokeColor)
        }
    }

private fun orientationForConfiguration(configuration: Configuration): String? =
    when (configuration.orientation) {
        Configuration.ORIENTATION_PORTRAIT -> "portrait"
        Configuration.ORIENTATION_LANDSCAPE -> "landscape"
        else -> null
    }

private fun shortOrientationLabel(orientation: String?): String = when (orientation) {
    "portrait" -> "竖屏"
    "landscape" -> "横屏"
    else -> "检测中"
}
