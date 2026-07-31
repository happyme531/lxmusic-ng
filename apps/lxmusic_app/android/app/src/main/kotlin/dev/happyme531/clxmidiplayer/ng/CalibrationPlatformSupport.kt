package dev.happyme531.clxmidiplayer.ng

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.graphics.Rect
import android.os.Build
import android.provider.Settings
import android.util.DisplayMetrics
import android.view.Display
import android.view.Surface
import android.view.WindowManager
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.Locale

data class CalibrationDisplayInfo(
    val widthPx: Int,
    val heightPx: Int,
    val density: Float,
    val rotation: Int,
)

object CalibrationPlatformSupport {
    fun stableDeviceId(context: Context): String {
        val androidId = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ANDROID_ID,
        ).orEmpty()
        val digest = MessageDigest.getInstance("SHA-256")
            .digest("$androidId:${context.packageName}".toByteArray(Charsets.UTF_8))
            .joinToString("") { byte -> "%02x".format(byte) }
            .take(32)
        return "android-$digest"
    }

    fun deviceDisplayName(): String {
        val manufacturer = Build.MANUFACTURER.trim()
        val model = Build.MODEL.trim()
        return if (model.lowercase(Locale.ROOT).startsWith(manufacturer.lowercase(Locale.ROOT))) {
            model
        } else {
            "$manufacturer $model".trim()
        }
    }

    fun displayInfo(context: Context): CalibrationDisplayInfo {
        val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val bounds: Rect
        val rotation: Int
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && context is Activity) {
            bounds = windowManager.currentWindowMetrics.bounds
            rotation = context.display?.rotation ?: Surface.ROTATION_0
        } else {
            val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                context.getSystemService(DisplayManager::class.java)
                    .getDisplay(Display.DEFAULT_DISPLAY)
            } else {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay
            }
            val metrics = DisplayMetrics()
            @Suppress("DEPRECATION")
            display.getRealMetrics(metrics)
            bounds = Rect(0, 0, metrics.widthPixels, metrics.heightPixels)
            @Suppress("DEPRECATION")
            rotation = display.rotation
        }
        val width = bounds.width()
        val height = bounds.height()
        return CalibrationDisplayInfo(
            widthPx = width,
            heightPx = height,
            density = context.resources.displayMetrics.density,
            rotation = rotation,
        )
    }

    fun findLaunchableTargets(
        context: Context,
        hints: List<String>,
    ): List<Map<String, String>> {
        val normalizedHints = hints
            .map(String::trim)
            .filter(String::isNotEmpty)
            .map { it.lowercase(Locale.ROOT) }
        if (normalizedHints.isEmpty()) {
            return emptyList()
        }
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val activities = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.packageManager.queryIntentActivities(
                intent,
                android.content.pm.PackageManager.ResolveInfoFlags.of(0),
            )
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.queryIntentActivities(intent, 0)
        }
        return activities
            .asSequence()
            .filter { it.activityInfo.packageName != context.packageName }
            .filter { target ->
                val packageName = target.activityInfo.packageName.lowercase(Locale.ROOT)
                normalizedHints.any(packageName::contains)
            }
            .distinctBy { it.activityInfo.packageName }
            .map { target ->
                mapOf(
                    "packageName" to target.activityInfo.packageName,
                    "label" to target.loadLabel(context.packageManager).toString(),
                )
            }
            .sortedBy { it["label"]?.lowercase(Locale.ROOT) }
            .toList()
    }

    fun launchPackage(context: Context, packageName: String): Boolean {
        val intent = context.packageManager.getLaunchIntentForPackage(packageName)
            ?: return false
        return try {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
            context.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    fun launchMainActivity(context: Context) {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: return
        try {
            intent.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
            context.startActivity(intent)
        } catch (_: Exception) {
            // The persisted result is still consumed the next time Flutter resumes.
        }
    }

    fun mapToJsonObject(map: Map<String, Any?>): JSONObject {
        val json = JSONObject()
        for ((key, value) in map) {
            json.put(key, toJsonValue(value))
        }
        return json
    }

    fun jsonObjectToMap(raw: String): Map<String, Any?> =
        fromJsonObject(JSONObject(raw))

    private fun toJsonValue(value: Any?): Any? = when (value) {
        null -> JSONObject.NULL
        is Map<*, *> -> mapToJsonObject(
            value.entries.associate { it.key.toString() to it.value },
        )
        is Iterable<*> -> JSONArray().apply {
            value.forEach { put(toJsonValue(it)) }
        }
        else -> value
    }

    private fun fromJsonObject(json: JSONObject): Map<String, Any?> {
        val result = mutableMapOf<String, Any?>()
        val keys = json.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            result[key] = fromJsonValue(json.get(key))
        }
        return result
    }

    private fun fromJsonValue(value: Any?): Any? = when (value) {
        JSONObject.NULL -> null
        is JSONObject -> fromJsonObject(value)
        is JSONArray -> List(value.length()) { index -> fromJsonValue(value.get(index)) }
        else -> value
    }
}
