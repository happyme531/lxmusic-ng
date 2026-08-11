package dev.happyme531.clxmidiplayer.ng

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * Relays player actions from the accessibility overlay FlutterEngine to the
 * application's primary FlutterEngine. The primary engine remains the single
 * owner of library and player state.
 */
internal object PlayerOverlayCoordinator {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var mainChannel: MethodChannel? = null

    fun attach(channel: MethodChannel) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            mainChannel = channel
        } else {
            mainHandler.post { mainChannel = channel }
        }
    }

    fun detach(channel: MethodChannel) {
        val detach = {
            if (mainChannel === channel) mainChannel = null
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            detach()
        } else {
            mainHandler.post { detach() }
        }
    }

    fun dispatch(
        action: Map<String, Any?>,
        result: MethodChannel.Result,
    ) {
        mainHandler.post {
            val channel = mainChannel
            if (channel == null) {
                result.error(
                    "main_engine_unavailable",
                    "主应用尚未运行，无法更新播放器状态。",
                    null,
                )
                return@post
            }
            var completed = false
            var timeout: Runnable? = null
            fun finish(callback: () -> Unit) {
                if (completed) return
                completed = true
                timeout?.let(mainHandler::removeCallbacks)
                callback()
            }
            timeout = Runnable {
                finish {
                    result.error(
                        "main_engine_timeout",
                        "主应用响应播放器操作超时。",
                        null,
                    )
                }
            }
            timeout?.let { mainHandler.postDelayed(it, DISPATCH_TIMEOUT_MS) }
            try {
                channel.invokeMethod(
                    "overlayAction",
                    action,
                    object : MethodChannel.Result {
                        override fun success(value: Any?) {
                            finish { result.success(value) }
                        }

                        override fun error(code: String, message: String?, details: Any?) {
                            finish { result.error(code, message, details) }
                        }

                        override fun notImplemented() {
                            finish { result.notImplemented() }
                        }
                    },
                )
            } catch (error: Exception) {
                finish {
                    result.error(
                        "main_engine_dispatch_failed",
                        error.message ?: "无法向主应用转发播放器操作。",
                        null,
                    )
                }
            }
        }
    }

    private const val DISPATCH_TIMEOUT_MS = 5_000L
}
