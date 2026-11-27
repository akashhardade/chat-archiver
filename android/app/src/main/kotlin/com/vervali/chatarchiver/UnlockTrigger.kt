package com.vervali.chatarchiver

import android.os.Handler
import android.os.Looper
import android.util.Log

/** Native-only unlock trigger. Works with the Flutter UI closed; policy lives in [RunPolicy]. */
object UnlockTrigger {
    private const val TAG = "ChatArchiver"
    const val START_DELAY_MS = 1500L
    private val main = Handler(Looper.getMainLooper())

    fun onUserPresent(service: ExportAccessibilityService) {
        val cfgStore = Stores.config(service)
        val now = System.currentTimeMillis()
        val today = RunPolicy.todayString(now)
        val decision = RunPolicy.decideOnUnlock(
            config = cfgStore.getConfig(),
            lastExportDates = cfgStore.lastExportDates(),
            lastAutoAttemptAt = cfgStore.lastAutoAttemptAt(),
            nowMs = now,
            autoAttemptsToday = cfgStore.autoAttemptsOn(today),
        )
        Log.d(TAG, "unlock: decision=${decision.reason} groups=${decision.groups.map { it.name }}")
        if (!decision.shouldRun) return
        val runner = service.runner
        if (runner.isRunning) return
        if (runner.resolveWhatsAppPackage() == null) {
            Log.d(TAG, "unlock: WhatsApp not installed, skipping")
            return
        }
        // Throttle and daily cap count from the attempt (also if it then fails).
        cfgStore.recordAutoAttempt(today, now)
        main.postDelayed({
            if (ExportAccessibilityService.instance !== service || runner.isRunning) return@postDelayed
            // Re-evaluate the due groups at start time (state may have changed during the delay).
            val due = RunPolicy.decideOnUnlock(
                config = cfgStore.getConfig(),
                lastExportDates = cfgStore.lastExportDates(),
                lastAutoAttemptAt = 0L, // throttle already accounted for
                nowMs = System.currentTimeMillis(),
            )
            if (due.shouldRun) {
                val res = runner.start(Trigger.UNLOCK, due.groups)
                Log.d(TAG, "unlock: start -> $res")
            }
        }, START_DELAY_MS)
    }
}
