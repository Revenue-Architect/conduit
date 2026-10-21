package app.cogwheel.conduit.push

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.engine.FlutterEngine
import org.unifiedpush.android.connector.UnifiedPush

/**
 * Pigeon host side of the push bridge. All real work is in the native classes
 * next to it; this only adapts them to Dart and gathers local status.
 */
internal class PushHostApiImpl(
    private val context: Context,
    private val activity: () -> Activity?,
) : ConduitPushHostApi {

    private val store get() = PushStore.get(context)
    private val vault get() = PushVault.get(context)

    override fun status(): PushNativeStatus {
        val distributors = externalDistributors()
        val saved = savedDistributor()
        val credentials = vault.load()
        val endpoint = store.endpoint()
        return PushNativeStatus(
            notificationsAllowed = NotificationManagerCompat.from(context).areNotificationsEnabled(),
            distributors = distributors,
            distributor = saved,
            distributorSelected = saved != null,
            registered = endpoint != null,
            paired = credentials != null,
            endpointGeneration = store.generation.toLong().takeIf { it > 0 },
            lastPushAtMs = store.lastPushMs.takeIf { it > 0 },
            lastUploadAtMs = store.lastUploadMs.takeIf { it > 0 },
            appBatteryUnrestricted = isUnrestricted(context.packageName) == true,
            distributorBatteryUnrestricted = saved?.let { isUnrestricted(it) },
            pendingUpload = store.pendingUpload,
            pushCount = store.pushCount.toLong(),
            tempUnavailable = store.tempUnavailable,
            gatewayUrl = credentials?.gatewayUrl,
            deviceId = credentials?.deviceId,
            lastError = store.lastError,
        )
    }

    override fun listDistributors(): List<String> = externalDistributors()

    override fun currentDistributor(): String? = savedDistributor()

    override fun saveDistributor(packageName: String) {
        UnifiedPush.saveDistributor(context, packageName)
        PushRuntime.statusChanged()
    }

    override fun pickDistributor(callback: (Result<Boolean>) -> Unit) {
        val available = externalDistributors()
        when {
            available.isEmpty() -> callback(Result.success(false))
            savedDistributor() != null -> callback(Result.success(true))
            available.size == 1 -> {
                UnifiedPush.saveDistributor(context, available.first())
                callback(Result.success(true))
            }
            else -> {
                val host = activity()
                if (host == null) {
                    callback(Result.success(false))
                } else {
                    UnifiedPush.tryUseCurrentOrDefaultDistributor(host) { ok -> callback(Result.success(ok)) }
                }
            }
        }
    }

    override fun register(): Boolean {
        if (savedDistributor() == null) return false
        UnifiedPush.register(context, INSTANCE, "Hermez")
        return true
    }

    override fun unregister() {
        UnifiedPush.unregister(context, INSTANCE)
        store.clearRegistrationState()
        PushWork.enqueueDelete(context)
        PushRuntime.statusChanged()
    }

    override fun storeVault(token: String, gatewayUrl: String, deviceId: String, expiresAtMs: Long) {
        vault.store(PushCredentials(token, gatewayUrl.trimEnd('/'), deviceId, expiresAtMs))
        // A new pairing means the server has no endpoint for this device yet.
        if (store.endpoint() != null) {
            store.pendingUpload = true
            PushWork.enqueueUpload(context)
        }
        PushRuntime.statusChanged()
    }

    override fun clearVault() {
        vault.clear()
        PushRuntime.statusChanged()
    }

    override fun getPrefs(): PushNativePrefs =
        PushNativePrefs(enabled = store.enabled, disabledCategories = store.disabledCategories.toList())

    override fun setPrefs(prefs: PushNativePrefs) {
        store.enabled = prefs.enabled
        store.disabledCategories = prefs.disabledCategories.toSet()
    }

    override fun syncEndpoint() {
        if (store.endpoint() != null && vault.isPaired) {
            store.pendingUpload = true
            PushWork.enqueueUpload(context)
        }
        if (vault.isPaired) PushWork.enqueueInbox(context)
    }

    override fun batteryUnrestricted(packageName: String): Boolean? = isUnrestricted(packageName)

    override fun openBatterySettings(packageName: String) {
        launch(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")),
            fallback = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
        )
    }

    override fun openApp(packageName: String): Boolean {
        val intent = context.packageManager.getLaunchIntentForPackage(packageName) ?: return false
        return launch(intent, fallback = null)
    }

    override fun openChannelSettings(category: String) {
        val channel = PushCategory.fromWire(category)?.channelId ?: return
        PushChannels.ensure(context)
        launch(
            Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                .putExtra(Settings.EXTRA_CHANNEL_ID, channel),
            fallback = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName),
        )
    }

    override fun cancelByTag(tag: String) {
        PushRenderer(context).cancel(tag)
    }

    // ---- helpers -----------------------------------------------------------

    private fun externalDistributors(): List<String> =
        UnifiedPush.getDistributors(context).filter { it != context.packageName }

    private fun savedDistributor(): String? =
        try {
            UnifiedPush.getSavedDistributor(context)
        } catch (e: Exception) {
            Log.w(TAG, "saved distributor unavailable: ${e.javaClass.simpleName}")
            null
        }

    private fun isUnrestricted(packageName: String): Boolean? =
        try {
            (context.getSystemService(Context.POWER_SERVICE) as PowerManager)
                .isIgnoringBatteryOptimizations(packageName)
        } catch (_: Exception) {
            null
        }

    private fun launch(intent: Intent, fallback: Intent?): Boolean {
        val host = activity()
        fun start(i: Intent): Boolean = try {
            if (host != null) host.startActivity(i) else context.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (_: Exception) {
            false
        }
        return start(intent) || (fallback != null && start(fallback))
    }

    companion object {
        const val INSTANCE = "default"
        private const val TAG = "PushHostApi"
    }
}

/** Wires the push bridge to a Flutter engine / activity pair. */
internal object PushBridge {
    fun attach(engine: FlutterEngine, activity: Activity) {
        val messenger = engine.dartExecutor.binaryMessenger
        ConduitPushHostApi.setUp(messenger, PushHostApiImpl(activity.applicationContext) { activity })
        PushRuntime.flutterApi = ConduitPushFlutterApi(messenger)
        PushChannels.ensure(activity.applicationContext)
    }

    fun detach(engine: FlutterEngine) {
        ConduitPushHostApi.setUp(engine.dartExecutor.binaryMessenger, null)
        PushRuntime.flutterApi = null
    }
}
