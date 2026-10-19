package app.cogwheel.conduit.push

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

/**
 * The push envelope (spec section 5.1): cleartext JSON inside the encrypted
 * UnifiedPush message. This file is deliberately free of Android classes so it
 * can be unit tested on the JVM.
 *
 * Parsing is defensive: anything malformed yields `null` and is dropped. The
 * server truncates over-limit text; the app truncates again so a hostile or
 * buggy sender can never create an oversized notification.
 */
internal object PushLimits {
    const val MAX_ENVELOPE_BYTES = 4096
    const val MAX_TITLE = 120
    const val MAX_BODY = 600
    const val MAX_LABEL = 24
    const val MAX_ACTIONS = 3
    const val DEFAULT_TTL_SECONDS = 86_400L
    const val MAX_TTL_SECONDS = 7L * 86_400L

    /** The signed-link relay is the only web origin a push may point at. */
    const val RELAY_ORIGIN = "https://umbrel.tail4c9e01.ts.net:8447/"

    /** Tolerated clock skew between the Umbrel and the phone. */
    const val CLOCK_SKEW_SECONDS = 600L
}

internal enum class PushCategory(val wire: String, val channelId: String) {
    APPROVALS("approvals", "hermez_approvals_v1"),
    CRITICAL("critical", "hermez_critical_v1"),
    ALERTS("alerts", "hermez_alerts_v1"),
    PROACTIVE("proactive", "hermez_proactive_v1"),
    BRIEFS("briefs", "hermez_briefs_v1"),
    AGENT("agent", "hermez_agent_v1"),
    WATCH("watch", "hermez_watch_v1"),
    STATUS("status", "hermez_status_v1");

    /** Approvals and critical can only be silenced by the master switch. */
    val alwaysOn: Boolean get() = this == APPROVALS || this == CRITICAL

    companion object {
        const val SHADOW_CHANNEL_ID = "hermez_shadow_v1"
        fun fromWire(value: String?): PushCategory? = entries.firstOrNull { it.wire == value }
    }
}

internal enum class PushType(val wire: String) {
    NOTIFY("notify"),
    DISMISS("dismiss"),
    UPDATE("update"),
    PROBE("probe"),
    VERIFY("verify");

    companion object {
        fun fromWire(value: String?): PushType? = entries.firstOrNull { it.wire == value }
    }
}

internal enum class OpenKind(val wire: String) {
    APPROVAL("approval"),
    SESSION("session"),
    THREAD("thread"),
    BRIEF("brief"),
    URL("url"),
    NONE("none");

    companion object {
        fun fromWire(value: String?): OpenKind? = entries.firstOrNull { it.wire == value }
    }
}

internal data class PushOpen(val kind: OpenKind, val id: String?, val url: String?)

internal enum class ActionKind { DECIDE, RELAY, VIEW }

internal data class PushAction(
    val id: String,
    val label: String,
    val kind: ActionKind,
    /** Approval id for [ActionKind.DECIDE]. */
    val approval: String? = null,
    val digest: String? = null,
    /** True when the action must only run on an unlocked device. */
    val auth: Boolean = false,
    val url: String? = null,
    val method: String? = null,
) {
    /** `approve` / `deny` for decide actions, else null. */
    val decision: String? get() = if (kind == ActionKind.DECIDE && (id == "approve" || id == "deny")) id else null
}

