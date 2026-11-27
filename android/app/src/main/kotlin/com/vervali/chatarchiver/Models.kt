package com.vervali.chatarchiver

/** Config groups as sent by Dart via `saveConfig`. */
data class GroupConfig(val id: String, val name: String, val enabled: Boolean) {
    fun toMap(): Map<String, Any?> = mapOf("id" to id, "name" to name, "enabled" to enabled)

    companion object {
        fun fromMap(m: Map<*, *>): GroupConfig? {
            val id = m["id"] as? String ?: return null
            val name = m["name"] as? String ?: return null
            return GroupConfig(id, name, (m["enabled"] as? Boolean) ?: true)
        }
    }
}

data class AutomationConfig(
    val enabled: Boolean,
    val morningHour: Int,
    val groups: List<GroupConfig>,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "enabled" to enabled,
        "morningHour" to morningHour,
        "groups" to groups.map { it.toMap() },
    )

    companion object {
        fun fromMap(m: Map<*, *>): AutomationConfig {
            val hour = ((m["morningHour"] as? Number)?.toInt() ?: 7).coerceIn(0, 23)
            val groups = (m["groups"] as? List<*>)
                ?.mapNotNull { (it as? Map<*, *>)?.let(GroupConfig::fromMap) }
                ?: emptyList()
            return AutomationConfig((m["enabled"] as? Boolean) ?: false, hour, groups)
        }
    }
}

object Trigger {
    const val UNLOCK = "unlock"
    const val MANUAL = "manual"
    const val SHARE = "share"
}

/** Error codes from the contract. */
object ErrorCode {
    const val WHATSAPP_NOT_INSTALLED = "whatsapp_not_installed"
    const val SEARCH_NOT_FOUND = "search_not_found"
    const val GROUP_NOT_FOUND = "group_not_found"
    const val WRONG_CHAT = "wrong_chat"
    const val MENU_NOT_FOUND = "menu_not_found"
    const val EXPORT_NOT_FOUND = "export_not_found"
    const val SHARE_TARGET_NOT_FOUND = "share_target_not_found"
    const val SHARE_NOT_RECEIVED = "share_not_received"
    const val TIMEOUT = "timeout"
    const val CANCELLED = "cancelled"
    const val SCREEN_LOCKED = "screen_locked"
    const val UNEXPECTED_SCREEN = "unexpected_screen"
}

data class PendingExport(
    val jobId: String,
    val groupId: String?,
    val groupName: String?,
    val filePath: String,
    val fileName: String,
    val mimeType: String,
    val receivedAt: Long,
    val runId: String?,
    val trigger: String,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "jobId" to jobId,
        "groupId" to groupId,
        "groupName" to groupName,
        "filePath" to filePath,
        "fileName" to fileName,
        "mimeType" to mimeType,
        "receivedAt" to receivedAt,
        "runId" to runId,
        "trigger" to trigger,
    )

    companion object {
        fun fromMap(m: Map<*, *>): PendingExport? {
            return PendingExport(
                jobId = m["jobId"] as? String ?: return null,
                groupId = m["groupId"] as? String,
                groupName = m["groupName"] as? String,
                filePath = m["filePath"] as? String ?: return null,
                fileName = m["fileName"] as? String ?: "export.txt",
                mimeType = m["mimeType"] as? String ?: "application/octet-stream",
                receivedAt = (m["receivedAt"] as? Number)?.toLong() ?: 0L,
                runId = m["runId"] as? String,
                trigger = m["trigger"] as? String ?: Trigger.SHARE,
            )
        }
    }
}

data class GroupResult(
    val groupId: String,
    val groupName: String,
    val status: String, // exported | failed | skipped
    val error: String?,
    val step: String?,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "groupId" to groupId,
        "groupName" to groupName,
        "status" to status,
        "error" to error,
        "step" to step,
    )

    companion object {
        const val EXPORTED = "exported"
        const val FAILED = "failed"
        const val SKIPPED = "skipped"

        fun fromMap(m: Map<*, *>): GroupResult? {
            return GroupResult(
                groupId = m["groupId"] as? String ?: return null,
                groupName = m["groupName"] as? String ?: "",
                status = m["status"] as? String ?: FAILED,
                error = m["error"] as? String,
                step = m["step"] as? String,
            )
        }
    }
}

data class RunReport(
    val runId: String,
    val trigger: String,
    val startedAt: Long,
    val finishedAt: Long,
    val results: List<GroupResult>,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "runId" to runId,
        "trigger" to trigger,
        "startedAt" to startedAt,
        "finishedAt" to finishedAt,
        "results" to results.map { it.toMap() },
    )

    companion object {
        fun fromMap(m: Map<*, *>): RunReport? {
            return RunReport(
                runId = m["runId"] as? String ?: return null,
                trigger = m["trigger"] as? String ?: Trigger.MANUAL,
                startedAt = (m["startedAt"] as? Number)?.toLong() ?: 0L,
                finishedAt = (m["finishedAt"] as? Number)?.toLong() ?: 0L,
                results = (m["results"] as? List<*>)
                    ?.mapNotNull { (it as? Map<*, *>)?.let(GroupResult::fromMap) } ?: emptyList(),
            )
        }
    }
}
