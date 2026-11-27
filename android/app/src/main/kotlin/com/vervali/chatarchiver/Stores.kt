package com.vervali.chatarchiver

import android.content.Context
import android.content.SharedPreferences
import java.io.File

/** Minimal string key/value abstraction so ConfigStore is testable on the JVM. */
interface KeyValueStore {
    fun getString(key: String): String?
    fun putString(key: String, value: String?)
    fun getLong(key: String, default: Long): Long
    fun putLong(key: String, value: Long)
}

class PrefsKeyValueStore(private val prefs: SharedPreferences) : KeyValueStore {
    override fun getString(key: String): String? = prefs.getString(key, null)
    override fun putString(key: String, value: String?) {
        prefs.edit().putString(key, value).apply()
    }
    override fun getLong(key: String, default: Long): Long = prefs.getLong(key, default)
    override fun putLong(key: String, value: Long) {
        prefs.edit().putLong(key, value).apply()
    }
}

/** Automation config, per-group `lastExportDate` and the last automatic attempt time. Thread-safe. */
class ConfigStore(private val kv: KeyValueStore) {
    private val lock = Any()

    fun saveConfig(config: AutomationConfig) = synchronized(lock) {
        kv.putString(KEY_CONFIG, JsonUtil.mapToString(config.toMap()))
    }

    fun getConfig(): AutomationConfig? = synchronized(lock) {
        val raw = kv.getString(KEY_CONFIG) ?: return null
        JsonUtil.stringToMap(raw)?.let { AutomationConfig.fromMap(it) }
    }

    /** groupId -> "yyyy-MM-dd" (local date) of the last successful export. */
    fun lastExportDates(): Map<String, String> = synchronized(lock) {
        val raw = kv.getString(KEY_LAST_EXPORT) ?: return emptyMap()
        JsonUtil.stringToMap(raw)?.mapNotNull { (k, v) -> (v as? String)?.let { k to it } }?.toMap()
            ?: emptyMap()
    }

    fun markExported(groupId: String, date: String) = synchronized(lock) {
        val m = LinkedHashMap<String, Any?>(lastExportDates())
        m[groupId] = date
        kv.putString(KEY_LAST_EXPORT, JsonUtil.mapToString(m))
    }

    fun lastAutoAttemptAt(): Long = synchronized(lock) { kv.getLong(KEY_LAST_ATTEMPT, 0L) }

    fun setLastAutoAttemptAt(ms: Long) = synchronized(lock) { kv.putLong(KEY_LAST_ATTEMPT, ms) }

    /** Number of automatic attempts made on local date [today] ("yyyy-MM-dd"); 0 for any other day. */
    fun autoAttemptsOn(today: String): Int = synchronized(lock) {
        if (kv.getString(KEY_ATTEMPTS_DATE) != today) 0 else kv.getLong(KEY_ATTEMPTS_COUNT, 0L).toInt()
    }

    /** Records one automatic attempt at [ms] on local date [today]. Returns the new count for that day. */
    fun recordAutoAttempt(today: String, ms: Long): Int = synchronized(lock) {
        val count = autoAttemptsOn(today) + 1
        kv.putString(KEY_ATTEMPTS_DATE, today)
        kv.putLong(KEY_ATTEMPTS_COUNT, count.toLong())
        kv.putLong(KEY_LAST_ATTEMPT, ms)
        count
    }

    companion object {
        private const val KEY_CONFIG = "config"
        private const val KEY_LAST_EXPORT = "last_export_dates"
        private const val KEY_LAST_ATTEMPT = "last_auto_attempt_at"
        private const val KEY_ATTEMPTS_DATE = "auto_attempts_date"
        private const val KEY_ATTEMPTS_COUNT = "auto_attempts_count"
    }
}

/**
 * Pending exports: files in [dir] named `<jobId>.<ext>` plus an `index.json` listing their records.
 * Thread-safe within the process (activity + service share one instance via [Stores]).
 */
