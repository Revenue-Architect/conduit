package app.cogwheel.conduit.push

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray

/**
 * Plain (non-secret) push state: dedup memory, the latest endpoint, switches
 * and counters. Secrets live in [PushVault]. SharedPreferences is process-safe
 * enough here: writes come from the receiver, workers and the UI thread, all
 * through [lock].
 */
internal class PushStore private constructor(private val prefs: SharedPreferences) {

    data class Endpoint(
        val url: String,
        val pubKey: String,
        val auth: String,
        val generation: Int,
        val distributor: String?,
    )

    // ---- dedup -------------------------------------------------------------

    /** True when [id] had not been handled before (and records it). */
    fun markFresh(id: String): Boolean = synchronized(lock) {
        val set = DedupSet.parse(prefs.getString(KEY_DEDUP, null))
        val fresh = set.markFresh(id)
        if (fresh) prefs.edit().putString(KEY_DEDUP, set.serialize()).apply()
        fresh
    }

    // ---- endpoint ----------------------------------------------------------

    fun saveEndpoint(url: String, pubKey: String, auth: String, distributor: String?): Endpoint =
        synchronized(lock) {
            val generation = prefs.getInt(KEY_GENERATION, 0) + 1
            prefs.edit()
                .putString(KEY_EP_URL, url)
                .putString(KEY_EP_PUB, pubKey)
                .putString(KEY_EP_AUTH, auth)
                .putString(KEY_EP_DIST, distributor)
                .putInt(KEY_GENERATION, generation)
                .putBoolean(KEY_PENDING_UPLOAD, true)
                .remove(KEY_LAST_ERROR)
                .apply()
            Endpoint(url, pubKey, auth, generation, distributor)
        }

    fun endpoint(): Endpoint? = synchronized(lock) {
        val url = prefs.getString(KEY_EP_URL, null) ?: return null
        val pub = prefs.getString(KEY_EP_PUB, null) ?: return null
        val auth = prefs.getString(KEY_EP_AUTH, null) ?: return null
        Endpoint(url, pub, auth, prefs.getInt(KEY_GENERATION, 0), prefs.getString(KEY_EP_DIST, null))
    }

    fun clearEndpoint() = synchronized(lock) {
        prefs.edit()
            .remove(KEY_EP_URL).remove(KEY_EP_PUB).remove(KEY_EP_AUTH).remove(KEY_EP_DIST)
            .putBoolean(KEY_PENDING_UPLOAD, false)
            .apply()
    }

    val generation: Int get() = prefs.getInt(KEY_GENERATION, 0)

    var inboxCursor: String?
        get() = prefs.getString("inbox_cursor_v1", null)
        set(value) { prefs.edit().putString("inbox_cursor_v1", value).commit() }

    /** Moves the generation counter up to at least [minimum] (never down). */
    fun raiseGeneration(minimum: Int) = synchronized(lock) {
        if (prefs.getInt(KEY_GENERATION, 0) < minimum) {
            prefs.edit().putInt(KEY_GENERATION, minimum).apply()
        }
    }

    var pendingUpload: Boolean
        get() = prefs.getBoolean(KEY_PENDING_UPLOAD, false)
        set(value) = prefs.edit().putBoolean(KEY_PENDING_UPLOAD, value).apply()

    fun markUploaded(nowMs: Long) = synchronized(lock) {
        prefs.edit().putBoolean(KEY_PENDING_UPLOAD, false).putLong(KEY_LAST_UPLOAD, nowMs).remove(KEY_LAST_ERROR).apply()
    }

    val lastUploadMs: Long get() = prefs.getLong(KEY_LAST_UPLOAD, 0L)

    // ---- counters / health -------------------------------------------------

    fun recordPush(nowMs: Long) = synchronized(lock) {
        prefs.edit()
            .putLong(KEY_LAST_PUSH, nowMs)
            .putInt(KEY_PUSH_COUNT, prefs.getInt(KEY_PUSH_COUNT, 0) + 1)
            .putBoolean(KEY_TEMP_UNAVAILABLE, false)
            .apply()
    }

