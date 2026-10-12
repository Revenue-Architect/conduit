package app.cogwheel.conduit

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.ContactsContract
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.core.content.ContextCompat
import androidx.work.*
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.net.URL
import java.time.Instant
import java.time.LocalDate
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import javax.net.ssl.HttpsURLConnection

internal const val TEXT_RELAY = "https://umbrel.tail4c9e01.ts.net:8448"
internal val otpText = Regex("\\b(?:otp|verification|verify|authentication|security|one[ -]time|2fa|passcode|login|sign[ -]?in|confirmation)\\b.{0,100}\\b\\d{4,8}\\b|\\b\\d{4,8}\\b.{0,100}\\b(?:code|otp|verification|passcode)\\b", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL))
internal fun isFilteredText(text: String, address: String): Boolean =
    otpText.containsMatchIn(text) || text.trim().matches(Regex("\\d{4,8}")) ||
    address.filter(Char::isDigit).length in 1..6 || address.any(Char::isLetter)
internal fun acknowledgedBatch(status: Int, accepted: Int, submitted: Int) = status == 202 && accepted == submitted

/** One encrypted JSON preference, backed by Android Keystore. No raw credentials in ordinary prefs. */
internal class TextSharingStore(private val context: Context) {
    private val prefs = context.getSharedPreferences("hermes-text-sharing", Context.MODE_PRIVATE)
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey("hermes-text-sharing-v1", null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder("hermes-text-sharing-v1", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    fun read(): JSONObject {
        val raw = prefs.getString("encrypted", null) ?: return JSONObject()
        val parts = raw.split(":")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)))
        return JSONObject(String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), Charsets.UTF_8))
    }
    fun write(value: JSONObject) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, key())
        val raw = Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" +
            Base64.encodeToString(cipher.doFinal(value.toString().toByteArray()), Base64.NO_WRAP)
        check(prefs.edit().putString("encrypted", raw).commit()) { "Text-sharing state could not be saved" }
    }
}

internal fun relayPost(path: String, value: JSONObject, token: String? = null): Pair<Int, JSONObject> {
    val connection = URL(TEXT_RELAY + path).openConnection() as HttpsURLConnection
    connection.instanceFollowRedirects = false
    connection.requestMethod = "POST"; connection.connectTimeout = 20000; connection.readTimeout = 30000
    connection.doOutput = true; connection.setRequestProperty("Content-Type", "application/json")
    if (token != null) connection.setRequestProperty("Authorization", "Bearer $token")
    try {
        connection.outputStream.use { it.write(value.toString().toByteArray()) }
        val status = connection.responseCode
        if (status !in 200..299) return status to JSONObject()
        return status to JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
    } finally { connection.disconnect() }
}

internal object TextSharingRuntime {
    val lock = Any()
    fun schedule(context: Context, periodic: Boolean = true) {
        val constraints = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()
        if (periodic) WorkManager.getInstance(context).enqueueUniquePeriodicWork("hermes-texts-periodic", ExistingPeriodicWorkPolicy.KEEP,
            PeriodicWorkRequestBuilder<TextSyncWorker>(15, TimeUnit.MINUTES).setConstraints(constraints)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS).build())
        WorkManager.getInstance(context).enqueueUniqueWork("hermes-texts-now", ExistingWorkPolicy.KEEP,
            OneTimeWorkRequestBuilder<TextSyncWorker>().setConstraints(constraints)
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST).build())
    }
    fun cancel(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork("hermes-texts-periodic")
        WorkManager.getInstance(context).cancelUniqueWork("hermes-texts-now")
    }
}

