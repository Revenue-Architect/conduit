package app.cogwheel.conduit.push

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Receives Approve / Deny / relay taps from the notification shade. It does no
 * network work itself: it shows "Approving..." immediately (which also removes
 * the buttons, so a double tap cannot send twice) and hands off to WorkManager.
 *
 * Not exported; the PendingIntents are immutable and explicit.
 */
class ApprovalActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_RUN) return
        val action = RetryAction.read(intent) ?: return
        val renderer = PushRenderer(context)
        when (action) {
            is RetryAction.Decide -> {
                renderer.showActionState(
                    tag = action.tag,
                    category = PushCategory.APPROVALS,
                    title = "Approval",
                    text = PushShadeText.sending(action.decision),
                    approvalId = action.approvalId,
                )
            }
            is RetryAction.Relay -> {
                renderer.showActionState(
                    tag = action.tag,
                    category = PushCategory.fromWire(action.category) ?: PushCategory.STATUS,
                    title = action.label,
                    text = "Sending…",
                    approvalId = null,
                )
            }
        }
        PushWork.enqueueAction(context.applicationContext, action)
    }

    companion object {
        const val ACTION_RUN = "app.cogwheel.conduit.push.ACTION_RUN"
    }
}
