package app.cogwheel.conduit.push

import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/** One gateway reply. [body] is the raw text (JSON for every documented route). */
internal data class GatewayResponse(val code: Int, val body: String) {
    fun json(): JSONObject? = try {
        JSONObject(body)
    } catch (_: Exception) {
        null
    }
}

/**
 * Minimal gateway client for the native workers (spec section 5.3). Only the
 * device token is ever sent; it is never logged. Network failures surface as
 * [IOException] so workers can retry; HTTP statuses are returned to the caller.
 */
internal class PushGatewayClient(private val credentials: PushCredentials) {

    private val base: String = credentials.gatewayUrl.trimEnd('/') + "/phone/v1"

    @Throws(IOException::class)
    fun get(path: String): GatewayResponse = request("GET", path, null, emptyMap())

    @Throws(IOException::class)
    fun post(path: String, body: JSONObject, headers: Map<String, String> = emptyMap()): GatewayResponse =
        request("POST", path, body, headers)

    @Throws(IOException::class)
    fun delete(path: String): GatewayResponse = request("DELETE", path, null, emptyMap())

    @Throws(IOException::class)
    fun put(path: String, body: JSONObject): GatewayResponse = request("PUT", path, body, emptyMap())

    @Throws(IOException::class)
    private fun request(
        method: String,
        path: String,
        body: JSONObject?,
        headers: Map<String, String>,
    ): GatewayResponse {
        val connection = URL(base + path).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = method
            connection.connectTimeout = CONNECT_TIMEOUT_MS
            connection.readTimeout = READ_TIMEOUT_MS
            connection.instanceFollowRedirects = false
            connection.setRequestProperty("Authorization", "Bearer ${credentials.token}")
            connection.setRequestProperty("Accept", "application/json")
            headers.forEach { (k, v) -> connection.setRequestProperty(k, v) }
            if (body != null) {
                val bytes = body.toString().toByteArray(Charsets.UTF_8)
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                connection.setFixedLengthStreamingMode(bytes.size)
                connection.outputStream.use { it.write(bytes) }
            }
            val code = connection.responseCode
            val stream = if (code >= 400) connection.errorStream else connection.inputStream
            val text = stream?.use { s -> s.readBytes().take(MAX_RESPONSE_BYTES).toByteArray().toString(Charsets.UTF_8) } ?: ""
            return GatewayResponse(code, text)
        } finally {
            connection.disconnect()
        }
    }

    private companion object {
        const val CONNECT_TIMEOUT_MS = 10_000
        const val READ_TIMEOUT_MS = 10_000
        const val MAX_RESPONSE_BYTES = 256 * 1024
    }
}