class TextSyncWorker(context: Context, params: WorkerParameters): Worker(context, params) {
    override fun doWork(): Result = synchronized(TextSharingRuntime.lock) {
        val store = TextSharingStore(applicationContext)
        try {
            val state = store.read()
            val effectiveSharing = state.optBoolean("enabled") && state.optLong("pausedUntil") <= System.currentTimeMillis()
            if (state.has("token") && (!state.has("reportedSharing") || state.optBoolean("reportedSharing") != effectiveSharing)) state.put("pendingSharingStatus", effectiveSharing)
            if (state.has("pendingSharingStatus") && state.has("token")) {
                val target = state.getBoolean("pendingSharingStatus")
                check(relayPost("/v1/sharing", JSONObject().put("enabled", target), state.getString("token")).first == 200)
                state.put("reportedSharing", target).remove("pendingSharingStatus"); store.write(state)
            }
            if (!state.optBoolean("enabled") || state.optLong("pausedUntil") > System.currentTimeMillis()) return@synchronized Result.success()
            if (ContextCompat.checkSelfPermission(applicationContext, Manifest.permission.READ_SMS) != PackageManager.PERMISSION_GRANTED ||
                ContextCompat.checkSelfPermission(applicationContext, Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) {
                state.put("error", "Allow message and contact access in Settings"); store.write(state); return@synchronized Result.success()
            }
            val reader = PhoneTextReader(applicationContext, state.getString("salt"))
            // Separate tables and cursors. Omitted/filtered rows advance only with their acknowledged batch.
            for (table in listOf("sms", "mms")) {
                val cursor = state.optLong("cursor_$table")
                val batch = reader.read(table, cursor, state.optLong("backfillSince", System.currentTimeMillis() - TimeUnit.DAYS.toMillis(14)))
                if (batch.lastId == cursor) continue
                if (batch.messages.length() > 0) {
                    val (status, reply) = relayPost("/v1/messages", JSONObject().put("messages", batch.messages), state.getString("token"))
                    if (!acknowledgedBatch(status, reply.optInt("accepted", -1), batch.messages.length())) throw IllegalStateException("Text relay did not acknowledge this batch")
                }
                // The user can disable sharing while HTTP is running; all control changes share this lock.
                state.put("cursor_$table", batch.lastId)
                if (state.optString("countDay") != LocalDate.now().toString()) state.put("sentToday", 0)
                state.put("countDay", LocalDate.now().toString()).put("sentToday", state.optInt("sentToday") + batch.messages.length())
                state.put("lastSync", Instant.now().toString()).remove("error"); store.write(state)
                if (batch.scanned == 500) TextSharingRuntime.schedule(applicationContext, false)
            }
            Result.success()
        } catch (_: Exception) {
            try { val state = store.read(); state.put("error", "Sync could not finish. Your messages are kept for retry."); store.write(state) } catch (_: Exception) {}
            Result.retry()
        }
    }
}

internal data class PhoneTextBatch(val messages: JSONArray, val lastId: Long, val scanned: Int)
internal class PhoneTextReader(private val context: Context, private val salt: String) {
    private val resolver = context.contentResolver
    private val nameCache = mutableMapOf<String, JSONObject>()
    private val threadCache = mutableMapOf<Long, List<String>>()
    private fun normalize(address: String): String {
        val digits = address.filter(Char::isDigit)
        return when { address.startsWith("+") -> "+$digits"; digits.length == 10 -> "+1$digits"; else -> "+$digits" }
    }
    private fun participant(address: String): JSONObject {
        nameCache[address]?.let { return it }
        val normalized = normalize(address)
        val mac = Mac.getInstance("HmacSHA256").apply { init(SecretKeySpec(salt.toByteArray(), "HmacSHA256")) }
        val digest = mac.doFinal(normalized.toByteArray()).joinToString("") { "%02x".format(it) }
        var name = "Unknown contact"
        resolver.query(Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(address)),
            arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) name = c.getString(0) ?: name
        }
        if (name.matches(Regex("[+\\d\\s().-]{6,}"))) name = "Unknown contact"
        return JSONObject().put("name", name).put("handle_hmac", digest).also { nameCache[address] = it }
    }
    private fun recipients(thread: Long): List<String> = threadCache.getOrPut(thread) {
        val ids = mutableListOf<String>()
        resolver.query(Uri.parse("content://mms-sms/conversations?simple=true"), arrayOf("recipient_ids"), "_id=?", arrayOf(thread.toString()), null)?.use { c ->
            if (c.moveToFirst()) ids.addAll((c.getString(0) ?: "").split(" ").filter { it.matches(Regex("\\d+")) })
        }
        ids.mapNotNull { id ->
            var address: String? = null
            resolver.query(Uri.parse("content://mms-sms/canonical-addresses"), arrayOf("address"), "_id=?", arrayOf(id), null)?.use { c ->
                if (c.moveToFirst()) address = c.getString(0)
            }
            address?.takeIf { it.isNotBlank() && it != "insert-address-token" }
        }.distinct().sorted()
    }
    private fun threadRef(addresses: List<String>): String {
        val mac = Mac.getInstance("HmacSHA256").apply { init(SecretKeySpec(salt.toByteArray(), "HmacSHA256")) }
        return mac.doFinal(addresses.map(::normalize).distinct().sorted().joinToString("|").toByteArray())
            .joinToString("") { "%02x".format(it) }.take(24)
    }
    fun read(table: String, after: Long, backfillSince: Long): PhoneTextBatch {
        val sms = table == "sms"
        val columns = if (sms) arrayOf("_id", "address", "date", "type", "body", "thread_id") else arrayOf("_id", "date", "msg_box", "thread_id")
        val batch = JSONArray(); var last = after; var scanned = 0
        resolver.query(Uri.parse("content://$table"), columns, "_id > ? AND date >= ?",
            arrayOf(after.toString(), (if (sms) backfillSince else backfillSince / 1000).toString()), "_id ASC")?.use { c ->
            while (scanned < 500 && c.moveToNext()) {
                val id = c.getLong(0); last = id; scanned++
                var address = ""; var text = ""; val attachments = JSONArray(); val participants = JSONArray()
                val at: Long; val direction: Int
                if (sms) {
                    address = c.getString(1) ?: ""; at = c.getLong(2); direction = c.getInt(3); text = c.getString(4) ?: ""
                    if (address.isNotBlank()) participants.put(participant(address))
                } else {
                    at = c.getLong(1) * 1000; direction = c.getInt(2)
                    resolver.query(Uri.parse("content://mms/$id/addr"), arrayOf("address", "type"), null, null, null)?.use { a ->
                        while (a.moveToNext()) {
                            val addr = a.getString(0) ?: ""
                            if (addr != "insert-address-token" && addr.isNotBlank() && !isFilteredText("", addr)) {
                                if (address.isBlank() || (direction == 1 && a.getInt(1) == 137)) address = addr
                                participants.put(participant(addr))
                            }
                        }
                    }
                    resolver.query(Uri.parse("content://mms/$id/part"), arrayOf("_id", "ct", "text", "_data"), null, null, null)?.use { p ->
                        val parts = mutableListOf<String>()
                        while (p.moveToNext()) {
                            val mime = p.getString(1) ?: ""
                            if (mime == "text/plain") {
                                val content = if (!p.isNull(3)) resolver.openInputStream(Uri.parse("content://mms/part/${p.getLong(0)}"))?.bufferedReader()?.use { it.readText() } else p.getString(2)
                                if (!content.isNullOrBlank()) parts.add(content)
                            } else if (mime != "application/smil") attachments.put(JSONObject().put("mime", mime))
                        }
                        text = parts.joinToString("\n")
                    }
                }
                if (direction !in 1..2 || participants.length() == 0 || isFilteredText(text, address)) continue
                val canonical = recipients(c.getLong(if (sms) 5 else 3)).ifEmpty { listOf(address) }
                val threadParticipants = JSONArray()
                for (recipient in canonical) threadParticipants.put(participant(recipient))
                // Never clip a message and advance its cursor: an oversized row must remain retryable.
                require(text.toByteArray().size <= 8192) { "Text exceeds relay limit" }
                batch.put(JSONObject().put("key", "$table:$id").put("direction", if (direction == 1) "in" else "out")
                    .put("at", Instant.ofEpochMilli(at).toString()).put("text", text).put("participants", threadParticipants)
                    .put("thread_ref", threadRef(canonical))
                    .put("kind", if (sms) "sms" else "rcs-text").put("attachments", attachments))
            }
        }
        return PhoneTextBatch(batch, last, scanned)
    }
}

