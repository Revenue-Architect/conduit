package app.cogwheel.conduit.push

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import app.cogwheel.conduit.MainActivity
import app.cogwheel.conduit.R

/**
 * Builds and posts Hermez push notifications (spec sections 4.6, 8). Only
 * called for envelopes that passed authentication, TTL, dedup and the user's
 * switches. Every approval action re-reads the request from the gateway in
 * [ApprovalDecisionWorker]; nothing in a notification is authority by itself.
 */
internal class PushRenderer(private val context: Context) {

    private val manager: NotificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    fun show(envelope: PushEnvelope, nowSeconds: Long) {
        PushChannels.ensure(context)
        val channelId = PushChannels.channelIdFor(envelope.category, envelope.shadow)
        val title = if (envelope.shadow) "[shadow] ${envelope.title}" else envelope.title
        val id = notificationId(envelope.effectiveTag)
        val groupKey = "hermez.group.${envelope.group ?: envelope.category.wire}"

        val builder = baseBuilder(channelId, title.ifEmpty { "Hermes" }, envelope.body)
            .setContentIntent(contentIntent(id, PushDeepLinks.forOpen(envelope.open), envelope.open))
            .setGroup(groupKey)
            .setWhen(envelope.timestamp * 1000L)
            .setShowWhen(true)
            .setCategory(androidCategory(envelope.category))
            .setPriority(compatPriority(envelope))
            .setOnlyAlertOnce(envelope.type == PushType.UPDATE)

        // A request that has expired must not keep live Approve/Deny buttons.
        val remaining = envelope.timestamp + envelope.ttl - nowSeconds
        if (remaining in 1..MAX_TIMEOUT_SECONDS) builder.setTimeoutAfter(remaining * 1000L)

        if (envelope.category.alwaysOn || envelope.category == PushCategory.ALERTS) {
            // Lock screen shows the title only; the body appears once unlocked.
            builder.setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            builder.setPublicVersion(
                baseBuilder(channelId, title.ifEmpty { "Hermes" }, "Unlock to see details").build(),
            )
        }

        if (envelope.type != PushType.UPDATE) {
            envelope.actions.forEachIndexed { index, action -> addAction(builder, envelope, id, index, action) }
        }

        manager.notify(id, builder.build())
        updateGroupSummary(groupKey, channelId, envelope.category)
    }

    /** Replaces a posted notification (same tag) with plain text and no actions. */
    fun showUpdate(envelope: PushEnvelope, existingTitle: String? = null) {
        PushChannels.ensure(context)
        val channelId = PushChannels.channelIdFor(envelope.category, envelope.shadow)
        val id = notificationId(envelope.effectiveTag)
        // An update only replaces a notification that is still showing. If the
        // request was already handled (decided in the app, swiped away), a
        // late "Approved" would just be stale clutter.
        val showing = try {
            manager.activeNotifications.any { it.id == id }
        } catch (_: Exception) {
            true
        }
        if (!showing) return
        val title = envelope.title.ifEmpty { existingTitle ?: "Hermes" }
        val groupKey = "hermez.group.${envelope.group ?: envelope.category.wire}"
        val builder = baseBuilder(channelId, title, envelope.body)
            .setContentIntent(contentIntent(id, PushDeepLinks.forOpen(envelope.open), envelope.open))
            .setGroup(groupKey)
            .setOnlyAlertOnce(true)
            .setTimeoutAfter(RESULT_TIMEOUT_MS)
            .setPriority(NotificationCompat.PRIORITY_LOW)
        manager.notify(id, builder.build())
    }

    /**
     * Unauthenticated or undecryptable content: never show its text and never
     * attach actions (spec section 7.4).
     */
    fun showGeneric() {
        PushChannels.ensure(context)
        val builder = baseBuilder(PushCategory.STATUS.channelId, "Hermes has an update", "Tap to open Hermez")
            .setContentIntent(contentIntent(GENERIC_ID, PushDeepLinks.approvals(), null))
            .setPriority(NotificationCompat.PRIORITY_LOW)
        manager.notify(GENERIC_ID, builder.build())
    }

    fun cancel(tag: String) {
        manager.cancel(notificationId(tag))
    }

