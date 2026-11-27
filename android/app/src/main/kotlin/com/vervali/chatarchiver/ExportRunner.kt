package com.vervali.chatarchiver

import android.accessibilityservice.AccessibilityService
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import java.util.UUID

/** Who a share that arrives right now belongs to. */
data class ShareAttribution(val runId: String, val groupId: String, val groupName: String, val trigger: String)

/**
 * Drives WhatsApp's own UI, one group at a time, as an explicit step machine on the main Looper.
 * Progress is driven by accessibility events (debounced) plus a poll every [POLL_MS].
 * Each step looks at a fresh [Screen] snapshot, acts only if its target is visible, then advances.
 * Every step has a timeout that maps to a contract error code.
 */
class ExportRunner(private val service: AccessibilityService) {

    enum class Step(val timeoutMs: Long, val errorOnTimeout: String) {
        LAUNCH(10_000, ErrorCode.TIMEOUT),
        TO_CHATS_LIST(10_000, ErrorCode.UNEXPECTED_SCREEN),
        OPEN_SEARCH(8_000, ErrorCode.SEARCH_NOT_FOUND),
        TYPE_QUERY(8_000, ErrorCode.SEARCH_NOT_FOUND),
        PICK_RESULT(12_000, ErrorCode.GROUP_NOT_FOUND),
        VERIFY_CHAT(8_000, ErrorCode.UNEXPECTED_SCREEN),
        OPEN_OVERFLOW(8_000, ErrorCode.MENU_NOT_FOUND),
        TAP_MORE(8_000, ErrorCode.MENU_NOT_FOUND),
        TAP_EXPORT(8_000, ErrorCode.EXPORT_NOT_FOUND),
        TAP_WITHOUT_MEDIA(8_000, ErrorCode.EXPORT_NOT_FOUND),
        FIND_SHARE_TARGET(15_000, ErrorCode.SHARE_TARGET_NOT_FOUND), // includes WhatsApp preparing the export
        WAIT_RECEIPT(20_000, ErrorCode.SHARE_NOT_RECEIVED),
        RETURN(8_000, ErrorCode.TIMEOUT), // cleanup only; timing out here never fails the group
    }

    data class StartResult(val started: Boolean, val reason: String? = null)

    private class Run(
        val runId: String,
        val trigger: String,
        val groups: List<GroupConfig>,
        val startedAt: Long,
    ) {
        var index = 0
        val results = ArrayList<GroupResult>()
        var cancelRequested = false

        lateinit var step: Step
        var stepStartedAt = 0L
        var cooldownUntil = 0L

        // per-step scratch state
        var launched = false
        var relaunches = 0
        var backPresses = 0
        var nextSetAt = 0L
        var stableKey: String? = null
        var stableSince = 0L
        var scrolls = 0
        var lastScrollAt = 0L
        var receivedJobId: String? = null
        var groupFinished = false

        val group: GroupConfig get() = groups[index]
    }

    private val handler = Handler(Looper.getMainLooper())
    private var run: Run? = null
    private var screenLock: PowerManager.WakeLock? = null
    private var waPackage: String? = null
    private var eventTickQueued = false

    /** Set while the runner is waiting for WhatsApp's share to reach ShareReceiverActivity. */
    @Volatile var awaitingShare: ShareAttribution? = null
        private set

    val isRunning: Boolean get() = run != null

