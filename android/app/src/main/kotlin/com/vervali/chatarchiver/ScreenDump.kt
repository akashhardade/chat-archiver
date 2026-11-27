package com.vervali.chatarchiver

import android.accessibilityservice.AccessibilityService
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Diagnostic: writes the full accessibility tree (all windows, invisible nodes flagged) to a text file. */
object ScreenDump {
    fun render(screen: Screen): String = buildString {
        append("# Chat Archiver screen dump ").append(Date()).append('\n')
        append("# windows: ").append(screen.windows.size).append(", nodes: ").append(screen.nodes.size).append('\n')
        var currentWindow = -1
        for (n in screen.nodes) {
            if (n.windowIndex != currentWindow) {
                currentWindow = n.windowIndex
                val w = screen.windows.firstOrNull { it.index == currentWindow }
                append("\n=== window ").append(currentWindow)
                    .append(" pkg=").append(w?.pkg)
                    .append(" type=").append(w?.type)
                    .append(" layer=").append(w?.layer)
                    .append(" active=").append(w?.active)
                    .append(" focused=").append(w?.focused)
                    .append(" title=").append(w?.title)
                    .append(" ===\n")
            }
            append("  ".repeat(n.depth.coerceAtMost(40))).append(n.describe()).append('\n')
        }
    }

    fun dumpToFile(service: AccessibilityService): File {
        val dir = File(service.filesDir, "diagnostics").apply { mkdirs() }
        val ts = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())
        val file = File(dir, "screen-$ts.txt")
        file.writeText(render(ScreenReader.capture(service, includeInvisible = true)))
        return file
    }
}
