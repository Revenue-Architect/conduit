package app.cogwheel.conduit.push

import android.net.Uri
import org.json.JSONObject

/**
 * Pure decisions behind the native push path. No Android classes, so every
 * branch is covered by plain JUnit tests.
 */
internal object PushPolicy {
    const val DEDUP_CAPACITY = 500
    const val DECISION_MAX_ATTEMPTS = 6
    const val ACK_MAX_ATTEMPTS = 3
    const val UPLOAD_MAX_ATTEMPTS = 8

    /** True when the envelope's `ts + ttl` is in the past (with clock skew allowance). */
    fun isExpired(envelope: PushEnvelope, nowSeconds: Long): Boolean =
        nowSeconds > envelope.timestamp + envelope.ttl + PushLimits.CLOCK_SKEW_SECONDS

    /**
     * Whether this envelope may be shown, given the user's local switches.
     * Approvals and critical honor only the master switch.
     */
    fun isCategoryAllowed(
        category: PushCategory,
        masterEnabled: Boolean,
        disabledCategories: Set<String>,
    ): Boolean {
        if (!masterEnabled) return false
        if (category.alwaysOn) return true
        return category.wire !in disabledCategories
    }

    /** Backoff before attempt number [attempt] (1-based): 30 s doubling, capped at 30 min. */
    fun backoffSeconds(attempt: Int): Long {
        val shift = (attempt - 1).coerceIn(0, 6)
        return (30L shl shift).coerceAtMost(1800L)
    }

    /** What the decision worker should do with one gateway response. */
    fun classifyDecisionResponse(httpCode: Int): DecisionOutcome = when (httpCode) {
        200, 201, 202, 204 -> DecisionOutcome.DONE
        404, 410 -> DecisionOutcome.GONE
        409 -> DecisionOutcome.CONFLICT
        401, 403 -> DecisionOutcome.UNAUTHORIZED
        408, 425, 429 -> DecisionOutcome.RETRY
        in 500..599 -> DecisionOutcome.RETRY
        else -> DecisionOutcome.REJECTED
    }

    /** Maps the V2 approval status string to the shade wording. */
    fun statusWord(status: String?): StatusWord = when (status?.lowercase()) {
        "approved" -> StatusWord.APPROVED
        "denied", "rejected" -> StatusWord.DENIED
        "expired" -> StatusWord.EXPIRED
        "cancelled", "canceled" -> StatusWord.CANCELLED
        "pending" -> StatusWord.PENDING
        else -> StatusWord.UNKNOWN
    }
}

internal enum class DecisionOutcome { DONE, GONE, CONFLICT, UNAUTHORIZED, RETRY, REJECTED }

internal enum class StatusWord { APPROVED, DENIED, EXPIRED, CANCELLED, PENDING, UNKNOWN }

/**
 * Bounded set of recently handled envelope ids, persisted as one string so a
 * process death between two deliveries still dedups.
 */
internal class DedupSet private constructor(private val ids: ArrayDeque<String>, private val capacity: Int) {
    /** Returns true when [id] had not been seen (and records it). */
    fun markFresh(id: String): Boolean {
        if (ids.contains(id)) return false
        ids.addLast(id)
        while (ids.size > capacity) ids.removeFirst()
        return true
    }

    fun contains(id: String): Boolean = ids.contains(id)

    fun serialize(): String = ids.joinToString("\n")

    val size: Int get() = ids.size

    companion object {
        fun parse(raw: String?, capacity: Int = PushPolicy.DEDUP_CAPACITY): DedupSet {
            val list = ArrayDeque<String>()
            raw?.split('\n')?.filter { it.isNotEmpty() }?.takeLast(capacity)?.forEach { list.addLast(it) }
            return DedupSet(list, capacity)
        }
    }
}

/** Builds the `hermez://` deep link a notification tap should open. */
internal object PushDeepLinks {
    private const val BASE = "hermez://hermes/profile/hermes"

    fun forOpen(open: PushOpen?): String? = when (open?.kind) {
        OpenKind.APPROVAL -> "$BASE/approvals/${open?.id}"
        OpenKind.SESSION -> session(open?.id)
        OpenKind.THREAD -> "$BASE/conversations?thread=${open?.id}"
        OpenKind.BRIEF -> "$BASE/home?brief=${open?.id}"
        OpenKind.URL, OpenKind.NONE, null -> null
    }

    private val PROFILE = Regex("^[a-z0-9][a-z0-9_-]{0,63}$")

    /** A session push opens that chat directly. The id may be "<profile>:<session>". */
    fun session(id: String?): String? {
        if (id.isNullOrBlank()) return null
        val cut = id.indexOf(':')
        val profile = if (cut > 0) id.substring(0, cut) else null
        val sid = if (cut > 0) id.substring(cut + 1) else id
        if (sid.isBlank()) return null
        val query = if (profile != null && PROFILE.matches(profile)) "?open=chat&profile=$profile" else "?open=chat"
        return "$BASE/live/${Uri.encode(sid)}$query"
    }

    fun approvals(): String = "$BASE/approvals"

    fun approval(id: String, openChat: Boolean = false): String =
        "$BASE/approvals/$id" + if (openChat) "?open=chat" else ""
}

/** What the shade shows for each stage of a decision made from a notification. */
internal object PushShadeText {
    fun sending(decision: String) = if (decision == "approve") "Approving…" else "Denying…"

    fun decided(word: StatusWord, description: String?): String {
        val tail = description?.takeIf { it.isNotBlank() }?.let { ": $it" } ?: ""
        return when (word) {
            StatusWord.APPROVED -> "Approved$tail"
            StatusWord.DENIED -> "Denied$tail"
            StatusWord.EXPIRED -> "Expired$tail"
            StatusWord.CANCELLED -> "Cancelled$tail"
            else -> "Already decided$tail"
        }
    }

    const val UNREACHABLE = "Could not reach Hermes - tap to retry"
    const val PAIRING_LOST = "Hermez is not paired - open the app"
    const val CHANGED = "This request changed - open it to review"
}

internal object PushJson {
    /** Safe string field read for gateway JSON that may be absent or null. */
    fun str(obj: JSONObject?, key: String): String? =
        if (obj == null || obj.isNull(key)) null else obj.optString(key).takeIf { it.isNotEmpty() }
}
