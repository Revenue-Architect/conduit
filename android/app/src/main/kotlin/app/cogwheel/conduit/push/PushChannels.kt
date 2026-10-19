package app.cogwheel.conduit.push

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.provider.Settings

/**
 * Notification channels for pushed categories (spec section 8.1). Ids carry a
 * `_v1` suffix: once a user changes a channel in Android settings the app can
 * no longer change its importance, so a different design means a new id.
 *
 * Deliberately NOT set anywhere here: [NotificationChannel.setBypassDnd]. The
 * critical category must not break through Do Not Disturb, and it also uses
 * the ordinary notification sound usage (not USAGE_ALARM, which DND treats as
 * an alarm and lets through by default).
 */
internal object PushChannels {

    private data class Spec(
        val category: PushCategory,
        val name: String,
        val description: String,
        val importance: Int,
        val sound: Boolean,
        val vibration: LongArray?,
        val privateLockScreen: Boolean,
    )

    private val STRONG_VIBRATION = longArrayOf(0, 400, 150, 400, 150, 600)
    private val DEFAULT_VIBRATION = longArrayOf(0, 250, 120, 250)

    private val specs = listOf(
        Spec(PushCategory.APPROVALS, "Approvals", "Requests that need your decision",
            NotificationManager.IMPORTANCE_HIGH, true, DEFAULT_VIBRATION, true),
        Spec(PushCategory.CRITICAL, "Critical alerts", "Backups failed, checks cannot run",
            NotificationManager.IMPORTANCE_HIGH, true, STRONG_VIBRATION, true),
        Spec(PushCategory.ALERTS, "Alerts", "New failures and outages on the Umbrel",
            NotificationManager.IMPORTANCE_HIGH, true, DEFAULT_VIBRATION, false),
        Spec(PushCategory.PROACTIVE, "Proactive", "Heads-ups and nudges from Hermes",
            NotificationManager.IMPORTANCE_DEFAULT, true, null, false),
        Spec(PushCategory.BRIEFS, "Briefs", "Morning brief, week prep and weekly review",
            NotificationManager.IMPORTANCE_DEFAULT, true, null, false),
        Spec(PushCategory.AGENT, "Agent messages", "Messages sent by Hermes agents",
            NotificationManager.IMPORTANCE_DEFAULT, true, null, false),
        Spec(PushCategory.WATCH, "Watches", "Site and price changes",
            NotificationManager.IMPORTANCE_DEFAULT, false, null, false),
        Spec(PushCategory.STATUS, "Status", "Recoveries, decisions and expiries",
            NotificationManager.IMPORTANCE_LOW, false, null, false),
    )

    fun ensure(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        for (spec in specs) {
            // Never touch an existing channel: the user may have customized it.
            if (manager.getNotificationChannel(spec.category.channelId) != null) continue
            val channel = NotificationChannel(spec.category.channelId, spec.name, spec.importance).apply {
                description = spec.description
                setShowBadge(spec.importance >= NotificationManager.IMPORTANCE_DEFAULT)
                enableLights(false)
                lockscreenVisibility =
                    if (spec.privateLockScreen) Notification.VISIBILITY_PRIVATE else Notification.VISIBILITY_PUBLIC
                if (spec.sound) {
                    setSound(
                        Settings.System.DEFAULT_NOTIFICATION_URI,
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build(),
                    )
                } else {
                    setSound(null, null)
                }
                if (spec.vibration != null) {
                    enableVibration(true)
                    vibrationPattern = spec.vibration
                } else {
                    enableVibration(false)
                }
                // Explicit: never ask the system to bypass Do Not Disturb.
                setBypassDnd(false)
            }
            manager.createNotificationChannel(channel)
        }
        if (manager.getNotificationChannel(PushCategory.SHADOW_CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(PushCategory.SHADOW_CHANNEL_ID, "Hermez shadow", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Delivery measurement copies during rollout"
                    setSound(null, null)
                    enableVibration(false)
                    setShowBadge(false)
                },
            )
        }
    }

    fun channelIdFor(category: PushCategory, shadow: Boolean): String =
        if (shadow) PushCategory.SHADOW_CHANNEL_ID else category.channelId
}
