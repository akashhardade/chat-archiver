package com.vervali.chatarchiver

import android.accessibilityservice.AccessibilityService
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.provider.Settings
import android.text.TextUtils
import android.util.Log
import android.view.accessibility.AccessibilityEvent

class ExportAccessibilityService : AccessibilityService() {

    val runner: ExportRunner by lazy { ExportRunner(this) }

    private var userPresentReceiver: BroadcastReceiver? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        connected = true
        Log.d(TAG, "accessibility service connected")
        registerUserPresent()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        runner.onAccessibilityEvent()
    }

    override fun onInterrupt() {
        Log.d(TAG, "accessibility service interrupted")
    }

    override fun onUnbind(intent: Intent?): Boolean {
        teardown()
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        teardown()
        super.onDestroy()
    }

    private fun teardown() {
        connected = false
        if (instance === this) instance = null
        unregisterUserPresent()
        runner.shutdown()
    }

    private fun registerUserPresent() {
        if (userPresentReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == Intent.ACTION_USER_PRESENT) {
                    UnlockTrigger.onUserPresent(this@ExportAccessibilityService)
                }
            }
        }
        val filter = IntentFilter(Intent.ACTION_USER_PRESENT)
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }
        userPresentReceiver = receiver
    }

    private fun unregisterUserPresent() {
        val r = userPresentReceiver ?: return
        userPresentReceiver = null
        try {
            unregisterReceiver(r)
        } catch (_: IllegalArgumentException) {
        }
    }

    companion object {
        private const val TAG = "ChatArchiver"

        @Volatile var instance: ExportAccessibilityService? = null
            private set

        @Volatile var connected: Boolean = false
            private set

        /** Connected instance, or the OS setting as a fallback (e.g. process just restarted). */
        fun isEnabled(context: Context): Boolean =
            (instance != null && connected) || isEnabledInSettings(context)

        fun isEnabledInSettings(context: Context): Boolean {
            val me = ComponentName(context, ExportAccessibilityService::class.java)
            val enabled = try {
                Settings.Secure.getInt(context.contentResolver, Settings.Secure.ACCESSIBILITY_ENABLED, 0) == 1
            } catch (_: Exception) {
                false
            }
            if (!enabled) return false
            val setting = try {
                Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
            } catch (_: Exception) {
                null
            } ?: return false
            val splitter = TextUtils.SimpleStringSplitter(':')
            splitter.setString(setting)
            while (splitter.hasNext()) {
                val c = ComponentName.unflattenFromString(splitter.next()) ?: continue
                if (c == me) return true
            }
            return false
        }
    }
}