class PendingStore(private val dir: File) {
    private val lock = Any()
    private val indexFile get() = File(dir, "index.json")

    init {
        dir.mkdirs()
    }

    /** Destination for a new job's file. Built only from the job id and a sanitised extension. */
    fun fileFor(jobId: String, ext: String): File {
        val safeExt = ext.filter { it.isLetterOrDigit() }.take(8).ifEmpty { "bin" }
        val safeId = jobId.filter { it.isLetterOrDigit() || it == '-' }
        return File(dir, "$safeId.$safeExt")
    }

    fun add(export: PendingExport) = synchronized(lock) {
        val all = readAll().filter { it.jobId != export.jobId } + export
        writeAll(all)
    }

    /** Oldest first. Records whose file has disappeared are dropped. */
    fun list(): List<PendingExport> = synchronized(lock) {
        val all = readAll()
        val alive = all.filter { File(it.filePath).exists() }
        if (alive.size != all.size) writeAll(alive)
        alive.sortedBy { it.receivedAt }
    }

    fun get(jobId: String): PendingExport? = synchronized(lock) { readAll().firstOrNull { it.jobId == jobId } }

    /** Deletes the stored file (only if it lives inside [dir]) and its record. */
    fun remove(jobId: String): Boolean = synchronized(lock) {
        val all = readAll()
        val rec = all.firstOrNull { it.jobId == jobId } ?: return false
        try {
            val f = File(rec.filePath).canonicalFile
            if (f.parentFile == dir.canonicalFile) f.delete()
        } catch (_: Exception) {
        }
        writeAll(all.filter { it.jobId != jobId })
        true
    }

    private fun readAll(): List<PendingExport> {
        val f = indexFile
        if (!f.exists()) return emptyList()
        return try {
            val arr = JsonUtil.fromJson(org.json.JSONArray(f.readText())) as? List<*> ?: return emptyList()
            arr.mapNotNull { (it as? Map<*, *>)?.let(PendingExport::fromMap) }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun writeAll(list: List<PendingExport>) {
        dir.mkdirs()
        val tmp = File(dir, "index.json.tmp")
        tmp.writeText(JsonUtil.toJson(list.map { it.toMap() }).toString())
        if (!tmp.renameTo(indexFile)) {
            indexFile.writeText(tmp.readText())
            tmp.delete()
        }
    }
}

/** Last RunReport kept as a single JSON file. */
class RunReportStore(private val file: File) {
    private val lock = Any()

    fun save(report: RunReport) = synchronized(lock) {
        file.parentFile?.mkdirs()
        file.writeText(JsonUtil.mapToString(report.toMap()))
    }

    fun load(): RunReport? = synchronized(lock) {
        if (!file.exists()) return null
        try {
            JsonUtil.stringToMap(file.readText())?.let { RunReport.fromMap(it) }
        } catch (_: Exception) {
            null
        }
    }
}

/** Process-wide singletons for the stores (activity, service and share receiver share a process). */
object Stores {
    @Volatile private var config: ConfigStore? = null
    @Volatile private var pending: PendingStore? = null
    @Volatile private var report: RunReportStore? = null

    fun config(ctx: Context): ConfigStore = config ?: synchronized(this) {
        config ?: ConfigStore(
            PrefsKeyValueStore(ctx.applicationContext.getSharedPreferences("automation", Context.MODE_PRIVATE)),
        ).also { config = it }
    }

    fun pending(ctx: Context): PendingStore = pending ?: synchronized(this) {
        pending ?: PendingStore(File(ctx.applicationContext.filesDir, "pending")).also { pending = it }
    }

    fun report(ctx: Context): RunReportStore = report ?: synchronized(this) {
        report ?: RunReportStore(File(ctx.applicationContext.filesDir, "last_run_report.json"))
            .also { report = it }
    }
}
