package dev.happyme531.clxmidiplayer.ng

import android.content.ClipData
import android.content.Intent
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** Native file/chooser operations behind the Flutter Material prompt. */
internal class CrashReportPrompt(
    private val activity: MainActivity,
) {
    private val store = LocalCrashReportStore(activity.applicationContext)
    private val archiveExecutor = Executors.newSingleThreadExecutor()

    fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pendingReportCount" -> result.success(store.pendingReports().size)
            "sharePendingReports" -> share(result)
            "deletePendingReports" -> {
                store.deleteReports(store.pendingReports())
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun close() {
        archiveExecutor.shutdown()
    }

    private fun share(result: MethodChannel.Result) {
        val reports = store.pendingReports()
        if (reports.isEmpty()) {
            result.error("no_reports", "没有可分享的崩溃报告。", null)
            return
        }
        archiveExecutor.execute {
            try {
                val archive = store.createShareArchive(reports)
                activity.runOnUiThread {
                    if (activity.isFinishing || activity.isDestroyed) {
                        result.error("activity_unavailable", "分享界面暂时不可用。", null)
                    } else {
                        openShareSheet(archive)
                        result.success(null)
                    }
                }
            } catch (error: Exception) {
                Log.e(TAG, "Failed to create crash report ZIP", error)
                activity.runOnUiThread {
                    result.error("archive_failed", "报告打包失败，请重新打开 App 后再试。", null)
                }
            }
        }
    }

    private fun openShareSheet(archive: File) {
        val authority = "${activity.packageName}.crash_reports"
        val uri = FileProvider.getUriForFile(activity, authority, archive)
        val shareIntent = Intent(Intent.ACTION_SEND).apply {
            type = "application/zip"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, "LxMusic-NG Android 崩溃报告")
            clipData = ClipData.newRawUri("LxMusic-NG crash report", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        activity.startActivity(Intent.createChooser(shareIntent, "分享崩溃报告"))
    }

    private companion object {
        const val TAG = "LxMusicCrash"
    }
}
