package com.vervali.chatarchiver

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.util.Log
import java.io.File
import java.util.UUID

/**
 * Invisible share target ("Save to Chat Archiver"). Receives WhatsApp's exported transcript (.txt/.zip),
 * streams it into app-private storage, records it in [PendingStore] and finishes.
 *
 * The copy runs on a worker thread; the (translucent, UI-less) activity stays alive until it is done so the
 * sender's temporary URI read grant remains valid, then finishes.
 */
class ShareReceiverActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val appContext = applicationContext
        val incoming = intent
        // Capture attribution NOW (main thread) so a late-finishing copy is still attributed correctly.
        val attribution = ExportAccessibilityService.instance?.runner?.awaitingShare
        val contentResolver = contentResolver
        Thread({
            var stored = 0
            try {
                stored = handle(appContext, contentResolver, incoming, attribution)
            } catch (e: Exception) {
                Log.e(TAG, "share handling failed", e)
            } finally {
                runOnUiThread {
                    if (stored > 0 && attribution == null) openAppToUpload(appContext)
                    finish()
                }
            }
        }, "share-receiver").start()
    }

    /**
     * A manual share (the user picked "Save to Chat Archiver" in WhatsApp themselves, outside a run): open the
     * app so the export is uploaded right away and the user sees the result. Never while a run is in progress,
     * because that would take the screen away from the automation (a late share of a timed-out run lands here).
     */
    private fun openAppToUpload(ctx: android.content.Context) {
        if (ExportAccessibilityService.instance?.runner?.isRunning == true) return
        try {
            startActivity(
                Intent(ctx, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    putExtra(MainActivity.EXTRA_PROCESS_PENDING, true)
                },
            )
        } catch (e: Exception) {
            Log.w(TAG, "could not open the app after a manual share", e)
        }
    }

    /** Stores every shared file as a pending export; returns how many were stored. */
    private fun handle(
        ctx: android.content.Context,
        resolver: android.content.ContentResolver,
        intent: Intent,
        attribution: ShareAttribution?,
    ): Int {
        val action = intent.action
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return 0
        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
        val declaredMime = intent.type
        val store = Stores.pending(ctx)

        val uris = collectUris(intent)
        val received = ArrayList<PendingExport>()

        for (uri in uris) {
            try {
                received += copyUri(ctx, resolver, store, uri, declaredMime, subject, attribution)
            } catch (e: Exception) {
                Log.e(TAG, "copying $uri failed", e)
            }
        }
        if (uris.isEmpty()) {
            val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
            if (!text.isNullOrEmpty()) received += saveText(store, text, subject, attribution)
        }

        val runner = ExportAccessibilityService.instance?.runner
        for ((i, p) in received.withIndex()) {
            store.add(p)
            Log.d(TAG, "received export job=${p.jobId} group=${p.groupName} trigger=${p.trigger} file=${p.fileName}")
            AutomationEvents.exportReceived(p.jobId)
            if (i == 0) runner?.notifyShareReceived(p.jobId, attribution)
        }
        return received.size
    }

    private fun collectUris(intent: Intent): List<Uri> {
        val out = LinkedHashSet<Uri>()
        @Suppress("DEPRECATION")
        if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let { out.addAll(it) }
        } else {
            (intent.getParcelableExtra<android.os.Parcelable>(Intent.EXTRA_STREAM) as? Uri)?.let { out.add(it) }
        }
        if (out.isEmpty()) {
            val clip: ClipData? = intent.clipData
            if (clip != null) {
                for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let { out.add(it) }
            }
        }
        return out.toList()
    }

    private fun copyUri(
        ctx: android.content.Context,
        resolver: android.content.ContentResolver,
        store: PendingStore,
        uri: Uri,
        declaredMime: String?,
        subject: String?,
        attribution: ShareAttribution?,
    ): PendingExport {
        val rawName = queryDisplayName(resolver, uri) ?: uri.lastPathSegment
        val displayName = ChatNames.sanitizeFileName(rawName, fallback = "WhatsApp Chat.txt")
        val streamMime = try { resolver.getType(uri) } catch (_: Exception) { null }
        val ext = ChatNames.extensionFor(displayName, streamMime ?: declaredMime)
        val jobId = UUID.randomUUID().toString()
        val dest = store.fileFor(jobId, ext)
        // Stream; never load the whole file into memory.
        try {
            val input = resolver.openInputStream(uri) ?: throw java.io.IOException("cannot open $uri")
            input.use { ins -> dest.outputStream().use { outs -> ins.copyTo(outs, 64 * 1024) } }
        } catch (e: Exception) {
            dest.delete() // never leave a half-written file behind
            throw e
        }
        return build(jobId, dest, displayName, ChatNames.mimeForExtension(ext, streamMime ?: declaredMime), subject, attribution)
    }

    private fun saveText(store: PendingStore, text: String, subject: String?, attribution: ShareAttribution?): PendingExport {
        val jobId = UUID.randomUUID().toString()
        val dest = store.fileFor(jobId, "txt")
        dest.writeText(text, Charsets.UTF_8)
        val name = ChatNames.sanitizeFileName(
            if (!subject.isNullOrBlank()) "$subject.txt" else null,
            fallback = "WhatsApp Chat.txt",
        )
        return build(jobId, dest, name, "text/plain", subject, attribution)
    }

    private fun build(
        jobId: String,
        file: File,
        displayName: String,
        mime: String,
        subject: String?,
        attribution: ShareAttribution?,
    ): PendingExport {
        val now = System.currentTimeMillis()
        return if (attribution != null) {
            PendingExport(
                jobId, attribution.groupId, attribution.groupName, file.absolutePath, displayName, mime,
                now, attribution.runId, attribution.trigger,
            )
        } else {
            PendingExport(
                jobId, null, ChatNames.parseGroupName(subject, displayName), file.absolutePath, displayName, mime,
                now, null, Trigger.SHARE,
            )
        }
    }

    private fun queryDisplayName(resolver: android.content.ContentResolver, uri: Uri): String? {
        if (uri.scheme != "content") return null
        return try {
            resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) c.getString(0) else null
            }
        } catch (_: Exception) {
            null
        }
    }

    companion object {
        private const val TAG = "ChatArchiver"
    }
}
