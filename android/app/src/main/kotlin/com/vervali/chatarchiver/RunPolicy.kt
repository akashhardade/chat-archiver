package com.vervali.chatarchiver

import java.time.Instant
import java.time.ZoneId

/** Pure unlock-trigger policy from the contract. */
object RunPolicy {
    const val THROTTLE_MS = 20L * 60L * 1000L

    /**
     * Automatic (unlock) attempts per local day. Without a cap, a group that keeps failing (e.g. a wrong title or a
     * WhatsApp layout change) would take over the phone on every unlock, every 20 minutes, all day.
     */
    const val MAX_AUTO_ATTEMPTS_PER_DAY = 3

    enum class Reason {
        OK, DISABLED, NO_ENABLED_GROUPS, BEFORE_MORNING_HOUR, ALL_EXPORTED_TODAY, THROTTLED, DAILY_LIMIT,
    }

    data class Decision(val reason: Reason, val groups: List<GroupConfig>) {
        val shouldRun: Boolean get() = reason == Reason.OK
    }

    fun todayString(nowMs: Long, zone: ZoneId = ZoneId.systemDefault()): String =
        Instant.ofEpochMilli(nowMs).atZone(zone).toLocalDate().toString() // yyyy-MM-dd

    fun localHour(nowMs: Long, zone: ZoneId = ZoneId.systemDefault()): Int =
        Instant.ofEpochMilli(nowMs).atZone(zone).hour

    /**
     * Decide what an ACTION_USER_PRESENT should do.
     * Run when: config enabled, at least one enabled group, local hour >= morningHour, some enabled group has
     * not exported successfully today, the last automatic attempt was >= 20 minutes ago, and fewer than
     * [MAX_AUTO_ATTEMPTS_PER_DAY] automatic attempts were made today ([autoAttemptsToday]).
     * Only groups not yet exported today are returned.
     */
    fun decideOnUnlock(
        config: AutomationConfig?,
        lastExportDates: Map<String, String>,
        lastAutoAttemptAt: Long,
        nowMs: Long,
        zone: ZoneId = ZoneId.systemDefault(),
        autoAttemptsToday: Int = 0,
    ): Decision {
        if (config == null || !config.enabled) return Decision(Reason.DISABLED, emptyList())
        val enabled = config.groups.filter { it.enabled }
        if (enabled.isEmpty()) return Decision(Reason.NO_ENABLED_GROUPS, emptyList())
        if (localHour(nowMs, zone) < config.morningHour) return Decision(Reason.BEFORE_MORNING_HOUR, emptyList())
        val today = todayString(nowMs, zone)
        val due = enabled.filter { lastExportDates[it.id] != today }
        if (due.isEmpty()) return Decision(Reason.ALL_EXPORTED_TODAY, emptyList())
        if (autoAttemptsToday >= MAX_AUTO_ATTEMPTS_PER_DAY) return Decision(Reason.DAILY_LIMIT, emptyList())
        if (nowMs - lastAutoAttemptAt < THROTTLE_MS && nowMs >= lastAutoAttemptAt) {
            return Decision(Reason.THROTTLED, emptyList())
        }
        return Decision(Reason.OK, due)
    }

    /** Groups for a manual run: explicit ids (any that exist in config) or all enabled groups. */
    fun groupsForManualRun(config: AutomationConfig?, requestedIds: List<String>?): List<GroupConfig> {
        if (config == null) return emptyList()
        if (requestedIds.isNullOrEmpty()) return config.groups.filter { it.enabled }
        // Keep the config order, ignore unknown ids.
        return config.groups.filter { it.id in requestedIds }
    }
}
