package dev.happyme531.clxmidiplayer.ng

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

internal object ExternalFileOpenCoordinator {
    const val CHANNEL_NAME = "dev.happyme531.clxmidiplayer.ng/external_file_open"

    private const val CACHE_DIRECTORY = "external_file_open"
    private const val CACHE_MAX_AGE_MS = 24L * 60 * 60 * 1000
    private const val COPY_BUFFER_BYTES = 128 * 1024

    private val lock = Any()
    private val pending = mutableListOf<Map<String, Any?>>()
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val sequence = AtomicLong()
    private var channel: MethodChannel? = null
    private var cacheCleaned = false

    fun attach(channel: MethodChannel) {
        synchronized(lock) {
            this.channel = channel
        }
    }

    fun detach(channel: MethodChannel) {
        synchronized(lock) {
            if (this.channel === channel) {
                this.channel = null
            }
        }
    }

    fun enqueue(context: Context, intent: Intent): Boolean {
        if (intent.action != Intent.ACTION_VIEW) return false
        val uris = linkedSetOf<Uri>()
        intent.data?.let(uris::add)
        intent.clipData?.let { clipData ->
            for (index in 0 until clipData.itemCount) {
                clipData.getItemAt(index).uri?.let(uris::add)
            }
        }
        if (uris.isEmpty()) return false

        val appContext = context.applicationContext
        val intentMimeType = intent.type
        for (uri in uris) {
            executor.execute {
                cleanCacheOnce(appContext)
                prepareFile(appContext, uri, intentMimeType)
            }
        }
        return true
    }

    fun consumePending(): List<Map<String, Any?>> = synchronized(lock) {
        pending.toList().also { pending.clear() }
    }

    fun releaseCachedFiles(context: Context, paths: List<String>) {
        val appContext = context.applicationContext
        executor.execute {
            val root = cacheRoot(appContext).canonicalFile
            val rootPrefix = root.path + File.separator
            for (path in paths) {
                try {
                    val file = File(path).canonicalFile
                    if (file.path.startsWith(rootPrefix)) {
                        file.delete()
                    }
                } catch (_: Exception) {
                    // Best-effort cleanup after the Dart importer has copied the file.
                }
            }
        }
    }

    private fun prepareFile(context: Context, uri: Uri, intentMimeType: String?) {
        val metadata = queryMetadata(context, uri)
        val mimeType = try {
            context.contentResolver.getType(uri) ?: intentMimeType
        } catch (_: Exception) {
            intentMimeType
        }
        val fileName = ExternalFileNameResolver.resolve(metadata.displayName, mimeType)
        if (fileName == null) {
            offer(
                mapOf(
                    "fileName" to (metadata.displayName ?: "外部文件"),
                    "errorMessage" to "该文件不是受支持的 MID、JSON、TXT 或 ZIP 格式。",
                ),
            )
            return
        }

        val maxBytes = ExternalFileNameResolver.maxSourceBytes(fileName)
        if (metadata.size != null && metadata.size > maxBytes) {
            offer(sizeFailure(fileName, maxBytes))
            return
        }

        val root = cacheRoot(context)
        root.mkdirs()
        val target = File(
            root,
            "${System.currentTimeMillis()}_${sequence.incrementAndGet()}",
        )
        try {
            val input = context.contentResolver.openInputStream(uri)
                ?: throw IllegalStateException("content resolver returned no stream")
            input.use { source ->
                target.outputStream().buffered(COPY_BUFFER_BYTES).use { output ->
                    val buffer = ByteArray(COPY_BUFFER_BYTES)
                    var copied = 0L
                    while (true) {
                        val count = source.read(buffer)
                        if (count < 0) break
                        copied += count
                        if (copied > maxBytes) {
                            throw SourceTooLargeException()
                        }
                        output.write(buffer, 0, count)
                    }
                }
            }
            offer(
                mapOf(
                    "fileName" to fileName,
                    "path" to target.path,
                ),
            )
        } catch (_: SourceTooLargeException) {
            target.delete()
            offer(sizeFailure(fileName, maxBytes))
        } catch (_: Exception) {
            target.delete()
            offer(
                mapOf(
                    "fileName" to fileName,
                    "errorMessage" to "无法读取外部应用提供的文件。",
                ),
            )
        }
    }

    private fun queryMetadata(context: Context, uri: Uri): SourceMetadata {
        var displayName: String? = null
        var size: Long? = null
        try {
            context.contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (nameIndex >= 0 && !cursor.isNull(nameIndex)) {
                        displayName = cursor.getString(nameIndex)
                    }
                    val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) {
                        size = cursor.getLong(sizeIndex)
                    }
                }
            }
        } catch (_: Exception) {
            // Some providers reject metadata queries but still expose a stream.
        }
        return SourceMetadata(
            displayName = displayName ?: uri.lastPathSegment,
            size = size,
        )
    }

    private fun sizeFailure(fileName: String, maxBytes: Long): Map<String, Any?> =
        mapOf(
            "fileName" to fileName,
            "errorMessage" to if (maxBytes >= 1024L * 1024 * 1024) {
                "外部 ZIP 文件超过 ${maxBytes / (1024L * 1024 * 1024)} GiB 安全上限。"
            } else {
                "外部乐谱文件超过 ${maxBytes / (1024L * 1024)} MiB 安全上限。"
            },
        )

    private fun offer(value: Map<String, Any?>) {
        synchronized(lock) {
            pending.add(value)
        }
        mainHandler.post {
            val attached = synchronized(lock) { channel }
            attached?.invokeMethod("externalFilesAvailable", null)
        }
    }

    private fun cleanCacheOnce(context: Context) {
        synchronized(lock) {
            if (cacheCleaned) return
            cacheCleaned = true
        }
        val cutoff = System.currentTimeMillis() - CACHE_MAX_AGE_MS
        cacheRoot(context).listFiles()?.forEach { file ->
            if (file.lastModified() < cutoff) {
                file.delete()
            }
        }
    }

    private fun cacheRoot(context: Context): File = File(context.cacheDir, CACHE_DIRECTORY)

    private data class SourceMetadata(
        val displayName: String?,
        val size: Long?,
    )

    private class SourceTooLargeException : Exception()
}
