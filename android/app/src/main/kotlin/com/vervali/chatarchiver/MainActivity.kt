package com.vervali.chatarchiver

import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null

    /** True once Dart made its first call to us (its handler is then registered). */
    private var dartReady = false
    private var processPendingQueued = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val handler = AutomationChannel(this)
        val ch = MethodChannel(messenger, AutomationChannel.CHANNEL)
        ch.setMethodCallHandler { call, result ->
            handler.onMethodCall(call, result)
            onDartCall()
        }
        channel = ch
        EventChannel(messenger, AutomationEvents.CHANNEL).setStreamHandler(AutomationEvents)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel?.setMethodCallHandler(null)
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null || !intent.getBooleanExtra(EXTRA_PROCESS_PENDING, false)) return
        intent.removeExtra(EXTRA_PROCESS_PENDING) // do not re-deliver on recreation
        Log.d(TAG, "process_pending received (dartReady=$dartReady)")
        if (dartReady) callProcessPending(0) else processPendingQueued = true
    }

    /** Called after every Dart->native call; the first one flushes a queued process_pending. */
    private fun onDartCall() {
        if (dartReady) return
        dartReady = true
        if (processPendingQueued) {
            processPendingQueued = false
            // Small delay so Dart finishes wiring its handler after its first call.
            main.postDelayed({ callProcessPending(0) }, 300)
        }
    }

    private fun callProcessPending(attempt: Int) {
        val ch = channel ?: return
        ch.invokeMethod("onProcessPending", null, object : MethodChannel.Result {
            override fun success(result: Any?) {}
            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                Log.w(TAG, "onProcessPending error: $errorCode $errorMessage")
            }

            override fun notImplemented() {
                // Dart handler not registered yet: retry a few times.
                if (attempt < 5) main.postDelayed({ callProcessPending(attempt + 1) }, 500)
                else Log.w(TAG, "onProcessPending not handled by Dart")
            }
        })
    }

    companion object {
        const val EXTRA_PROCESS_PENDING = "process_pending"
        private const val TAG = "ChatArchiver"
    }
}
