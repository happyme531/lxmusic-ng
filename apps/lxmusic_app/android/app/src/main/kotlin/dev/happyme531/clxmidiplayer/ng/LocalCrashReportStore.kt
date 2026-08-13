package dev.happyme531.clxmidiplayer.ng

import android.content.Context
import android.os.Build
import io.sentry.ISerializer
import io.sentry.SentryEnvelope
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.charset.StandardCharsets
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

internal class LocalCrashReportStore(
    private val context: Context,
) {
    private val pendingDirectory = File(context.filesDir, PENDING_DIRECTORY)
    private val sentryCacheDirectory = File(context.cacheDir, SENTRY_CACHE_DIRECTORY)
    private val shareDirectory = File(context.cacheDir, SHARE_DIRECTORY)

    @Synchronized
    @Throws(IOException::class)
    fun writeEnvelope(envelope: SentryEnvelope, serializer: ISerializer) {
        ensureDirectory(pendingDirectory)
        val eventId = envelope.header.eventId?.toString() ?: UUID.randomUUID().toString()
        val destination = File(
            pendingDirectory,
            "${System.currentTimeMillis()}-${safeFileName(eventId)}.envelope",
        )
        val temporary = File(pendingDirectory, "${destination.name}.tmp")
        try {
            FileOutputStream(temporary).use { fileOutput ->
                BufferedOutputStream(fileOutput).use { output ->
                    serializer.serialize(envelope, output)
                    output.flush()
                    fileOutput.fd.sync()
                }
            }
            if (!temporary.renameTo(destination)) {
                temporary.copyTo(destination, overwrite = true)
                temporary.delete()
            }
            trimOldReports()
        } finally {
            temporary.delete()
        }
    }

    fun pendingReports(): List<File> {
        val locallyPersisted = pendingDirectory
            .listFiles { file -> file.isFile && file.extension == "envelope" }
            .orEmpty()
        // Sentry deliberately writes unhandled Java and native events into its
        // own offline cache before the process exits. Those envelopes may not
        // reach our transport before Android kills the process, so they are an
        // equally important source for the next-launch prompt.
        val sentryPersisted: List<File> = if (sentryCacheDirectory.isDirectory) {
            sentryCacheDirectory
                .walkTopDown()
                .maxDepth(SENTRY_CACHE_SCAN_DEPTH)
                .filter { file ->
                    file.isFile &&
                        isSentryEnvelopeCandidate(file) &&
                        containsEvent(file)
                }
                .toList()
        } else {
            emptyList()
        }
        return (locallyPersisted.toList() + sentryPersisted)
            .distinctBy { it.absolutePath }
            .sortedByDescending(File::lastModified)
    }

    @Synchronized
    @Throws(IOException::class)
    fun createShareArchive(reports: List<File>): File {
        require(reports.isNotEmpty()) { "No crash reports to archive" }
        ensureDirectory(shareDirectory)
        shareDirectory.listFiles()?.forEach { oldArchive ->
            if (oldArchive.isFile && oldArchive.extension == "zip") oldArchive.delete()
        }

        val timestamp = fileTimestampFormat().format(Date())
        val archive = File(shareDirectory, "lxmusic-crash-$timestamp.zip")
        ZipOutputStream(BufferedOutputStream(FileOutputStream(archive))).use { zip ->
            addTextEntry(zip, "README.txt", reportReadme())
            addTextEntry(zip, "device-info.txt", deviceInfo())
            reports.forEachIndexed { index, report ->
                if (!isAllowedReport(report)) return@forEachIndexed
                val exportedName = if (report.extension == "envelope") {
                    report.name
                } else {
                    "${report.name}.envelope"
                }
                zip.putNextEntry(ZipEntry("reports/${index + 1}-$exportedName"))
                report.inputStream().buffered().use { input -> input.copyTo(zip) }
                zip.closeEntry()
            }
        }
        return archive
    }

    @Synchronized
    fun deleteReports(reports: List<File>) {
        reports.forEach { report ->
            if (isAllowedReport(report)) report.delete()
        }
    }

    private fun trimOldReports() {
        pendingReports().drop(MAX_REPORT_COUNT).forEach(File::delete)
    }

    private fun containsEvent(file: File): Boolean = try {
        file.bufferedReader().use { reader ->
            repeat(MAX_ENVELOPE_HEADER_LINES) {
                val line = reader.readLine() ?: return false
                if (EVENT_ITEM_PATTERN.containsMatchIn(line)) return true
            }
            false
        }
    } catch (_: IOException) {
        false
    }

    private fun isAllowedReport(file: File): Boolean {
        if (!file.isFile) return false
        return (file.extension == "envelope" && isInside(file, pendingDirectory)) ||
            (
                isInside(file, sentryCacheDirectory) &&
                    isSentryEnvelopeCandidate(file) &&
                    containsEvent(file)
            )
    }

    private fun isSentryEnvelopeCandidate(file: File): Boolean =
        file.extension == "envelope" || file.parentFile?.name == SENTRY_OUTBOX_DIRECTORY

    private fun isInside(file: File, directory: File): Boolean = try {
        val directoryPath = directory.canonicalPath + File.separator
        file.canonicalPath.startsWith(directoryPath)
    } catch (_: IOException) {
        false
    }

    private fun reportReadme(): String = """
        LxMusic-NG Android 本地崩溃报告

        此 ZIP 由用户在 App 内确认后生成并手动分享，没有自动上传。
        reports/ 中是 Sentry envelope，可能包含异常堆栈、设备/系统信息、
        App 生命周期与用户操作 breadcrumbs。报告不包含屏幕截图或网络请求记录。
    """.trimIndent() + "\n"

    private fun deviceInfo(): String {
        val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            packageInfo.versionCode.toLong()
        }
        return buildString {
            appendLine("generated_at_utc=${isoTimestampFormat().format(Date())}")
            appendLine("package=${context.packageName}")
            appendLine("version_name=${packageInfo.versionName.orEmpty()}")
            appendLine("version_code=$versionCode")
            appendLine("android_api=${Build.VERSION.SDK_INT}")
            appendLine("android_release=${Build.VERSION.RELEASE}")
            appendLine("manufacturer=${Build.MANUFACTURER}")
            appendLine("model=${Build.MODEL}")
            appendLine("supported_abis=${Build.SUPPORTED_ABIS.joinToString(",")}")
        }
    }

    private fun addTextEntry(zip: ZipOutputStream, name: String, content: String) {
        zip.putNextEntry(ZipEntry(name))
        zip.write(content.toByteArray(StandardCharsets.UTF_8))
        zip.closeEntry()
    }

    private fun ensureDirectory(directory: File) {
        if (!directory.isDirectory && !directory.mkdirs() && !directory.isDirectory) {
            throw IOException("Cannot create ${directory.absolutePath}")
        }
    }

    private fun safeFileName(value: String): String =
        value.replace(Regex("[^A-Za-z0-9._-]"), "_").take(80)

    private fun fileTimestampFormat() =
        SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US)

    private fun isoTimestampFormat() =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }

    private companion object {
        const val PENDING_DIRECTORY = "crash-reports/pending"
        const val SENTRY_CACHE_DIRECTORY = "sentry"
        const val SENTRY_OUTBOX_DIRECTORY = "outbox"
        const val SHARE_DIRECTORY = "crash-reports-share"
        const val MAX_REPORT_COUNT = 5
        const val SENTRY_CACHE_SCAN_DEPTH = 4
        const val MAX_ENVELOPE_HEADER_LINES = 8
        val EVENT_ITEM_PATTERN = Regex("\\\"type\\\"\\s*:\\s*\\\"event\\\"")
    }
}