class TextSharingWakeReceiver: BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == "android.provider.Telephony.SMS_RECEIVED") {
            try { if (TextSharingStore(context).read().optBoolean("enabled")) TextSharingRuntime.schedule(context, false) } catch (_: Exception) {}
        }
    }
}

internal class TextSharingBridge(private val context: Context) {
    private val executor = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private val observer = object: ContentObserver(handler) {
        override fun onChange(selfChange: Boolean) { wake() }
    }
    private var observed = false
    fun setup(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "app.cogwheel.conduit/text-sharing").setMethodCallHandler { call, result ->
            executor.execute {
                try {
                    val value = synchronized(TextSharingRuntime.lock) {
                        val store = TextSharingStore(context); val state = store.read()
                        when (call.method) {
                            "enroll" -> {
                                val (code, enrolled) = relayPost("/v1/enroll", JSONObject().put("code", call.argument<String>("code")))
                                check(code == 200 && enrolled.has("token") && enrolled.has("salt")) { "Pairing code expired or unavailable" }
                                state.put("token", enrolled.getString("token")).put("salt", enrolled.getString("salt"))
                                    .put("backfillSince", System.currentTimeMillis() - TimeUnit.DAYS.toMillis(14)).put("enabled", false)
                                store.write(state)
                            }
                            "setEnabled" -> {
                                val enabled = call.argument<Boolean>("enabled") == true
                                check(!enabled || state.has("token")) { "Pair this phone first" }
                                state.put("enabled", enabled).put("pausedUntil", 0).put("pendingSharingStatus", enabled); store.write(state)
                                if (enabled) TextSharingRuntime.schedule(context) else {
                                    TextSharingRuntime.cancel(context); TextSharingRuntime.schedule(context, false)
                                }
                            }
                            "pause" -> { state.put("pausedUntil", System.currentTimeMillis() + TimeUnit.HOURS.toMillis(24)).put("pendingSharingStatus", false); store.write(state); TextSharingRuntime.schedule(context, false) }
                            "forget" -> {
                                if (state.has("token")) check(relayPost("/v1/forget", JSONObject(), state.getString("token")).first == 200) { "Connect to forget this device" }
                                store.write(JSONObject()); TextSharingRuntime.cancel(context)
                            }
                            "sync" -> if (state.optBoolean("enabled")) TextSharingRuntime.schedule(context, false)
                            "status" -> Unit
                            else -> throw IllegalArgumentException("Unknown text-sharing action")
                        }
                        val current = store.read()
                        mapOf("paired" to current.has("token"), "enabled" to current.optBoolean("enabled"),
                            "pausedUntil" to current.optLong("pausedUntil"), "lastSync" to current.optString("lastSync"),
                            "sentToday" to if (current.optString("countDay") == LocalDate.now().toString()) current.optInt("sentToday") else 0,
                            "error" to current.optString("error"))
                    }
                    handler.post { result.success(value); observeIfEnabled() }
                } catch (_: Exception) { handler.post { result.error("text_sharing", "Text sharing could not finish. Check the connection and pairing code.", null) } }
            }
        }
        observeIfEnabled(); wake()
    }
    private fun observeIfEnabled() {
        try {
            val enabled = TextSharingStore(context).read().optBoolean("enabled")
            if (enabled && !observed) { context.contentResolver.registerContentObserver(Uri.parse("content://mms-sms/"), true, observer); observed = true }
            if (!enabled && observed) { context.contentResolver.unregisterContentObserver(observer); observed = false }
        } catch (_: Exception) {}
    }
    fun wake() { try { if (TextSharingStore(context).read().optBoolean("enabled")) TextSharingRuntime.schedule(context, false) } catch (_: Exception) {} }
    fun dispose() { if (observed) context.contentResolver.unregisterContentObserver(observer); executor.shutdown() }
}
