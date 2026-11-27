package com.vervali.chatarchiver

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class StoresTest {
    @get:Rule val tmp = TemporaryFolder()

    private class MemKv : KeyValueStore {
        val m = HashMap<String, Any?>()
        override fun getString(key: String) = m[key] as String?
        override fun putString(key: String, value: String?) { m[key] = value }
        override fun getLong(key: String, default: Long) = (m[key] as Long?) ?: default
        override fun putLong(key: String, value: Long) { m[key] = value }
    }

    @Test fun configRoundTrip() {
        val store = ConfigStore(MemKv())
        assertNull(store.getConfig())
        // Shaped like the map Dart sends (ints, nested lists/maps).
        val sent = mapOf(
            "enabled" to true, "morningHour" to 8,
            "groups" to listOf(
                mapOf("id" to "g1", "name" to "Project Alpha", "enabled" to true),
                mapOf("id" to "g2", "name" to "Family", "enabled" to false),
            ),
        )
        store.saveConfig(AutomationConfig.fromMap(sent))
        assertEquals(sent, store.getConfig()!!.toMap())
    }

    @Test fun lastExportDatesAndAttempt() {
        val store = ConfigStore(MemKv())
        assertTrue(store.lastExportDates().isEmpty())
        store.markExported("g1", "2026-03-10")
        store.markExported("g2", "2026-03-09")
        store.markExported("g1", "2026-03-11")
        assertEquals(mapOf("g1" to "2026-03-11", "g2" to "2026-03-09"), store.lastExportDates())
        assertEquals(0L, store.lastAutoAttemptAt())
        store.setLastAutoAttemptAt(123L)
        assertEquals(123L, store.lastAutoAttemptAt())
    }

    @Test fun autoAttemptsAreCountedPerDay() {
        val store = ConfigStore(MemKv())
        assertEquals(0, store.autoAttemptsOn("2026-03-10"))
        assertEquals(1, store.recordAutoAttempt("2026-03-10", 100L))
        assertEquals(2, store.recordAutoAttempt("2026-03-10", 200L))
        assertEquals(2, store.autoAttemptsOn("2026-03-10"))
        assertEquals(200L, store.lastAutoAttemptAt())
        // A new day starts from zero.
        assertEquals(0, store.autoAttemptsOn("2026-03-11"))
        assertEquals(1, store.recordAutoAttempt("2026-03-11", 300L))
        assertEquals(0, store.autoAttemptsOn("2026-03-10"))
    }

    @Test fun pendingRoundTripAndAck() {
        val dir = tmp.newFolder("pending")
        val store = PendingStore(dir)
        assertTrue(store.list().isEmpty())

        val f1 = store.fileFor("job-1", "txt").also { it.writeText("hello") }
        val f2 = store.fileFor("job-2", "zip").also { it.writeText("zipdata") }
        val p1 = PendingExport("job-1", "g1", "Alpha", f1.absolutePath, "WhatsApp Chat with Alpha.txt", "text/plain", 200L, "run-1", "manual")
        val p2 = PendingExport("job-2", null, "Beta", f2.absolutePath, "WhatsApp Chat with Beta.zip", "application/zip", 100L, null, "share")
        store.add(p1)
        store.add(p2)

        // Re-open to prove persistence; oldest first.
        val reopened = PendingStore(dir)
        assertEquals(listOf(p2, p1), reopened.list())
        assertEquals(p1.toMap(), PendingExport.fromMap(p1.toMap())!!.toMap())

        assertTrue(reopened.remove("job-1"))
        assertFalse(f1.exists())
        assertEquals(listOf(p2), reopened.list())
        assertFalse(reopened.remove("nope"))
    }

    @Test fun pendingDropsRecordsWhoseFileVanished() {
        val dir = tmp.newFolder("pending2")
        val store = PendingStore(dir)
        val f = store.fileFor("job-x", "txt").also { it.writeText("x") }
        store.add(PendingExport("job-x", null, null, f.absolutePath, "a.txt", "text/plain", 1L, null, "share"))
        f.delete()
        assertTrue(store.list().isEmpty())
    }

    @Test fun pendingRemoveNeverDeletesOutsideItsFolder() {
        val dir = tmp.newFolder("pending3")
        val outside = tmp.newFile("outside.txt")
        val store = PendingStore(dir)
        store.add(PendingExport("job-o", null, null, outside.absolutePath, "o.txt", "text/plain", 1L, null, "share"))
        store.remove("job-o")
        assertTrue(outside.exists())
    }

    @Test fun fileForIgnoresHostileInput() {
        val store = PendingStore(tmp.newFolder("pending4"))
        val f = store.fileFor("../../x", "t/x/t")
        assertEquals(store.fileFor("xx", "txt").parentFile, f.parentFile)
        assertFalse(f.name.contains("/"))
    }

    @Test fun runReportRoundTrip() {
        val store = RunReportStore(tmp.newFile("report.json"))
        val report = RunReport(
            "run-1", "unlock", 1000L, 2000L,
            listOf(
                GroupResult("g1", "Alpha", "exported", null, "wait_receipt"),
                GroupResult("g2", "Beta", "failed", "group_not_found", "pick_result"),
                GroupResult("g3", "Gamma", "skipped", "cancelled", null),
            ),
        )
        store.save(report)
        assertEquals(report, store.load())
        assertNotNull(store.load())
    }
}