    /**
     * Shows the progress/result of an action taken from the shade. Same id as
     * the original notification so it replaces the buttons.
     */
    fun showActionState(
        tag: String,
        category: PushCategory,
        title: String,
        text: String,
        approvalId: String?,
        retry: RetryAction? = null,
        timeoutMs: Long = RESULT_TIMEOUT_MS,
        openChat: Boolean = false,
    ) {
        PushChannels.ensure(context)
        val id = notificationId(tag)
        val builder = baseBuilder(category.channelId, title, text)
            .setContentIntent(contentIntent(id, approvalId?.let { PushDeepLinks.approval(it, openChat) } ?: PushDeepLinks.approvals(), null))
            .setOnlyAlertOnce(true)
            // A failed action keeps its Retry button much longer than a result.
            .setTimeoutAfter(if (retry != null) FAILURE_TIMEOUT_MS else timeoutMs)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
        if (retry != null) {
            val needsUnlock = retry is RetryAction.Decide
            if (!needsUnlock || Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val action = NotificationCompat.Action.Builder(0, "Retry", decideIntent(id, 90, retry))
                // Retrying an Approve is still an approval: keep the unlock gate.
                if (needsUnlock) action.setAuthenticationRequired(true)
                builder.addAction(action.build())
            }
        }
        manager.notify(id, builder.build())
    }

    // ---- building blocks ---------------------------------------------------

