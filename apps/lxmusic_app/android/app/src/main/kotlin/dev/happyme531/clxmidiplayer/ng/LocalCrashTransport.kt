package dev.happyme531.clxmidiplayer.ng

import android.content.Context
import io.sentry.Hint
import io.sentry.ITransportFactory
import io.sentry.RequestDetails
import io.sentry.SentryEnvelope
import io.sentry.SentryOptions
import io.sentry.hints.DiskFlushNotification
import io.sentry.hints.Retryable
import io.sentry.hints.SubmissionResult
import io.sentry.transport.ITransport
import io.sentry.transport.RateLimiter
import io.sentry.util.HintUtils
import java.io.IOException

internal class LocalCrashTransportFactory(
    context: Context,
) : ITransportFactory {
    private val store = LocalCrashReportStore(context.applicationContext)

    override fun create(
        options: SentryOptions,
        requestDetails: RequestDetails,
    ): ITransport = LocalCrashTransport(store, options)
}

/** Persists Sentry envelopes locally instead of opening a network connection. */
private class LocalCrashTransport(
    private val store: LocalCrashReportStore,
    private val options: SentryOptions,
) : ITransport {
    override fun send(envelope: SentryEnvelope, hint: Hint) {
        try {
            store.writeEnvelope(envelope, options.serializer)
            markHandled(hint, success = true, retry = false)
        } catch (error: Exception) {
            markHandled(hint, success = false, retry = true)
            if (error is IOException) throw error
            throw IOException("Failed to persist local crash report", error)
        }
    }

    private fun markHandled(hint: Hint, success: Boolean, retry: Boolean) {
        val sdkHint = HintUtils.getSentrySdkHint(hint)
        (sdkHint as? SubmissionResult)?.setResult(success)
        (sdkHint as? Retryable)?.setRetry(retry)
        if (success) {
            (sdkHint as? DiskFlushNotification)?.markFlushed()
        }
    }

    override fun flush(timeoutMillis: Long) = Unit

    override fun getRateLimiter(): RateLimiter? = null

    override fun isHealthy(): Boolean = true

    override fun close() = Unit

    override fun close(isRestarting: Boolean) = Unit
}
