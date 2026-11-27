package com.vervali.chatarchiver

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId
import java.time.ZonedDateTime

class RunPolicyTest {
    private val zone = ZoneId.of("Asia/Kolkata")
    private fun at(h: Int, m: Int = 0, day: Int = 10): Long =
        ZonedDateTime.of(2026, 3, day, h, m, 0, 0, zone).toInstant().toEpochMilli()

    private val a = GroupConfig("a", "Alpha", true)
    private val b = GroupConfig("b", "Beta", true)
    private val off = GroupConfig("c", "Gamma", false)
    private fun cfg(enabled: Boolean = true, hour: Int = 7, vararg g: GroupConfig) =
        AutomationConfig(enabled, hour, g.toList())

    private fun decide(
        c: AutomationConfig?, last: Map<String, String> = emptyMap(), attempt: Long = 0, now: Long, attemptsToday: Int = 0,
    ) = RunPolicy.decideOnUnlock(c, last, attempt, now, zone, attemptsToday)

    @Test fun disabledOrMissingConfig() {
        assertEquals(RunPolicy.Reason.DISABLED, decide(null, now = at(9)).reason)
        assertEquals(RunPolicy.Reason.DISABLED, decide(cfg(false, 7, a), now = at(9)).reason)
    }

    @Test fun noEnabledGroups() {
        assertEquals(RunPolicy.Reason.NO_ENABLED_GROUPS, decide(cfg(true, 7, off), now = at(9)).reason)
        assertEquals(RunPolicy.Reason.NO_ENABLED_GROUPS, decide(cfg(true, 7), now = at(9)).reason)
    }

    @Test fun hourGate() {
        assertEquals(RunPolicy.Reason.BEFORE_MORNING_HOUR, decide(cfg(true, 7, a), now = at(6, 59)).reason)
        assertTrue(decide(cfg(true, 7, a), now = at(7, 0)).shouldRun)
        assertTrue(decide(cfg(true, 0, a), now = at(0, 5)).shouldRun)
    }

    @Test fun onlyGroupsNotExportedTodayAreRun() {
        val today = RunPolicy.todayString(at(9), zone)
        val d = decide(cfg(true, 7, a, b, off), mapOf("a" to today, "b" to "2026-03-09"), now = at(9))
        assertTrue(d.shouldRun)
        assertEquals(listOf("b"), d.groups.map { it.id })
    }

    @Test fun allExportedToday() {
        val today = RunPolicy.todayString(at(9), zone)
        val d = decide(cfg(true, 7, a, b), mapOf("a" to today, "b" to today), now = at(9))
        assertEquals(RunPolicy.Reason.ALL_EXPORTED_TODAY, d.reason)
    }

    @Test fun throttleTwentyMinutes() {
        val c = cfg(true, 7, a)
        assertEquals(RunPolicy.Reason.THROTTLED, decide(c, attempt = at(9, 0), now = at(9, 19)).reason)
        assertTrue(decide(c, attempt = at(9, 0), now = at(9, 20)).shouldRun)
        assertTrue(decide(c, attempt = 0, now = at(9, 0)).shouldRun)
    }

    @Test fun clockGoingBackwardsDoesNotThrottleForever() {
        assertTrue(decide(cfg(true, 7, a), attempt = at(12, 0), now = at(9, 0)).shouldRun)
    }

    @Test fun newDayResetsExported() {
        val yesterday = RunPolicy.todayString(at(9, 0, day = 9), zone)
        assertTrue(decide(cfg(true, 7, a), mapOf("a" to yesterday), now = at(9, 0, day = 10)).shouldRun)
    }

    @Test fun manualRunGroups() {
        val c = cfg(true, 7, a, b, off)
        assertEquals(listOf("a", "b"), RunPolicy.groupsForManualRun(c, null).map { it.id })
        assertEquals(listOf("a", "b"), RunPolicy.groupsForManualRun(c, emptyList()).map { it.id })
        assertEquals(listOf("c"), RunPolicy.groupsForManualRun(c, listOf("c", "zzz")).map { it.id })
        assertTrue(RunPolicy.groupsForManualRun(null, null).isEmpty())
    }

    @Test fun atMostThreeAutomaticAttemptsPerDay() {
        val c = cfg(true, 7, a)
        assertTrue(decide(c, now = at(9), attemptsToday = 2).shouldRun)
        assertEquals(RunPolicy.Reason.DAILY_LIMIT, decide(c, now = at(9), attemptsToday = 3).reason)
        // Already exported today wins over the cap (nothing to do anyway).
        val today = RunPolicy.todayString(at(9), zone)
        assertEquals(RunPolicy.Reason.ALL_EXPORTED_TODAY, decide(c, mapOf("a" to today), now = at(9), attemptsToday = 5).reason)
    }
}