internal data class PushEnvelope(
    val version: Int,
    val type: PushType,
    val id: String,
    val dedupe: String?,
    val tag: String?,
    val timestamp: Long,
    val ttl: Long,
    val category: PushCategory,
    val priority: Int,
    val title: String,
    val body: String,
    val open: PushOpen?,
    val actions: List<PushAction>,
    val group: String?,
    val ack: Boolean,
    val shadow: Boolean,
    val nonce: String?,
) {
    /** The tag that gives a notification its stable identity. */
    val effectiveTag: String get() = tag?.takeIf { it.isNotEmpty() } ?: id

    companion object {
        private val ID_PATTERN = Regex("^[A-Za-z0-9_.:@/-]{1,128}$")

        /** Wire ids are used in tags and deep links, so `..` is never allowed. */
        private fun validId(value: String): Boolean = ID_PATTERN.matches(value) && !value.contains("..")

        private val UUID_RE = Regex("^[0-9a-fA-F-]{8,64}$")
        private val DIGEST_RE = Regex("^[0-9a-fA-F]{64}$")

        /** Parses and validates; returns null for anything not acceptable. */
        fun parse(bytes: ByteArray): PushEnvelope? {
            if (bytes.isEmpty() || bytes.size > PushLimits.MAX_ENVELOPE_BYTES) return null
            return try {
                parse(JSONObject(String(bytes, Charsets.UTF_8)))
            } catch (_: JSONException) {
                null
            }
        }

        fun parse(json: JSONObject): PushEnvelope? {
            if (json.optInt("v", -1) != 1) return null
            val type = PushType.fromWire(json.optString("t", "")) ?: return null
            val id = json.optString("id", "")
            if (!validId(id)) return null
            val category = PushCategory.fromWire(json.optString("cat", ""))
                ?: if (type == PushType.PROBE || type == PushType.VERIFY) PushCategory.STATUS else return null
            val ts = json.optLong("ts", 0L)
            if (ts <= 0L) return null
            val ttl = json.optLong("ttl", PushLimits.DEFAULT_TTL_SECONDS)
                .coerceIn(1L, PushLimits.MAX_TTL_SECONDS)
            val tag = json.optString("tag", "").takeIf { it.isNotEmpty() }
            if (tag != null && !validId(tag)) return null
            if (type == PushType.DISMISS && tag == null) return null
            val nonce = json.optString("nonce", "").takeIf { it.isNotEmpty() }
            if (nonce != null && !validId(nonce)) return null
            if (type == PushType.VERIFY && nonce == null) return null
            val actions = parseActions(json.optJSONArray("actions"))
            return PushEnvelope(
                version = 1,
                type = type,
                id = id,
                dedupe = json.optString("dedupe", "").takeIf { it.isNotEmpty() && validId(it) },
                tag = tag,
                timestamp = ts,
                ttl = ttl,
                category = category,
                priority = json.optInt("pri", 3).coerceIn(1, 5),
                title = clip(json.optString("title", ""), PushLimits.MAX_TITLE),
                body = clip(json.optString("body", ""), PushLimits.MAX_BODY),
                open = parseOpen(json.optJSONObject("open")),
                actions = actions,
                group = json.optString("group", "").takeIf { it.isNotEmpty() },
                ack = json.optBoolean("ack", false),
                shadow = json.optBoolean("shadow", false),
                nonce = nonce,
            )
        }

        private fun clip(value: String, max: Int): String =
            if (value.length <= max) value else value.substring(0, max - 1) + "…"

        private fun parseOpen(obj: JSONObject?): PushOpen? {
            obj ?: return null
            val kind = OpenKind.fromWire(obj.optString("k", "")) ?: return null
            val id = obj.optString("id", "").takeIf { it.isNotEmpty() }
            val url = obj.optString("url", "").takeIf { it.isNotEmpty() }
            return when (kind) {
                OpenKind.NONE -> PushOpen(kind, null, null)
                OpenKind.URL ->
                    if (url != null && isRelayUrl(url)) PushOpen(kind, null, url) else null
                else ->
                    if (id != null && validId(id)) PushOpen(kind, id, null) else null
            }
        }

        private fun parseActions(array: JSONArray?): List<PushAction> {
            array ?: return emptyList()
            val out = ArrayList<PushAction>()
            for (i in 0 until minOf(array.length(), PushLimits.MAX_ACTIONS)) {
                val obj = array.optJSONObject(i) ?: continue
                val action = parseAction(obj) ?: continue
                out += action
            }
            return out
        }

        private fun parseAction(obj: JSONObject): PushAction? {
            val id = obj.optString("id", "")
            if (!validId(id)) return null
            val label = clip(obj.optString("label", ""), PushLimits.MAX_LABEL)
            if (label.isEmpty()) return null
            return when (obj.optString("kind", "")) {
                "decide" -> {
                    if (id != "approve" && id != "deny") return null
                    val approval = obj.optString("approval", "")
                    val digest = obj.optString("digest", "")
                    if (!UUID_RE.matches(approval) || !DIGEST_RE.matches(digest)) return null
                    PushAction(
                        id = id,
                        label = label,
                        kind = ActionKind.DECIDE,
                        approval = approval,
                        digest = digest.lowercase(),
                        auth = obj.optBoolean("auth", id == "approve"),
                    )
                }
                "relay" -> {
                    val url = obj.optString("url", "")
                    if (!isRelayUrl(url)) return null
                    val method = obj.optString("method", "POST").uppercase()
                    if (method != "POST") return null
                    PushAction(id = id, label = label, kind = ActionKind.RELAY, url = url, method = method)
                }
                "view" -> {
                    val url = obj.optString("url", "")
                    if (!isRelayUrl(url)) return null
                    PushAction(id = id, label = label, kind = ActionKind.VIEW, url = url)
                }
                else -> null
            }
        }

        /** Only the pinned relay origin may be called or opened from a push. */
        fun isRelayUrl(url: String): Boolean =
            url.startsWith(PushLimits.RELAY_ORIGIN) && url.length <= 600 && !url.contains(' ')
    }
}
