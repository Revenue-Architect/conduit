package app.cogwheel.conduit.push

import android.app.Activity
import android.app.Application
import android.os.Bundle
import android.os.Handler
import android.os.Looper

/**
 * Process-wide push runtime state: whether an activity is on screen and, when
 * the Flutter engine is attached, the channel to Dart. The receiver consults
 * this to decide between a Dart in-app banner and a system notification.
 */
internal object PushRuntime {
    @Volatile var flutterApi: ConduitPushFlutterApi? = null
    @Volatile private var started = 0
    private val main = Handler(Looper.getMainLooper())

    val isForeground: Boolean get() = started > 0

    fun install(application: Application) {
        application.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            override fun onActivityStarted(activity: Activity) { started++ }
            override fun onActivityStopped(activity: Activity) { if (started > 0) started-- }
            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
            override fun onActivityResumed(activity: Activity) {}
            override fun onActivityPaused(activity: Activity) {}
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
            override fun onActivityDestroyed(activity: Activity) {}
        })
    }

    /** Runs [block] on the main thread against the attached Dart API, if any. */
    fun withFlutter(block: (ConduitPushFlutterApi) -> Unit): Boolean {
        val api = flutterApi ?: return false
        main.post {
            try {
                block(api)
            } catch (_: Exception) {
                // The engine may have detached between the check and the post.
            }
        }
        return true
    }

    fun statusChanged() {
        withFlutter { it.onStatusChanged {} }
    }
}
