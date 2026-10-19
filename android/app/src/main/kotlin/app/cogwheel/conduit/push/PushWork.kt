package app.cogwheel.conduit.push

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/** Queues the network work behind pushes. Everything here is best-effort and idempotent. */
internal object PushWork {
    private val online = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()

    fun enqueueInbox(context: Context) {
        val request = OneTimeWorkRequestBuilder<PushSyncWorker>()
            .setInputData(Data.Builder().putString(PushSyncWorker.KEY_KIND, PushSyncWorker.KIND_INBOX).build())
            .setConstraints(online)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork("push-inbox", ExistingWorkPolicy.KEEP, request)
    }

    fun enqueueAck(context: Context) {
        val request = OneTimeWorkRequestBuilder<PushSyncWorker>()
            .setInputData(Data.Builder().putString(PushSyncWorker.KEY_KIND, PushSyncWorker.KIND_ACK).build())
            .setConstraints(online)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork("push-ack", ExistingWorkPolicy.APPEND_OR_REPLACE, request)
    }

    fun enqueueVerify(context: Context, nonce: String) {
        val request = OneTimeWorkRequestBuilder<PushSyncWorker>()
            .setInputData(
                Data.Builder()
                    .putString(PushSyncWorker.KEY_KIND, PushSyncWorker.KIND_VERIFY)
                    .putString(PushSyncWorker.KEY_NONCE, nonce)
                    .build(),
            )
            .setConstraints(online)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            .build()
        WorkManager.getInstance(context)
            .enqueueUniqueWork("push-verify-$nonce", ExistingWorkPolicy.KEEP, request)
    }

    fun enqueueUpload(context: Context) {
        val request = OneTimeWorkRequestBuilder<PushSyncWorker>()
            .setInputData(Data.Builder().putString(PushSyncWorker.KEY_KIND, PushSyncWorker.KIND_UPLOAD).build())
            .setConstraints(online)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            .build()
        // The newest endpoint always wins, so a queued older upload is replaced.
        WorkManager.getInstance(context).enqueueUniqueWork("push-endpoint", ExistingWorkPolicy.REPLACE, request)
    }

    fun enqueueDelete(context: Context) {
        val request = OneTimeWorkRequestBuilder<PushSyncWorker>()
            .setInputData(Data.Builder().putString(PushSyncWorker.KEY_KIND, PushSyncWorker.KIND_DELETE).build())
            .setConstraints(online)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork("push-endpoint-delete", ExistingWorkPolicy.KEEP, request)
    }

    fun enqueueAction(context: Context, action: RetryAction) {
        val data = Data.Builder()
        val unique: String
        when (action) {
            is RetryAction.Decide -> {
                data.putString(ActionWorker.KEY_KIND, ActionWorker.KIND_DECIDE)
                    .putString(ActionWorker.KEY_APPROVAL, action.approvalId)
                    .putString(ActionWorker.KEY_DECISION, action.decision)
                    .putString(ActionWorker.KEY_DIGEST, action.digest)
                    .putString(ActionWorker.KEY_TAG, action.tag)
                    .putString(ActionWorker.KEY_ENVELOPE, action.envelopeId)
                unique = "push-decide-${action.approvalId}-${action.decision}"
            }
            is RetryAction.Relay -> {
                data.putString(ActionWorker.KEY_KIND, ActionWorker.KIND_RELAY)
                    .putString(ActionWorker.KEY_URL, action.url)
                    .putString(ActionWorker.KEY_TAG, action.tag)
                    .putString(ActionWorker.KEY_CATEGORY, action.category)
                    .putString(ActionWorker.KEY_LABEL, action.label)
                unique = "push-relay-${action.url.hashCode()}"
            }
        }
        val request = OneTimeWorkRequestBuilder<ActionWorker>()
            .setInputData(data.build())
            .setConstraints(online)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            .build()
        // REPLACE so an explicit Retry tap starts a fresh attempt count.
        WorkManager.getInstance(context).enqueueUniqueWork(unique, ExistingWorkPolicy.REPLACE, request)
    }
}
