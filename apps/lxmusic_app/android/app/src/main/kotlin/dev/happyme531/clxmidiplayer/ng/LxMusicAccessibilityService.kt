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
import android.widget.Button
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
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12f, density), dp(8f, density), dp(12f, density), dp(8f, density))
            background = roundedBackground(
                Color.argb(205, 30, 34, 39),
                dp(14f, density).toFloat(),
            )
            elevation = dp(8f, density).toFloat()
        }
        container.addView(
            TextView(this).apply {
                setTextColor(Color.WHITE)
                textSize = 13f
                setTypeface(Typeface.DEFAULT, Typeface.BOLD)
                text = "${active.profileDisplayName} · ${active.layoutDisplayName}"
            },
        )
        val buttons = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END
        }
        buttons.addView(
            Button(this).apply {
                text = "展开校准"
                setTextColor(Color.WHITE)
                textSize = 13f
                minHeight = dp(40f, density)
                minimumHeight = dp(40f, density)
                background = roundedBackground(
                    Color.argb(185, 46, 125, 246),
                    dp(11f, density).toFloat(),
                )
                setOnClickListener { showFullOverlay() }
            },
        )
        buttons.addView(
            Button(this).apply {
                text = "取消"
                setTextColor(Color.WHITE)
                textSize = 13f
                minHeight = dp(40f, density)
                minimumHeight = dp(40f, density)
                background = roundedBackground(
                    Color.argb(165, 91, 96, 104),
                    dp(11f, density).toFloat(),
                )
                setOnClickListener {
                    finishSession(status = "cancelled", message = "用户取消了校准。")
                }
            },
        )
        container.addView(buttons)

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = dp(64f, density)
        }
        windowManager.addView(container, params)
        compactOverlay = container
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
        calibrationOverlay = null
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
    private val handleRadius = dp(18f, density).toFloat()
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
    private val titlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = dp(14f, density).toFloat()
        textAlign = Paint.Align.CENTER
    }
    private var left = 0f
    private var top = 0f
    private var right = 0f
    private var bottom = 0f
    private var initialized = false
    private var activeHandle = Handle.none
    private var pressedButton = ActionButton.none
    private val saveButton = RectF()
    private val resetButton = RectF()
    private val cancelButton = RectF()
    private val titlePill = RectF()
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
        canvas.drawColor(Color.argb(42, 28, 32, 36))

        paint.style = Paint.Style.FILL
        paint.color = Color.argb(26, 83, 211, 190)
        canvas.drawRoundRect(
            RectF(left, top, right, bottom),
            dp(10f, density).toFloat(),
            dp(10f, density).toFloat(),
            paint,
        )
        canvas.drawRect(left, top, right, bottom, borderPaint)

        paint.color = Color.argb(225, 83, 211, 190)
        for (key in session.keys) {
            val x = left + (right - left) * key.normX
            val y = top + (bottom - top) * key.normY
            canvas.drawCircle(x, y, dp(4f, density).toFloat(), paint)
            canvas.drawText(key.keyId, x, y - dp(8f, density), labelPaint)
        }

        paint.color = Color.argb(235, 255, 205, 64)
        canvas.drawCircle(left, top, handleRadius, paint)
        canvas.drawCircle(right, bottom, handleRadius, paint)
        labelPaint.color = Color.BLACK
        canvas.drawText("↖", left, top + dp(4f, density), labelPaint)
        canvas.drawText("↘", right, bottom + dp(4f, density), labelPaint)
        labelPaint.color = Color.WHITE

        paint.color = Color.argb(190, 25, 29, 34)
        canvas.drawRoundRect(
            titlePill,
            dp(13f, density).toFloat(),
            dp(13f, density).toFloat(),
            paint,
        )
        canvas.drawText(
            "${orientationLabel(session.orientation)} · 拖动两端锚点对齐游戏键位",
            titlePill.centerX(),
            titlePill.centerY() - (titlePaint.ascent() + titlePaint.descent()) / 2,
            titlePaint,
        )
        drawButton(canvas, saveButton, "保存", Color.argb(180, 46, 125, 246))
        drawButton(canvas, resetButton, "重置", Color.argb(165, 75, 81, 90))
        drawButton(canvas, cancelButton, "取消", Color.argb(170, 176, 58, 58))
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        val location = IntArray(2)
        getLocationOnScreen(location)
        val x = event.rawX - location[0]
        val y = event.rawY - location[1]
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                activeHandle = when {
                    hypot(x - left, y - top) <= handleRadius * 1.5f -> Handle.leftTop
                    hypot(x - right, y - bottom) <= handleRadius * 1.5f -> Handle.rightBottom
                    else -> Handle.none
                }
                pressedButton = if (activeHandle == Handle.none) buttonAt(x, y) else ActionButton.none
                return activeHandle != Handle.none || pressedButton != ActionButton.none
            }
            MotionEvent.ACTION_MOVE -> {
                when (activeHandle) {
                    Handle.leftTop -> {
                        left = x.coerceIn(viewport.left.toFloat(), max(viewport.left.toFloat(), right - minimumSize))
                        top = y.coerceIn(viewport.top.toFloat(), max(viewport.top.toFloat(), bottom - minimumSize))
                    }
                    Handle.rightBottom -> {
                        right = x.coerceIn(left + minimumSize, viewport.right.toFloat())
                        bottom = y.coerceIn(top + minimumSize, viewport.bottom.toFloat())
                    }
                    Handle.none -> Unit
                }
                invalidate()
                return activeHandle != Handle.none
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
                invalidate()
                return true
            }
            MotionEvent.ACTION_CANCEL -> {
                activeHandle = Handle.none
                pressedButton = ActionButton.none
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

    private fun layoutButtons() {
        val gap = dp(8f, density).toFloat()
        val margin = dp(16f, density).toFloat()
        val titleHeight = dp(38f, density).toFloat()
        val titleWidth = minOf(
            dp(360f, density).toFloat(),
            viewport.width() - margin * 2,
        )
        val titleTop = viewport.top + dp(12f, density)
        titlePill.set(
            viewport.exactCenterX() - titleWidth / 2,
            titleTop.toFloat(),
            viewport.exactCenterX() + titleWidth / 2,
            titleTop + titleHeight,
        )
        val buttonHeight = dp(40f, density).toFloat()
        val availableWidth = (viewport.width() - margin * 2 - gap * 2) / 3f
        val buttonWidth = minOf(dp(92f, density).toFloat(), availableWidth)
        val top = titlePill.bottom + dp(8f, density)
        val totalWidth = buttonWidth * 3 + gap * 2
        val start = viewport.exactCenterX() - totalWidth / 2
        saveButton.set(start, top, start + buttonWidth, top + buttonHeight)
        resetButton.set(saveButton.right + gap, top, saveButton.right + gap + buttonWidth, top + buttonHeight)
        cancelButton.set(resetButton.right + gap, top, resetButton.right + gap + buttonWidth, top + buttonHeight)
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
        layoutButtons()
        if (!initialized) {
            resetBounds(usePrevious = true)
            initialized = true
        } else if (viewportChanged) {
            clampBounds()
        }
        invalidate()
    }

    private fun drawButton(canvas: Canvas, bounds: RectF, text: String, color: Int) {
        paint.color = color
        paint.style = Paint.Style.FILL
        canvas.drawRoundRect(bounds, dp(13f, density).toFloat(), dp(13f, density).toFloat(), paint)
        canvas.drawText(
            text,
            bounds.centerX(),
            bounds.centerY() - (titlePaint.ascent() + titlePaint.descent()) / 2,
            titlePaint,
        )
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

private fun roundedBackground(color: Int, radius: Float): GradientDrawable =
    GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        cornerRadius = radius
        setColor(ColorStateList.valueOf(color))
    }

private fun orientationForConfiguration(configuration: Configuration): String? =
    when (configuration.orientation) {
        Configuration.ORIENTATION_PORTRAIT -> "portrait"
        Configuration.ORIENTATION_LANDSCAPE -> "landscape"
        else -> null
    }

private fun orientationLabel(orientation: String?): String = when (orientation) {
    "portrait" -> "游戏内竖屏"
    "landscape" -> "游戏内横屏"
    else -> "正在检测游戏画面"
}