    val lastPushMs: Long get() = prefs.getLong(KEY_LAST_PUSH, 0L)
    val pushCount: Int get() = prefs.getInt(KEY_PUSH_COUNT, 0)

    var tempUnavailable: Boolean
        get() = prefs.getBoolean(KEY_TEMP_UNAVAILABLE, false)
        set(value) = prefs.edit().putBoolean(KEY_TEMP_UNAVAILABLE, value).apply()

    var lastError: String?
        get() = prefs.getString(KEY_LAST_ERROR, null)
        set(value) {
            val e = prefs.edit()
            if (value == null) e.remove(KEY_LAST_ERROR) else e.putString(KEY_LAST_ERROR, value)
            e.apply()
        }

    // ---- switches ----------------------------------------------------------

    var enabled: Boolean
        get() = prefs.getBoolean(KEY_ENABLED, true)
        set(value) = prefs.edit().putBoolean(KEY_ENABLED, value).apply()

    var disabledCategories: Set<String>
        get() = prefs.getStringSet(KEY_DISABLED, emptySet())?.toSet() ?: emptySet()
        set(value) = prefs.edit().putStringSet(KEY_DISABLED, value.toSet()).apply()

    // ---- ack queue ---------------------------------------------------------

    fun queueAck(id: String) = synchronized(lock) {
        val list = ackQueueLocked()
        if (!list.contains(id)) list.add(id)
        while (list.size > 200) list.removeAt(0)
        prefs.edit().putString(KEY_ACKS, JSONArray(list).toString()).apply()
    }

    fun ackQueue(): List<String> = synchronized(lock) { ackQueueLocked() }

    fun removeAcks(ids: Collection<String>) = synchronized(lock) {
        val list = ackQueueLocked()
        list.removeAll(ids.toSet())
        prefs.edit().putString(KEY_ACKS, JSONArray(list).toString()).apply()
    }

    private fun ackQueueLocked(): MutableList<String> {
        val raw = prefs.getString(KEY_ACKS, null) ?: return mutableListOf()
        return try {
            val arr = JSONArray(raw)
            MutableList(arr.length()) { arr.optString(it) }.filter { it.isNotEmpty() }.toMutableList()
        } catch (_: Exception) {
            mutableListOf()
        }
    }

    fun clearRegistrationState() = synchronized(lock) {
        prefs.edit()
            .remove("inbox_cursor_v1").remove(KEY_DEDUP).remove(KEY_ACKS)
            .remove(KEY_EP_URL).remove(KEY_EP_PUB).remove(KEY_EP_AUTH).remove(KEY_EP_DIST)
            .putBoolean(KEY_PENDING_UPLOAD, false)
            .apply()
    }

    companion object {
        private const val FILE = "conduit_push_state"
        private const val KEY_DEDUP = "dedup_v1"
        private const val KEY_EP_URL = "endpoint_url"
        private const val KEY_EP_PUB = "endpoint_pub"
        private const val KEY_EP_AUTH = "endpoint_auth"
        private const val KEY_EP_DIST = "endpoint_distributor"
        private const val KEY_GENERATION = "endpoint_generation"
        private const val KEY_PENDING_UPLOAD = "pending_upload"
        private const val KEY_LAST_UPLOAD = "last_upload_ms"
        private const val KEY_LAST_PUSH = "last_push_ms"
        private const val KEY_PUSH_COUNT = "push_count"
        private const val KEY_TEMP_UNAVAILABLE = "temp_unavailable"
        private const val KEY_LAST_ERROR = "last_error"
        private const val KEY_ENABLED = "enabled"
        private const val KEY_DISABLED = "disabled_categories"
        private const val KEY_ACKS = "ack_queue"

        private val lock = Any()

        @Volatile private var instance: PushStore? = null

        fun get(context: Context): PushStore =
            instance ?: synchronized(lock) {
                instance ?: PushStore(
                    context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE),
                ).also { instance = it }
            }
    }
}