    private val pollRunnable = object : Runnable {
        override fun run() {
            if (this@ExportRunner.run == null) return
            tick()
            if (this@ExportRunner.run != null) handler.postDelayed(this, POLL_MS)
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Public API (main thread)
    // ---------------------------------------------------------------------------------------------

    fun resolveWhatsAppPackage(): String? {
        val pm = service.packageManager
        return WhatsAppSelectors.PACKAGES.firstOrNull { pm.getLaunchIntentForPackage(it) != null }
    }

    fun start(trigger: String, groups: List<GroupConfig>): StartResult {
        if (run != null) return StartResult(false, "already_running")
        if (groups.isEmpty()) return StartResult(false, "no_groups")
        val pkg = resolveWhatsAppPackage() ?: return StartResult(false, "whatsapp_not_installed")
        waPackage = pkg
        val r = Run(UUID.randomUUID().toString(), trigger, groups, System.currentTimeMillis())
        run = r
        log(r, "run started trigger=$trigger groups=${groups.map { it.name }} wa=$pkg")
        AutomationEvents.runStarted(r.runId, trigger, groups.map { it.id })
        keepScreenOn(true)
        beginGroup(r)
        handler.removeCallbacks(pollRunnable)
        handler.postDelayed(pollRunnable, POLL_MS)
        return StartResult(true)
    }

    fun cancel() {
        val r = run ?: return
        log(r, "cancel requested")
        r.cancelRequested = true
        handler.post { tick() }
    }

    fun onAccessibilityEvent() {
        if (run == null || eventTickQueued) return
        eventTickQueued = true
        handler.postDelayed({
            eventTickQueued = false
            tick()
        }, EVENT_DEBOUNCE_MS)
    }

    /** Called by ShareReceiverActivity (any thread) after it stored the file. */
    fun notifyShareReceived(jobId: String, attribution: ShareAttribution?) {
        handler.post {
            val r = run ?: return@post
            if (attribution != null && attribution.runId == r.runId) {
                log(r, "share received job=$jobId")
                r.receivedJobId = jobId
                handler.post { tick() }
            }
        }
    }

    /** Called when the service goes away: abort quietly so no run is left dangling. */
    fun shutdown() {
        handler.removeCallbacksAndMessages(null)
        val r = run
        if (r != null) {
            abort(r, ErrorCode.CANCELLED, goHome = false)
        }
        awaitingShare = null
        keepScreenOn(false)
    }

    // ---------------------------------------------------------------------------------------------
    // Step machine
    // ---------------------------------------------------------------------------------------------

    private fun beginGroup(r: Run) {
        if (r.index >= r.groups.size) {
            finishRun(r, goHome = true)
            return
        }
        val g = r.group
        log(r, "group started: '${g.name}'")
        AutomationEvents.groupStarted(r.runId, g.id)
        r.launched = false
        r.relaunches = 0
        r.receivedJobId = null
        r.groupFinished = false
        awaitingShare = null
        enterStep(r, Step.LAUNCH)
    }

    private fun enterStep(r: Run, step: Step, cooldownMs: Long = 0) {
        r.step = step
        r.stepStartedAt = SystemClock.uptimeMillis()
        r.cooldownUntil = if (cooldownMs > 0) r.stepStartedAt + cooldownMs else 0L
        r.backPresses = 0
        r.stableKey = null
        r.nextSetAt = 0L
        r.scrolls = 0
        r.lastScrollAt = 0L
        log(r, "-> step ${step.name}")
        onAccessibilityEvent()
    }

    private fun tick() {
        val r = run ?: return
        try {
            tickInner(r)
        } catch (e: Exception) {
            Log.e(TAG, "tick failed in step ${r.step}", e)
            if (run === r && !r.groupFinished) failGroup(r, ErrorCode.UNEXPECTED_SCREEN)
        }
    }

    private fun tickInner(r: Run) {
        if (r.cancelRequested) {
            abort(r, ErrorCode.CANCELLED, goHome = true)
            return
        }
        if (isLocked()) {
            abort(r, ErrorCode.SCREEN_LOCKED, goHome = false)
            return
        }
        val now = SystemClock.uptimeMillis()
        if (now - r.stepStartedAt > r.step.timeoutMs) {
            if (r.step == Step.RETURN) {
                log(r, "cleanup timed out; moving on")
                afterGroup(r)
            } else {
                failGroup(r, r.step.errorOnTimeout)
            }
            return
        }
        if (now < r.cooldownUntil) return

        val screen = ScreenReader.capture(service)
        val wa = screen.inPackages(WhatsAppSelectors.PACKAGES)
        val g = r.group

        when (r.step) {
            Step.LAUNCH -> {
                val waActive = screen.windows.any { it.pkg in WhatsAppSelectors.PACKAGES && it.active }
                if (waActive) {
                    enterStep(r, Step.TO_CHATS_LIST)
                } else if (!r.launched) {
                    r.launched = true
                    if (!launchWhatsApp(r)) failGroup(r, ErrorCode.WHATSAPP_NOT_INSTALLED)
                    else r.cooldownUntil = now + 1000
                }
            }

            Step.TO_CHATS_LIST -> {
                if (wa.isEmpty()) {
                    // Maybe BACK left WhatsApp; bring it back (at most twice).
                    if (r.backPresses > 0 && r.relaunches < 2) {
                        r.relaunches++
                        log(r, "WhatsApp left the foreground while going back; relaunching")
                        r.launched = false
                        enterStep(r, Step.LAUNCH)
                    }
                    return
                }
                if (ScreenState.isChatsList(wa)) {
                    enterStep(r, Step.OPEN_SEARCH)
                } else if (now - r.stepStartedAt < SETTLE_MS) {
                    // let a splash/loading screen finish before pressing BACK
                } else if (r.backPresses < MAX_BACK) {
                    r.backPresses++
                    log(r, "BACK ${r.backPresses}/$MAX_BACK to reach Chats list")
                    service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)
                    r.cooldownUntil = now + 800
                } else {
                    failGroup(r, ErrorCode.UNEXPECTED_SCREEN)
                }
            }

            Step.OPEN_SEARCH -> {
                if (wa.isEmpty()) return
                if (ScreenState.searchField(wa) != null) {
                    enterStep(r, Step.TYPE_QUERY)
                    return
                }
                val h = wa.maxOfOrNull { it.bounds.bottom } ?: 0
                // Prefer a node we can actually tap (self, ancestor, or clickable child). Top 40%
                // covers taller Meta AI search bars on some devices.
                val entry = Finders.find(wa, WhatsAppSelectors.SEARCH_ENTRY) {
                    !it.editable &&
                        (h == 0 || it.bounds.top <= h * 0.40) &&
                        Finders.clickableTarget(it).clickable
                }.minByOrNull { it.bounds.top }
                if (entry != null && ScreenReader.click(entry, "open search")) {
                    enterStep(r, Step.TYPE_QUERY, cooldownMs = 900)
                }
            }

            Step.TYPE_QUERY -> {
                val field = ScreenState.searchField(wa) ?: return
                if (ChatNames.matches(field.text, g.name)) {
                    enterStep(r, Step.PICK_RESULT)
                } else if (now >= r.nextSetAt) {
                    ScreenReader.setText(field, g.name)
                    r.nextSetAt = now + 800
                    r.cooldownUntil = now + 500
                }
            }

            Step.PICK_RESULT -> {
                val rows = ScreenState.exactResultRows(wa, g.name)
                if (rows.isEmpty()) {
                    r.stableKey = null
                    return
                }
                // Prefer the topmost Chats-section hit. Meta AI search often also lists the same
                // title under Messages; VERIFY_CHAT still confirms the opened conversation title.
                val pick = rows.minByOrNull { it.bounds.top }!!
                val key = "${pick.id}${pick.bounds}|n=${rows.size}"
                if (key != r.stableKey) {
                    r.stableKey = key
                    r.stableSince = now
                    return
                }
                if (now - r.stableSince < STABLE_MS) return
                if (rows.size > 1) {
                    log(
                        r,
                        "multiple exact titles for '${g.name}' (${rows.size}); opening topmost at y=${pick.bounds.top}",
                    )
                }
                if (ScreenReader.click(pick, "open chat '${g.name}'")) {
                    enterStep(r, Step.VERIFY_CHAT, cooldownMs = 800)
                } else {
                    r.stableKey = null
                }
            }

            Step.VERIFY_CHAT -> {
                when (val t = ScreenState.conversationTitle(wa, g.name)) {
                    is ScreenState.Title.Found ->
                        if (ChatNames.matches(t.text, g.name)) {
                            log(r, "safety gate passed: title='${t.text}'")
                            enterStep(r, Step.OPEN_OVERFLOW)
                        } else {
                            log(r, "SAFETY GATE FAILED: title='${t.text}' expected='${g.name}'")
                            failGroup(r, ErrorCode.WRONG_CHAT)
                        }
                    ScreenState.Title.NotInChat -> Unit // keep waiting for the conversation to open
                }
            }

            Step.OPEN_OVERFLOW -> {
                // Safety gate is re-checked immediately before the first menu tap.
                when (val t = ScreenState.conversationTitle(wa, g.name)) {
                    is ScreenState.Title.Found -> if (!ChatNames.matches(t.text, g.name)) {
                        log(r, "SAFETY GATE FAILED before menu: title='${t.text}'")
                        failGroup(r, ErrorCode.WRONG_CHAT)
                        return
                    }
                    ScreenState.Title.NotInChat -> return
                }
                val btn = Finders.find(wa, WhatsAppSelectors.OVERFLOW).minByOrNull { it.bounds.top } ?: return
                if (ScreenReader.click(btn, "overflow")) enterStep(r, Step.TAP_MORE, cooldownMs = 700)
            }

            Step.TAP_MORE -> {
                if (menuMatch(wa, WhatsAppSelectors.EXPORT_CHAT) != null) {
                    enterStep(r, Step.TAP_EXPORT) // "Export chat" already visible, no need for "More"
                    return
                }
                val more = menuMatch(wa, WhatsAppSelectors.MORE) ?: return
                if (ScreenReader.click(more, "More")) enterStep(r, Step.TAP_EXPORT, cooldownMs = 700)
            }

            Step.TAP_EXPORT -> {
                val export = menuMatch(wa, WhatsAppSelectors.EXPORT_CHAT) ?: return
                if (ScreenReader.click(export, "Export chat")) enterStep(r, Step.TAP_WITHOUT_MEDIA, cooldownMs = 700)
            }

            Step.TAP_WITHOUT_MEDIA -> {
                val btn = menuMatch(wa, WhatsAppSelectors.WITHOUT_MEDIA)
                if (btn == null) {
                    // A chat without any media may skip the "Include media?" question and go straight to the share
                    // sheet: continue there instead of failing with export_not_found.
                    if (shareTarget(screen) != null) {
                        log(r, "no media dialog; share sheet already open")
                        enterStep(r, Step.FIND_SHARE_TARGET)
                    }
                    return
                }
                if (ScreenReader.click(btn, "Without media")) enterStep(r, Step.FIND_SHARE_TARGET, cooldownMs = 1000)
            }

            Step.FIND_SHARE_TARGET -> findShareTarget(r, screen, g, now)

            Step.WAIT_RECEIPT -> {
                val job = r.receivedJobId
                if (job != null) succeedGroup(r, job)
            }

            Step.RETURN -> {
                if (wa.isEmpty() || ScreenState.isChatsList(wa)) {
                    afterGroup(r)
                } else if (r.backPresses < MAX_BACK) {
                    r.backPresses++
                    log(r, "cleanup BACK ${r.backPresses}/$MAX_BACK")
                    service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)
                    r.cooldownUntil = now + 800
                } else {
                    afterGroup(r)
                }
            }
        }
    }

