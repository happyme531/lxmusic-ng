package dev.happyme531.clxmidiplayer.ng

import java.util.Locale

internal object ExternalFileNameResolver {
    private val supportedSuffixes = listOf(".midi", ".json", ".mid", ".txt", ".zip")
    private val invalidFileNameCharacters = Regex("[\\u0000-\\u001f\\\\/:*?\"<>|]")

    fun resolve(displayName: String?, mimeType: String?): String? {
        val safeName = displayName
            ?.replace('\\', '/')
            ?.substringAfterLast('/')
            ?.replace(invalidFileNameCharacters, "_")
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: "外部文件"
        val lowerName = safeName.lowercase(Locale.ROOT)
        if (supportedSuffixes.any(lowerName::endsWith)) {
            return safeName
        }

        val suffix = when (mimeType?.substringBefore(';')?.trim()?.lowercase(Locale.ROOT)) {
            "audio/midi", "audio/x-midi", "audio/sp-midi",
            "application/midi", "application/x-midi" -> ".mid"
            "application/json", "text/json" -> ".json"
            "text/plain" -> ".txt"
            "application/zip", "application/x-zip-compressed", "multipart/x-zip" -> ".zip"
            else -> null
        }
        return suffix?.let { "$safeName$it" }
    }

    fun maxSourceBytes(fileName: String): Long =
        if (fileName.lowercase(Locale.ROOT).endsWith(".zip")) {
            8L * 1024 * 1024 * 1024
        } else {
            64L * 1024 * 1024
        }
}
