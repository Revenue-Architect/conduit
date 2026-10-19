package app.cogwheel.conduit.push

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** What pairing gave the phone. */
internal data class PushCredentials(
    val token: String,
    val gatewayUrl: String,
    val deviceId: String,
    val expiresAtMs: Long,
)

/**
 * The device token and gateway origin, encrypted with an Android Keystore
 * AES-GCM key (non-exportable) and stored in private SharedPreferences. Dart
 * writes it once after pairing through Pigeon; workers read it while the app
 * is dead. The plaintext never leaves this class except to the gateway client.
 */
internal class PushVault private constructor(private val prefs: SharedPreferences) {

    fun store(credentials: PushCredentials) {
        val json = JSONObject()
            .put("token", credentials.token)
            .put("gateway", credentials.gatewayUrl)
            .put("device", credentials.deviceId)
            .put("exp", credentials.expiresAtMs)
            .toString()
        val sealed = seal(json.toByteArray(Charsets.UTF_8))
        prefs.edit().putString(KEY_BLOB, Base64.encodeToString(sealed, Base64.NO_WRAP)).apply()
    }

    fun load(): PushCredentials? {
        val blob = prefs.getString(KEY_BLOB, null) ?: return null
        return try {
            val plain = open(Base64.decode(blob, Base64.NO_WRAP))
            val obj = JSONObject(String(plain, Charsets.UTF_8))
            PushCredentials(
                token = obj.getString("token"),
                gatewayUrl = obj.getString("gateway"),
                deviceId = obj.getString("device"),
                expiresAtMs = obj.optLong("exp", 0L),
            )
        } catch (e: Exception) {
            // Never log the blob. A corrupt vault reads as "not paired".
            Log.w(TAG, "vault unreadable: ${e.javaClass.simpleName}")
            null
        }
    }

    fun clear() {
        prefs.edit().remove(KEY_BLOB).apply()
    }

    val isPaired: Boolean get() = prefs.contains(KEY_BLOB)

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (ks.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        gen.init(
            KeyGenParameterSpec.Builder(
                ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return gen.generateKey()
    }

    private fun seal(plain: ByteArray): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORM)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val iv = cipher.iv
        return iv + cipher.doFinal(plain)
    }

    private fun open(sealed: ByteArray): ByteArray {
        val iv = sealed.copyOfRange(0, IV_BYTES)
        val cipher = Cipher.getInstance(TRANSFORM)
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, iv))
        return cipher.doFinal(sealed, IV_BYTES, sealed.size - IV_BYTES)
    }

    companion object {
        private const val TAG = "PushVault"
        private const val FILE = "conduit_push_vault"
        private const val KEY_BLOB = "blob_v1"
        private const val ALIAS = "conduit_push_vault_v1"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val TRANSFORM = "AES/GCM/NoPadding"
        private const val IV_BYTES = 12

        @Volatile private var instance: PushVault? = null

        fun get(context: Context): PushVault =
            instance ?: synchronized(this) {
                instance ?: PushVault(
                    context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE),
                ).also { instance = it }
            }
    }
}