    /** Topmost menu / dialog entry; never anything inside the conversation's own window (see [ScreenState.menuItems]). */
    private fun menuMatch(wa: List<UiNode>, sels: List<Sel>): UiNode? =
        ScreenState.menuItems(wa, sels).minByOrNull { it.windowIndex }

    /** Our share target ("Save to Chat Archiver...") in any non-WhatsApp window, or null. */
    private fun shareTarget(screen: Screen): UiNode? {
        val label = service.getString(R.string.share_label)
        val candidates = screen.nodes.filter { it.pkg !in WhatsAppSelectors.PACKAGES }
        return Finders.find(candidates, listOf(Sel.Text(label))).firstOrNull()
    }

    private fun findShareTarget(r: Run, screen: Screen, g: GroupConfig, now: Long) {
        val label = service.getString(R.string.share_label)
        val candidates = screen.nodes.filter { it.pkg !in WhatsAppSelectors.PACKAGES }
        val hit = shareTarget(screen)
        if (hit != null) {
            // Attribute the incoming share BEFORE tapping so a fast receiver cannot race us.
            awaitingShare = ShareAttribution(r.runId, g.id, g.name, r.trigger)
            if (ScreenReader.click(hit, "share target '$label'")) {
                enterStep(r, Step.WAIT_RECEIPT)
            } else {
                awaitingShare = null
            }
            return
        }
        // Not visible: scroll the chooser forward (up to MAX_SCROLLS times).
        val sheetScrollables = candidates.filter {
            it.scrollable && it.pkg !in WhatsAppSelectors.NOT_SHARE_SHEET_PACKAGES
        }
        if (sheetScrollables.isEmpty()) return // chooser not on screen yet
        if (r.scrolls >= MAX_SCROLLS) {
            if (now - r.lastScrollAt > 1500) {
                log(r, "share target '$label' not found after $MAX_SCROLLS scrolls")
                failGroup(r, ErrorCode.SHARE_TARGET_NOT_FOUND)
            }
            return
        }
        if (now - r.lastScrollAt < 800) return
        r.scrolls++
        r.lastScrollAt = now
        log(r, "share target not visible, scroll ${r.scrolls}/$MAX_SCROLLS")
        sheetScrollables.forEach { ScreenReader.scrollForward(it) }
        r.cooldownUntil = now + 600
    }

