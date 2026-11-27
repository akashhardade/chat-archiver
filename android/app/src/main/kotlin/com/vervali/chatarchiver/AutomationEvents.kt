package com.vervali.chatarchiver

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/** Best-effort event delivery to Dart. Safe to call from any thread; dropped when nobody listens. */
object AutomationEvents : EventChannel.StreamHandler {
    const val CHANNEL = "chat_archiver/automation/events"

    @Volatile private var sink: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    fun emit(event: Map<String, Any?>) {
        main.post {
            try {
                sink?.success(event)
            } catch (_: Exception) {
                // best effort
            }
        }
    }

    fun runStarted(runId: String, trigger: String, groupIds: List<String>) =
        emit(mapOf("type" to "runStarted", "runId" to runId, "trigger" to trigger, "groupIds" to groupIds))

    fun groupStarted(runId: String, groupId: String) =
        emit(mapOf("type" to "groupStarted", "runId" to runId, "groupId" to groupId))

    fun groupExported(runId: String, groupId: String, jobId: String?) =
        emit(mapOf("type" to "groupExported", "runId" to runId, "groupId" to groupId, "jobId" to jobId))

    fun groupFailed(runId: String, groupId: String, error: String, step: String?) =
        emit(mapOf("type" to "groupFailed", "runId" to runId, "groupId" to groupId, "error" to error, "step" to step))

    fun runFinished(runId: String, report: RunReport) =
        emit(mapOf("type" to "runFinished", "runId" to runId, "report" to report.toMap()))

    fun exportReceived(jobId: String) = emit(mapOf("type" to "exportReceived", "jobId" to jobId))
}
