package dev.happyme531.clxmidiplayer.ng

import android.app.Application
import android.content.Context
import android.util.Log
import io.sentry.android.core.SentryAndroid

class LxMusicApplication : Application() {
    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
        initializeLocalCrashCapture()
    }

    private fun initializeLocalCrashCapture() {
        try {
            SentryAndroid.init(this) { options ->
                // A valid DSN keeps the SDK enabled. LocalCrashTransportFactory
                // replaces the network transport, so this host is never contacted.
                options.dsn = LOCAL_ONLY_DSN
                options.setTransportFactory(LocalCrashTransportFactory(this))

                options.isSendDefaultPii = false
                options.isEnableAutoSessionTracking = false
                options.isSendClientReports = false
                options.isEnableNdk = true
                options.isEnableScopeSync = true
                options.isAnrEnabled = true
                options.isTombstoneEnabled = true
                options.isAttachRawTombstone = true
                options.isAttachAnrThreadDump = true
                options.isCollectExternalStorageContext = false
                options.isAttachScreenshot = false
                options.isAttachViewHierarchy = false
                options.tracesSampleRate = 0.0

                options.enableAllAutoBreadcrumbs(true)
                // URLs may contain private data and are not needed for this app's
                // local crash diagnosis.
                options.isEnableNetworkEventBreadcrumbs = false
            }
        } catch (error: RuntimeException) {
            // Crash reporting must never prevent the app itself from starting.
            Log.e(TAG, "Failed to initialize local crash capture", error)
        }
    }

    private companion object {
        const val TAG = "LxMusicCrash"
        const val LOCAL_ONLY_DSN = "https://local@localhost/1"
    }
}