    // ---------------------------------------------------------------------------------------------
    // Group / run outcomes
    // ---------------------------------------------------------------------------------------------

    private fun succeedGroup(r: Run, jobId: String) {
        val g = r.group
        awaitingShare = null
        r.groupFinished = true
        r.results.add(GroupResult(g.id, g.name, GroupResult.EXPORTED, null, Step.WAIT_RECEIPT.name.lowercase()))
        Stores.config(service).markExported(g.id, RunPolicy.todayString(System.currentTimeMillis()))
        log(r, "group exported: '${g.name}' job=$jobId")
        AutomationEvents.groupExported(r.runId, g.id, jobId)
        enterStep(r, Step.RETURN)
    }

    private fun failGroup(r: Run, error: String) {
        val g = r.group
        awaitingShare = null
        r.groupFinished = true
        val stepName = r.step.name.lowercase()
        r.results.add(GroupResult(g.id, g.name, GroupResult.FAILED, error, stepName))
        Log.w(TAG, "group FAILED: '${g.name}' error=$error step=$stepName")
        AutomationEvents.groupFailed(r.runId, g.id, error, stepName)
        enterStep(r, Step.RETURN) // best-effort: back out of dialogs / sheets / the chat
    }

    private fun afterGroup(r: Run) {
        r.index++
        beginGroup(r)
    }

