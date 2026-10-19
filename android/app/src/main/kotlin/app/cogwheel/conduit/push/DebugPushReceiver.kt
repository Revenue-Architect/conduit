package app.cogwheel.conduit.push

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Debug and profile builds only (declared in their manifests, never in main or
 * release). Feeds a plaintext envelope to the same intake path so rendering,
 * channels and shade actions can be exercised over adb without ntfy:
 *
 *   adb shell am broadcast -n app.cogwheel.conduit.debug/app.cogwheel.conduit.push.DebugPushReceiver \
 *       --es envelope '{"v":1,...}'
 *
 * The manifest requires android.permission.DUMP, which only the shell (adb)
 * holds, so no other app can use this to forge a notification. Even then, a
 * decide action re-reads the request from the gateway, so a forged envelope
 * cannot approve anything that is not genuinely pending.
 */
class DebugPushReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val raw = intent.getStringExtra("envelope") ?: return
        val envelope = PushEnvelope.parse(raw.toByteArray(Charsets.UTF_8))
        if (envelope == null) {
            Log.w(TAG, "debug envelope rejected")
            return
        }
        PushStore.get(context).recordPush(System.currentTimeMillis())
        PushIntake.handle(context, envelope, raw)
        PushRuntime.statusChanged()
    }

    private companion object {
        const val TAG = "DebugPushReceiver"
    }
}
