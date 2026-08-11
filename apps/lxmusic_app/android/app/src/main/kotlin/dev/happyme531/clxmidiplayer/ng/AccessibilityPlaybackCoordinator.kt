package dev.happyme531.clxmidiplayer.ng

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/** Keeps native playback alive in the accessibility service while relaying
 * terminal events to the primary Flutter engine when it is available. */
internal object AccessibilityPlaybackCoordinator {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null

    fun attach(next: MethodChannel) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            channel = next
        } else {
            mainHandler.post { channel = next }
        }
    }

    fun detach(current: MethodChannel) {
        val detach = {
            if (channel === current) channel = null
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            detach()
        } else {
            mainHandler.post { detach() }
        }
    }

    fun emit(event: Map<String, Any?>) {
        mainHandler.post {
            LxMusicAccessibilityService.updatePlayerOverlayFromPlaybackEvent(event)
            channel?.invokeMethod("playbackEvent", event)
        }
    }
}