    /** Stop the run now: current group failed with [code], the rest skipped with the same code. */
    private fun abort(r: Run, code: String, goHome: Boolean) {
        val g = r.groups.getOrNull(r.index)
        val startIdx = if (g != null && !r.groupFinished) {
            val stepName = r.step.name.lowercase()
            r.results.add(GroupResult(g.id, g.name, GroupResult.FAILED, code, stepName))
            AutomationEvents.groupFailed(r.runId, g.id, code, stepName)
            r.index + 1
        } else {
            r.index + 1
        }
        for (i in startIdx until r.groups.size) {
            val s = r.groups[i]
            r.results.add(GroupResult(s.id, s.name, GroupResult.SKIPPED, code, null))
        }
        log(r, "run aborted: $code")
        finishRun(r, goHome = goHome, launchApp = code != ErrorCode.SCREEN_LOCKED)
    }

    private fun finishRun(r: Run, goHome: Boolean, launchApp: Boolean = true) {
        awaitingShare = null
        handler.removeCallbacks(pollRunnable)
        keepScreenOn(false)
        val report = RunReport(r.runId, r.trigger, r.startedAt, System.currentTimeMillis(), r.results.toList())
        try {
            Stores.report(service).save(report)
        } catch (e: Exception) {
            Log.e(TAG, "saving run report failed", e)
        }
        run = null
        log(r, "run finished: ${report.results.map { "${it.groupName}=${it.status}/${it.error}" }}")
        AutomationEvents.runFinished(r.runId, report)
        if (goHome) service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME)
        if (launchApp) handler.postDelayed({ launchMainActivity() }, 700)
    }

    private fun launchMainActivity() {
        try {
            val i = Intent(service, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                putExtra(MainActivity.EXTRA_PROCESS_PENDING, true)
            }
            service.startActivity(i)
        } catch (e: Exception) {
            Log.w(TAG, "could not launch MainActivity", e)
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------

    private fun launchWhatsApp(r: Run): Boolean {
        val pkg = waPackage ?: resolveWhatsAppPackage() ?: return false
        val intent = service.packageManager.getLaunchIntentForPackage(pkg) ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            service.startActivity(intent)
            log(r, "launched $pkg")
            true
        } catch (e: Exception) {
            Log.e(TAG, "launching WhatsApp failed", e)
            false
        }
    }

    /**
     * Keeps the screen on while a run is in progress. Accessibility clicks are not user activity, so with a
     * 30-second screen timeout the phone would otherwise lock in the middle of a run (`screen_locked`).
     * The lock never turns the screen on and is released at the end of the run (or after [MAX_RUN_SCREEN_ON_MS]).
     */
    @Suppress("DEPRECATION") // SCREEN_BRIGHT_WAKE_LOCK: the only way for a service without a window.
    private fun keepScreenOn(on: Boolean) {
        try {
            if (on) {
                if (screenLock?.isHeld == true) return
                val pm = service.getSystemService(Context.POWER_SERVICE) as PowerManager
                screenLock = pm.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ON_AFTER_RELEASE,
                    "ChatArchiver:run",
                ).apply {
                    setReferenceCounted(false)
                    acquire(MAX_RUN_SCREEN_ON_MS)
                }
            } else {
                screenLock?.let { if (it.isHeld) it.release() }
                screenLock = null
            }
        } catch (e: Exception) {
            Log.w(TAG, "screen wake lock failed", e)
        }
    }

    private fun isLocked(): Boolean {
        val pm = service.getSystemService(Context.POWER_SERVICE) as PowerManager
        val km = service.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        return !pm.isInteractive || km.isKeyguardLocked
    }

    private fun log(r: Run, msg: String) {
        val grp = r.groups.getOrNull(r.index)?.name
        Log.d(TAG, "[${r.runId.take(8)}${if (grp != null) " '$grp'" else ""}] $msg")
    }

    companion object {
        private const val TAG = "ChatArchiver"
        const val POLL_MS = 400L
        const val EVENT_DEBOUNCE_MS = 150L
        private const val SETTLE_MS = 1500L
        private const val STABLE_MS = 900L
        private const val MAX_BACK = 5
        private const val MAX_SCROLLS = 6
        private const val MAX_RUN_SCREEN_ON_MS = 10L * 60L * 1000L
    }
}
