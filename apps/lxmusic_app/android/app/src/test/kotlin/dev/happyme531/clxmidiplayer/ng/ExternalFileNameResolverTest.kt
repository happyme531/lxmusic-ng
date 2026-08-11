package dev.happyme531.clxmidiplayer.ng

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ExternalFileNameResolverTest {
    @Test
    fun preservesSupportedUnicodeFileName() {
        assertEquals(
            "天空é.mid",
            ExternalFileNameResolver.resolve("天空é.mid", "application/octet-stream"),
        )
    }

    @Test
    fun addsSuffixFromRegisteredMimeType() {
        assertEquals(
            "score.json",
            ExternalFileNameResolver.resolve("score", "application/json"),
        )
        assertEquals(
            "archive.zip",
            ExternalFileNameResolver.resolve("archive", "application/x-zip-compressed"),
        )
    }

    @Test
    fun rejectsUnknownNameAndMimeType() {
        assertNull(ExternalFileNameResolver.resolve("manual.pdf", "application/pdf"))
    }
}
