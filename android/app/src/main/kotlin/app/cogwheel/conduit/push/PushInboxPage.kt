package app.cogwheel.conduit.push

import org.json.JSONObject

/** Validate the entire page before handling it or advancing its durable cursor. */
internal data class PushInboxPage(
    val envelopes: List<Pair<PushEnvelope, String>>,
    val next: String?,
    val more: Boolean,
) {
    companion object {
        fun parse(raw: String): PushInboxPage? = try {
            val body = JSONObject(raw)
            val items = body.getJSONArray("items")
            require(items.length() <= 100)
            val next = body.optString("next").takeIf { it.isNotEmpty() && it != "null" }
            require(next == null || Regex("[0-9A-HJKMNP-TV-Z]{26}").matches(next))
            val more = body.getBoolean("more")
            require(!more || (next != null && items.length() > 0))
            val envelopes = (0 until items.length()).map { index ->
                val json = items.getJSONObject(index).toString()
                val envelope = requireNotNull(PushEnvelope.parse(json.toByteArray(Charsets.UTF_8)))
                require(!envelope.shadow && envelope.type != PushType.PROBE && envelope.type != PushType.VERIFY)
                envelope to json
            }
            PushInboxPage(envelopes, next, more)
        } catch (_: Exception) { null }
    }
}
