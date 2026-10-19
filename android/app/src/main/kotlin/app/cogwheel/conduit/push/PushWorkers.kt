package app.cogwheel.conduit.push

import android.content.Context
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import app.cogwheel.conduit.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/**
 * Endpoint upload, verify answer, batched acks and endpoint delete. All talk
 * to the phone gateway with the vault token. Failures retry with WorkManager
 * backoff; permanent failures are recorded in [PushStore.lastError] so the
 * health card can say what is wrong.
 */
class PushSyncWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val store = PushStore.get(applicationContext)
        val credentials = PushVault.get(applicationContext).load()
            ?: return@withContext Result.success() // not paired: nothing to sync yet
        val client = PushGatewayClient(credentials)
        try {
            when (inputData.getString(KEY_KIND)) {
                KIND_ACK -> ack(client, store)
                KIND_VERIFY -> verify(client, inputData.getString(KEY_NONCE))
                KIND_UPLOAD -> upload(client, store)
                KIND_DELETE -> delete(client, store)
                KIND_INBOX -> inbox(client, store)
                else -> Result.success()
            }
        } catch (_: IOException) {
            retryOrGiveUp(max = PushPolicy.UPLOAD_MAX_ATTEMPTS)
        }
    }

    private fun ack(client: PushGatewayClient, store: PushStore): Result {
        val ids = store.ackQueue()
        if (ids.isEmpty()) return Result.success()
        val body = JSONObject()
            .put("ids", org.json.JSONArray(ids))
            .put("rcv_ts", System.currentTimeMillis() / 1000L)
        val response = client.post("/push/ack", body)
        return when {
            response.code in 200..299 -> {
                store.removeAcks(ids)
                Result.success()
            }
            // The token is wrong or the ack is malformed: retrying cannot help.
            response.code in 400..499 && response.code != 408 && response.code != 429 -> {
                store.removeAcks(ids)
                Result.success()
            }
            else -> retryOrGiveUp(PushPolicy.ACK_MAX_ATTEMPTS)
        }
    }

    private fun inbox(client: PushGatewayClient, store: PushStore): Result {
        // Bound one worker's budget; a retry resumes from the last committed page.
        repeat(20) {
            val cursor = store.inboxCursor
            val query = cursor?.let { "&since=" + java.net.URLEncoder.encode(it, "UTF-8") } ?: ""
            val response = client.get("/inbox?limit=100$query")
            if (response.code == 401 || response.code == 403) {
                store.lastError = "gateway_unauthorized"
                PushRuntime.statusChanged()
                return Result.success()
            }
            if (response.code !in 200..299) return retryOrGiveUp(10)
            val page = PushInboxPage.parse(response.body) ?: return retryOrGiveUp(10)
            page.envelopes.forEach { (envelope, raw) ->
                PushIntake.handle(applicationContext, envelope, raw)
            }
            if (page.next != null) store.inboxCursor = page.next
            if (!page.more) return Result.success()
            if (page.next == null || page.next == cursor) return retryOrGiveUp(10)
        }
        return Result.retry()
    }

    private fun verify(client: PushGatewayClient, nonce: String?): Result {
        if (nonce.isNullOrEmpty()) return Result.success()
        val response = client.post("/push/verify", JSONObject().put("nonce", nonce))
        return when {
            response.code in 200..299 -> {
                PushRuntime.statusChanged()
                Result.success()
            }
            response.code in 400..499 && response.code != 408 && response.code != 429 -> Result.success()
            else -> retryOrGiveUp(5)
        }
    }

    private fun upload(client: PushGatewayClient, store: PushStore): Result {
        val endpoint = store.endpoint() ?: return Result.success()
        // The server accepts exactly these keys; the endpoint goes up exactly as
        // the distributor gave it (including any ?up=1).
        val body = JSONObject()
            .put("generation", endpoint.generation)
            .put("endpoint", endpoint.url)
            .put("p256dh", endpoint.pubKey)
            .put("auth", endpoint.auth)
            .put("instance", PushHostApiImpl.INSTANCE)
        endpoint.distributor?.takeIf { it.isNotEmpty() }?.let { body.put("distributor", it) }
        val response = client.put("/devices/me/push", body)
        return when {
            response.code in 200..299 -> {
                val reply = response.json()
                if (reply?.optBoolean("ignored", false) == true) {
                    // The server already knows a newer generation: move past it and retry.
                    store.raiseGeneration(reply.optInt("generation", endpoint.generation) + 1)
                    return retryOrGiveUp(PushPolicy.UPLOAD_MAX_ATTEMPTS)
                }
                store.markUploaded(System.currentTimeMillis())
                PushRuntime.statusChanged()
                Result.success()
            }
            response.code == 401 || response.code == 403 -> {
                store.lastError = "gateway_unauthorized"
                PushRuntime.statusChanged()
                Result.success()
            }
            response.code in 400..499 && response.code != 408 && response.code != 429 -> {
                // 400/409 (topic_in_use, topic_retired, topic_key_mismatch, ...) are real rejections.
                store.lastError = "endpoint_rejected_${response.code}"
                PushRuntime.statusChanged()
                Result.success()
            }
            else -> {
                store.lastError = "gateway_unavailable"
                retryOrGiveUp(PushPolicy.UPLOAD_MAX_ATTEMPTS)
            }
        }
    }

    private fun delete(client: PushGatewayClient, store: PushStore): Result {
        // Best effort: the server also notices the dead endpoint through missed probes.
        val response = client.delete("/devices/me/push")
        store.lastError = null
        return if (response.code in 500..599) retryOrGiveUp(3) else Result.success()
    }

    private fun retryOrGiveUp(max: Int): Result =
        if (runAttemptCount + 1 >= max) Result.failure() else Result.retry()

    companion object {
        const val KEY_KIND = "kind"
        const val KEY_NONCE = "nonce"
        const val KIND_ACK = "ack"
        const val KIND_VERIFY = "verify"
        const val KIND_UPLOAD = "upload"
        const val KIND_DELETE = "delete"
        const val KIND_INBOX = "inbox"
    }
}

