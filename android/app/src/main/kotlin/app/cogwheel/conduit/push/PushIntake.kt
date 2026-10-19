package app.cogwheel.conduit.push

import android.content.Context
import android.util.Log

/**
 * The one place an accepted push is acted on. [authenticated] is true only
 * for envelopes the connector decrypted (RFC 8291 gives message authenticity);
 * everything else renders as the generic notice or not at all.
 */
internal object PushIntake {
    private const val TAG = "PushIntake"

    fun handle(
        context: Context,
        envelope: PushEnvelope,
        raw: String,
        nowMs: Long = System.currentTimeMillis(),
    ) {
        val store = PushStore.get(context)
        val nowSeconds = nowMs / 1000L

        if (PushPolicy.isExpired(envelope, nowSeconds)) {
            Log.i(TAG, "drop expired envelope type=${envelope.type.wire}")
            return
        }
        if (!store.markFresh(envelope.id)) {
            Log.i(TAG, "drop duplicate envelope type=${envelope.type.wire}")
            return
        }
        if (envelope.ack || envelope.type == PushType.PROBE) {
            store.queueAck(envelope.id)
            PushWork.enqueueAck(context)
        }

        when (envelope.type) {
            PushType.PROBE -> Unit // the ack above is the whole answer
            PushType.VERIFY -> envelope.nonce?.let { PushWork.enqueueVerify(context, it) }
            PushType.DISMISS -> {
                PushRenderer(context).cancel(envelope.effectiveTag)
                PushRuntime.statusChanged()
            }
            PushType.UPDATE -> if (allowed(store, envelope)) {
                PushRenderer(context).showUpdate(envelope)
                PushRuntime.statusChanged()
            }
            PushType.NOTIFY -> if (allowed(store, envelope)) {
                // In the foreground, Dart draws the in-app banner instead of
                // a shade entry; with no engine attached, post to the shade.
                if (PushRuntime.isForeground && PushRuntime.withFlutter { it.onForegroundEnvelope(raw) {} }) {
                    Log.i(TAG, "forwarded to Dart category=${envelope.category.wire}")
                } else {
                    PushRenderer(context).show(envelope, nowSeconds)
                }
            }
        }
    }

    private fun allowed(store: PushStore, envelope: PushEnvelope): Boolean =
        PushPolicy.isCategoryAllowed(envelope.category, store.enabled, store.disabledCategories)
}
