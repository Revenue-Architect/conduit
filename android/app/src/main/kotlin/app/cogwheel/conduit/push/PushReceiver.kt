package app.cogwheel.conduit.push

import android.content.Context
import android.util.Log
import org.unifiedpush.android.connector.FailedReason
import org.unifiedpush.android.connector.MessagingReceiver
import org.unifiedpush.android.connector.UnifiedPush
import org.unifiedpush.android.connector.data.PushEndpoint
import org.unifiedpush.android.connector.data.PushMessage

/**
 * UnifiedPush entry point. The connector has already decrypted (or failed to
 * decrypt) the RFC 8291 message. Runs with no Flutter engine and keeps to the
 * short broadcast budget: parse, dedup, render; network work goes to WorkManager.
 *
 * Uses the connector's receiver base class (documented as still supported)
 * because it delivers synchronously inside the broadcast, which is what we
 * want while the app process may have just been started.
 */
@Suppress("DEPRECATION")
class PushReceiver : MessagingReceiver() {

    override fun onNewEndpoint(context: Context, endpoint: PushEndpoint, instance: String) {
        if (endpoint.temporary) {
            // A fallback distributor's endpoint: the primary will re-announce itself.
            Log.i(TAG, "ignoring temporary endpoint")
            return
        }
        val keys = endpoint.pubKeySet
        val store = PushStore.get(context)
        if (keys == null) {
            store.lastError = "endpoint_without_keys"
            PushRuntime.statusChanged()
            return
        }
        val saved = store.saveEndpoint(
            url = endpoint.url,
            pubKey = keys.pubKey,
            auth = keys.auth,
            distributor = UnifiedPush.getSavedDistributor(context),
        )
        Log.i(TAG, "new endpoint generation=${saved.generation}")
        PushWork.enqueueUpload(context)
        PushRuntime.withFlutter { it.onEndpoint(endpoint.url, "", "", saved.generation.toLong()) {} }
        PushRuntime.statusChanged()
    }

    override fun onMessage(context: Context, message: PushMessage, instance: String) {
        val store = PushStore.get(context)
        store.recordPush(System.currentTimeMillis())
        if (!message.decrypted) {
            // Could not be authenticated: no content, no actions (spec 7.4).
            Log.w(TAG, "undecrypted push size=${message.content.size}")
            if (store.enabled) PushRenderer(context).showGeneric()
            PushRuntime.statusChanged()
            return
        }
        val envelope = PushEnvelope.parse(message.content)
        if (envelope == null) {
            Log.w(TAG, "unparseable envelope size=${message.content.size}")
            return
        }
        PushIntake.handle(context, envelope, String(message.content, Charsets.UTF_8))
        PushRuntime.statusChanged()
    }

    override fun onRegistrationFailed(context: Context, reason: FailedReason, instance: String) {
        Log.w(TAG, "registration failed: $reason")
        PushStore.get(context).lastError = "registration_${reason.name.lowercase()}"
        PushRuntime.withFlutter { it.onRegistrationFailed(reason.name) {} }
        PushRuntime.statusChanged()
    }

    override fun onUnregistered(context: Context, instance: String) {
        Log.i(TAG, "unregistered")
        val store = PushStore.get(context)
        store.clearEndpoint()
        PushWork.enqueueDelete(context)
        PushRuntime.withFlutter { it.onUnregistered {} }
        PushRuntime.statusChanged()
    }

    override fun onTempUnavailable(context: Context, instance: String) {
        PushStore.get(context).tempUnavailable = true
        PushRuntime.statusChanged()
    }

    private companion object {
        const val TAG = "PushReceiver"
    }
}