/**
 * Runs an Approve / Deny / relay tap from the shade. For decisions it follows
 * the spec exactly: read the request from the gateway (still pending? same
 * digest?), then send one idempotent decision, then rewrite the notification.
 */
class ActionWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    private val renderer = PushRenderer(applicationContext)

    override suspend fun getForegroundInfo(): ForegroundInfo {
        PushChannels.ensure(applicationContext)
        val notification = NotificationCompat.Builder(applicationContext, PushCategory.STATUS.channelId)
            .setSmallIcon(R.drawable.ic_stat_hermez)
            .setContentTitle("Sending your answer")
            .setOngoing(true)
            .build()
        return ForegroundInfo(FOREGROUND_ID, notification)
    }

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        when (inputData.getString(KEY_KIND)) {
            KIND_DECIDE -> decide()
            KIND_RELAY -> relay()
            else -> Result.success()
        }
    }

    private fun decide(): Result {
        val approval = inputData.getString(KEY_APPROVAL) ?: return Result.success()
        val decision = inputData.getString(KEY_DECISION) ?: return Result.success()
        val digest = inputData.getString(KEY_DIGEST) ?: return Result.success()
        val tag = inputData.getString(KEY_TAG) ?: return Result.success()
        val retryAction = RetryAction.Decide(approval, decision, digest, tag, inputData.getString(KEY_ENVELOPE) ?: "")

        val credentials = PushVault.get(applicationContext).load()
        if (credentials == null) {
            finalState(tag, approval, PushShadeText.PAIRING_LOST)
            return Result.success()
        }
        val client = PushGatewayClient(credentials)
        return try {
            val detail = client.get("/approvals/$approval")
            when (PushPolicy.classifyDecisionResponse(detail.code)) {
                DecisionOutcome.DONE -> Unit
                DecisionOutcome.GONE -> {
                    finalState(tag, approval, PushShadeText.decided(StatusWord.EXPIRED, null))
                    return Result.success()
                }
                DecisionOutcome.UNAUTHORIZED -> {
                    finalState(tag, approval, PushShadeText.PAIRING_LOST)
                    return Result.success()
                }
                DecisionOutcome.RETRY -> return retryOrFail(tag, approval, retryAction)
                else -> {
                    finalState(tag, approval, "Could not read this request (${detail.code})")
                    return Result.success()
                }
            }
            val item = detail.json().let { it?.optJSONObject("item") ?: it }
            val description = PushJson.str(item, "description")
            val word = PushPolicy.statusWord(PushJson.str(item, "status"))
            if (word != StatusWord.PENDING) {
                finalState(tag, approval, PushShadeText.decided(word, description))
                return Result.success()
            }
            val serverDigest = PushJson.str(item, "payload_digest")
            if (serverDigest != null && !serverDigest.equals(digest, ignoreCase = true)) {
                // The request changed since this notification was built: never act on it.
                finalState(tag, approval, PushShadeText.CHANGED)
                return Result.success()
            }
            val deviceId = credentials.deviceId
            val response = client.post(
                "/approvals/$approval/decision",
                JSONObject().put("decision", decision).put("digest", digest),
                mapOf("Idempotency-Key" to "dec-$approval-$decision-$deviceId"),
            )
            when (PushPolicy.classifyDecisionResponse(response.code)) {
                DecisionOutcome.DONE -> {
                    val done = if (decision == "approve") StatusWord.APPROVED else StatusWord.DENIED
                    finalState(tag, approval, PushShadeText.decided(done, description))
                    PushRuntime.statusChanged()
                    Result.success()
                }
                DecisionOutcome.CONFLICT -> {
                    if (PushJson.str(response.json(), "error") == "digest_mismatch") {
                        finalState(tag, approval, PushShadeText.CHANGED)
                        return Result.success()
                    }
                    val current = PushPolicy.statusWord(PushJson.str(response.json(), "status"))
                    finalState(tag, approval, PushShadeText.decided(current, description))
                    Result.success()
                }
                DecisionOutcome.GONE -> {
                    finalState(tag, approval, PushShadeText.decided(StatusWord.EXPIRED, description))
                    Result.success()
                }
                DecisionOutcome.UNAUTHORIZED -> {
                    finalState(tag, approval, PushShadeText.PAIRING_LOST)
                    Result.success()
                }
                DecisionOutcome.RETRY -> retryOrFail(tag, approval, retryAction)
                DecisionOutcome.REJECTED -> {
                    finalState(tag, approval, "Hermes did not accept the answer (${response.code})")
                    Result.success()
                }
            }
        } catch (_: IOException) {
            retryOrFail(tag, approval, retryAction)
        }
    }

    private fun relay(): Result {
        val url = inputData.getString(KEY_URL) ?: return Result.success()
        val tag = inputData.getString(KEY_TAG) ?: return Result.success()
        val category = PushCategory.fromWire(inputData.getString(KEY_CATEGORY)) ?: PushCategory.STATUS
        val label = inputData.getString(KEY_LABEL) ?: "Done"
        // The URL came from an authenticated envelope, but check the pin again.
        if (!PushEnvelope.isRelayUrl(url)) return Result.success()
        return try {
            val code = postRelay(url)
            val text = if (code in 200..299) "Done" else "Hermes did not accept this ($code)"
            renderer.showActionState(tag, category, label, text, null)
            Result.success()
        } catch (_: IOException) {
            if (runAttemptCount + 1 >= PushPolicy.DECISION_MAX_ATTEMPTS) {
                renderer.showActionState(tag, category, label, PushShadeText.UNREACHABLE, null,
                    RetryAction.Relay(url, tag, category.wire, label))
                Result.success()
            } else {
                Result.retry()
            }
        }
    }

    private fun postRelay(url: String): Int {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.connectTimeout = 10_000
            connection.readTimeout = 10_000
            connection.instanceFollowRedirects = false
            connection.doOutput = true
            connection.setFixedLengthStreamingMode(0)
            connection.outputStream.close()
            return connection.responseCode
        } finally {
            connection.disconnect()
        }
    }

    private fun retryOrFail(tag: String, approval: String, retryAction: RetryAction.Decide): Result {
        if (runAttemptCount + 1 < PushPolicy.DECISION_MAX_ATTEMPTS) return Result.retry()
        renderer.showActionState(
            tag = tag,
            category = PushCategory.APPROVALS,
            title = "Approval",
            text = PushShadeText.UNREACHABLE,
            approvalId = approval,
            retry = retryAction,
        )
        return Result.success()
    }

    private fun finalState(tag: String, approval: String, text: String) {
        renderer.showActionState(
            tag = tag,
            category = PushCategory.APPROVALS,
            title = "Approval",
            text = text,
            approvalId = approval,
        )
    }

    companion object {
        const val KEY_KIND = "kind"
        const val KEY_APPROVAL = "approval"
        const val KEY_DECISION = "decision"
        const val KEY_DIGEST = "digest"
        const val KEY_TAG = "tag"
        const val KEY_ENVELOPE = "envelope"
        const val KEY_URL = "url"
        const val KEY_CATEGORY = "category"
        const val KEY_LABEL = "label"
        const val KIND_DECIDE = "decide"
        const val KIND_RELAY = "relay"
        private const val FOREGROUND_ID = 0x5A5A0002
    }
}