    private fun baseBuilder(channelId: String, title: String, text: String): NotificationCompat.Builder {
        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_stat_hermez)
            .setContentTitle(title)
            .setContentText(text.lineSequence().firstOrNull() ?: "")
            .setAutoCancel(true)
        if (text.isNotEmpty()) builder.setStyle(NotificationCompat.BigTextStyle().bigText(text))
        return builder
    }

    private fun addAction(
        builder: NotificationCompat.Builder,
        envelope: PushEnvelope,
        notificationId: Int,
        index: Int,
        action: PushAction,
    ) {
        when (action.kind) {
            ActionKind.DECIDE -> {
                val decision = action.decision ?: return
                val approval = action.approval ?: return
                val digest = action.digest ?: return
                // Both decisions require the unlocked phone (Kamran's choice).
                val unlockRequired = true
                if (unlockRequired && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                    // No system unlock gate before Android 12: open the request
                    // instead of letting a locked phone approve it.
                    builder.addAction(
                        NotificationCompat.Action.Builder(
                            0,
                            "Review",
                            contentIntent(notificationId + index + 1, PushDeepLinks.approval(approval), null),
                        ).build(),
                    )
                    return
                }
                val pending = decideIntent(
                    notificationId,
                    index,
                    RetryAction.Decide(approval, decision, digest, envelope.effectiveTag, envelope.id),
                )
                val compat = NotificationCompat.Action.Builder(0, action.label, pending)
                    .setShowsUserInterface(false)
                    .setSemanticAction(
                        if (decision == "approve") NotificationCompat.Action.SEMANTIC_ACTION_NONE
                        else NotificationCompat.Action.SEMANTIC_ACTION_DELETE,
                    )
                if (unlockRequired) compat.setAuthenticationRequired(true)
                builder.addAction(compat.build())
            }
            ActionKind.RELAY -> {
                val url = action.url ?: return
                builder.addAction(
                    NotificationCompat.Action.Builder(
                        0,
                        action.label,
                        decideIntent(
                            notificationId,
                            index,
                            RetryAction.Relay(url, envelope.effectiveTag, envelope.category.wire, action.label),
                        ),
                    ).build(),
                )
            }
            ActionKind.VIEW -> {
                val url = action.url ?: return
                val view = Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                builder.addAction(
                    NotificationCompat.Action.Builder(
                        0,
                        action.label,
                        PendingIntent.getActivity(
                            context,
                            requestCode(notificationId, index),
                            view,
                            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                        ),
                    ).build(),
                )
            }
        }
    }

    private fun decideIntent(notificationId: Int, index: Int, action: RetryAction): PendingIntent {
        val intent = Intent(context, ApprovalActionReceiver::class.java).apply {
            this.action = ApprovalActionReceiver.ACTION_RUN
            action.writeTo(this)
        }
        return PendingIntent.getBroadcast(
            context,
            requestCode(notificationId, index),
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    private fun contentIntent(id: Int, link: String?, open: PushOpen?): PendingIntent {
        val intent = when {
            link != null -> Intent(Intent.ACTION_VIEW, Uri.parse(link)).setClass(context, MainActivity::class.java)
            open?.kind == OpenKind.URL && open.url != null -> Intent(Intent.ACTION_VIEW, Uri.parse(open.url))
            else -> Intent(context, MainActivity::class.java).setAction(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_LAUNCHER)
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(
            context,
            id,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    private fun updateGroupSummary(groupKey: String, channelId: String, category: PushCategory) {
        val active = try {
            manager.activeNotifications.filter { it.notification.group == groupKey && it.notification.flags and Notification.FLAG_GROUP_SUMMARY == 0 }
        } catch (_: Exception) {
            return
        }
        val summaryId = notificationId(groupKey)
        if (active.size <= SUMMARY_THRESHOLD) {
            if (manager.activeNotifications.any { it.id == summaryId }) manager.cancel(summaryId)
            return
        }
        val summary = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_stat_hermez)
            .setContentTitle("${active.size} ${category.wire} notifications")
            .setGroup(groupKey)
            .setGroupSummary(true)
            .setOnlyAlertOnce(true)
            .setAutoCancel(true)
            .setContentIntent(contentIntent(summaryId, PushDeepLinks.approvals().takeIf { category == PushCategory.APPROVALS }, null))
            .build()
        manager.notify(summaryId, summary)
    }

    private fun androidCategory(category: PushCategory): String = when (category) {
        PushCategory.APPROVALS -> NotificationCompat.CATEGORY_REMINDER
        PushCategory.CRITICAL, PushCategory.ALERTS -> NotificationCompat.CATEGORY_ERROR
        PushCategory.STATUS -> NotificationCompat.CATEGORY_STATUS
        else -> NotificationCompat.CATEGORY_MESSAGE
    }

    private fun compatPriority(envelope: PushEnvelope): Int = when {
        envelope.priority >= 4 -> NotificationCompat.PRIORITY_HIGH
        envelope.priority == 3 -> NotificationCompat.PRIORITY_DEFAULT
        else -> NotificationCompat.PRIORITY_LOW
    }

    companion object {
        private const val GENERIC_ID = 0x5A5A0001
        private const val SUMMARY_THRESHOLD = 3
        private const val MAX_TIMEOUT_SECONDS = 7L * 86_400L
        /** A finished decision is a receipt, not a to-do: it clears itself. */
        private const val RESULT_TIMEOUT_MS = 10L * 60L * 1000L
        private const val FAILURE_TIMEOUT_MS = 6L * 60L * 60L * 1000L

        /** Stable id in a high range so it never collides with the Dart plugin's counter. */
        fun notificationId(tag: String): Int = (tag.hashCode() and 0x3FFFFFFF) or 0x40000000

        private fun requestCode(notificationId: Int, index: Int): Int = notificationId * 7 + index
    }
}

/** A shade action that the receiver turns into background work. */
internal sealed class RetryAction {
    abstract fun writeTo(intent: Intent)

    data class Decide(
        val approvalId: String,
        val decision: String,
        val digest: String,
        val tag: String,
        val envelopeId: String,
    ) : RetryAction() {
        override fun writeTo(intent: Intent) {
            intent.putExtra(RetryAction.KIND, "decide").putExtra("approval", approvalId).putExtra("decision", decision)
                .putExtra("digest", digest).putExtra("tag", tag).putExtra("envelope", envelopeId)
        }
    }

    data class Relay(val url: String, val tag: String, val category: String, val label: String) : RetryAction() {
        override fun writeTo(intent: Intent) {
            intent.putExtra(RetryAction.KIND, "relay").putExtra("url", url).putExtra("tag", tag)
                .putExtra("category", category).putExtra("label", label)
        }
    }

    companion object {
        const val KIND = "kind"

        fun read(intent: Intent): RetryAction? = when (intent.getStringExtra(KIND)) {
            "decide" -> Decide(
                approvalId = intent.getStringExtra("approval") ?: return null,
                decision = intent.getStringExtra("decision") ?: return null,
                digest = intent.getStringExtra("digest") ?: return null,
                tag = intent.getStringExtra("tag") ?: return null,
                envelopeId = intent.getStringExtra("envelope") ?: "",
            )
            "relay" -> Relay(
                url = intent.getStringExtra("url") ?: return null,
                tag = intent.getStringExtra("tag") ?: return null,
                category = intent.getStringExtra("category") ?: "status",
                label = intent.getStringExtra("label") ?: "Done",
            )
            else -> null
        }
    }
}
