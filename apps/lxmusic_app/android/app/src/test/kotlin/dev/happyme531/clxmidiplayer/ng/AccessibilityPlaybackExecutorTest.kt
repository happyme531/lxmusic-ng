package dev.happyme531.clxmidiplayer.ng

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class AccessibilityPlaybackExecutorTest {
    @Test
    fun actionsFromPreservesCompilerBatchDelays() {
        val actions = plan(
            action(
                atMs = 100L,
                point(10f, 20f, delayMs = 0L),
                point(30f, 40f, delayMs = 8L),
            ),
        ).actionsFrom(positionMs = 0L)

        assertEquals(1, actions.size)
        assertEquals(100L, actions.single().atMs)
        assertEquals(listOf(0L, 8L), actions.single().points.map { it.delayMs })
    }

    @Test
    fun actionsFromFiltersSeekedPointsAndRebasesRemainingBatch() {
        val actions = plan(
            action(
                atMs = 100L,
                point(10f, 20f, delayMs = 0L),
                point(30f, 40f, delayMs = 8L),
            ),
        ).actionsFrom(positionMs = 105L)

        assertEquals(1, actions.size)
        assertEquals(108L, actions.single().atMs)
        assertEquals(listOf(0L), actions.single().points.map { it.delayMs })
        assertEquals(30f, actions.single().points.single().x)
    }

    @Test
    fun actionsFromDoesNotMergeOriginalCompilerActions() {
        val actions = plan(
            action(atMs = 100L, point(10f, 20f, delayMs = 0L)),
            action(atMs = 100L, point(30f, 40f, delayMs = 0L)),
        ).actionsFrom(positionMs = 0L)

        assertEquals(2, actions.size)
        assertEquals(listOf(100L, 100L), actions.map { it.atMs })
    }

    @Test
    fun wallClockOffsetIsNotScaledByPlaybackSpeed() {
        val delayMs = AccessibilityPlaybackTiming.delayUntilPlanTime(
            nowRealtimeMs = 1_000L,
            originRealtimeMs = 1_000L,
            originPlanMs = 0L,
            targetPlanMs = 100L,
            speed = 2.0,
            wallClockOffsetMs = 100L,
        )

        assertEquals(150L, delayMs)
        assertEquals(12L, AccessibilityPlaybackTiming.tapDurationForGesture(12L))
    }

    @Test
    fun negativeWallClockOffsetClampsAnOverdueActionToNow() {
        val delayMs = AccessibilityPlaybackTiming.delayUntilPlanTime(
            nowRealtimeMs = 1_000L,
            originRealtimeMs = 1_000L,
            originPlanMs = 0L,
            targetPlanMs = 100L,
            speed = 2.0,
            wallClockOffsetMs = -100L,
        )

        assertEquals(0L, delayMs)
    }

    @Test
    fun parserRejectsUnboundedDelayedTaps() {
        assertThrows(IllegalArgumentException::class.java) {
            plan(
                action(atMs = 100L, point(10f, 20f, delayMs = 33L)),
            )
        }
    }

    @Test
    fun parserAcceptsBoundedNativeHoldPoints() {
        val parsed = plan(
            gestureAction(
                atMs = 100L,
                point(10f, 20f, delayMs = 0L, durationMs = 800L),
                point(30f, 40f, delayMs = 400L, durationMs = 500L),
            ),
        )

        assertEquals(listOf(800L, 500L), parsed.actions.single().points.map { it.durationMs })
    }

    @Test
    fun parserRejectsUnboundedNativeHoldPoints() {
        assertThrows(IllegalArgumentException::class.java) {
            plan(
                gestureAction(
                    atMs = 100L,
                    point(10f, 20f, delayMs = 0L, durationMs = 10_001L),
                ),
            )
        }
    }

    @Test
    fun anyCalibrationSurfaceBlocksPlayback() {
        assertFalse(AccessibilityPlaybackSafety.calibrationActive(false, false, false))
        assertTrue(AccessibilityPlaybackSafety.calibrationActive(true, false, false))
        assertTrue(AccessibilityPlaybackSafety.calibrationActive(false, true, false))
        assertTrue(AccessibilityPlaybackSafety.calibrationActive(false, false, true))
    }

    private fun plan(
        vararg actions: Map<String, Any?>,
    ): AccessibilityPlaybackExecutor.PlaybackPlan =
        AccessibilityPlaybackExecutor.PlaybackPlan.from(
            mapOf(
                "backendId" to "android-accessibility",
                "totalDurationMs" to 1_000L,
                "actions" to actions.toList(),
            ),
        )

    private fun action(
        atMs: Long,
        vararg points: Map<String, Any?>,
    ): Map<String, Any?> = mapOf(
        "kind" to "touchPoints",
        "atMs" to atMs,
        "payload" to mapOf(
            "calibrated" to true,
            "points" to points.toList(),
        ),
    )

    private fun gestureAction(
        atMs: Long,
        vararg points: Map<String, Any?>,
    ): Map<String, Any?> = mapOf(
        "kind" to "touchGesture",
        "atMs" to atMs,
        "payload" to mapOf(
            "calibrated" to true,
            "points" to points.toList(),
        ),
    )

    private fun point(
        x: Float,
        y: Float,
        delayMs: Long,
        durationMs: Long? = null,
    ): Map<String, Any?> = buildMap {
        put("x", x)
        put("y", y)
        put("delayMs", delayMs)
        if (durationMs != null) put("durationMs", durationMs)
    }
}
