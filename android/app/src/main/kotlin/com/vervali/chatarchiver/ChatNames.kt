package com.vervali.chatarchiver

/** Pure helpers for group names, share subjects and safe file names. */
object ChatNames {
    // LRM/RLM (required), plus other invisible bidi controls WhatsApp may wrap names with.
    private val INVISIBLE = Regex("[‎‏‪-‮⁦-⁩﻿​]")
    private val WS = Regex("\\s+")

    /** trim, collapse whitespace, strip LRM/RLM (and other invisible bidi marks). */
    fun normalize(s: String?): String {
        if (s == null) return ""
        return s.replace(INVISIBLE, "").replace(' ', ' ').replace(WS, " ").trim()
    }

    /** Exact (case-sensitive) comparison after normalisation. Empty never matches. */
    fun matches(a: String?, b: String?): Boolean {
        val na = normalize(a)
        return na.isNotEmpty() && na == normalize(b)
    }

    /** Case-insensitive comparison used for UI labels (menu items, share target). */
    fun labelEquals(a: String?, b: String?): Boolean {
        val na = normalize(a)
        return na.isNotEmpty() && na.equals(normalize(b), ignoreCase = true)
    }

    fun labelContains(haystack: String?, needle: String): Boolean {
        val n = normalize(needle)
        return n.isNotEmpty() && normalize(haystack).contains(n, ignoreCase = true)
    }

    private val SUBJECT = Regex("^WhatsApp Chat(?: with| -)\\s+(.+?)\\s*$", RegexOption.IGNORE_CASE)
    private val EXT = Regex("\\.(txt|zip)$", RegexOption.IGNORE_CASE)
    private val DUP_SUFFIX = Regex("\\s*\\(\\d+\\)$")

    /**
     * Group name from `EXTRA_SUBJECT` ("WhatsApp Chat with X" / "WhatsApp Chat - X") or,
     * as fallback, from the file name ("WhatsApp Chat with X.txt", "... - X.zip").
     */
    fun parseGroupName(subject: String?, fileName: String?): String? {
        val s = normalize(subject)
        if (s.isNotEmpty()) {
            val n = SUBJECT.find(s)?.groupValues?.get(1)?.let { normalize(it) }
            if (!n.isNullOrEmpty()) return n
        }
        val f = normalize(fileName?.substringAfterLast('/')?.substringAfterLast('\\'))
        if (f.isNotEmpty()) {
            val base = f.replace(EXT, "").replace(DUP_SUFFIX, "")
            val n = SUBJECT.find(base)?.groupValues?.get(1)?.let { normalize(it) }
            if (!n.isNullOrEmpty()) return n
        }
        return null
    }

    /** Strips directories, control characters and ".." so a display name can never escape a folder. */
    fun sanitizeFileName(name: String?, fallback: String = "export"): String {
        var n = (name ?: "").substringAfterLast('/').substringAfterLast('\\')
        n = n.filter { it.code >= 0x20 && it.code != 0x7F }
        n = n.replace(":", "_").replace("*", "_").replace("?", "_").replace("\"", "_")
            .replace("<", "_").replace(">", "_").replace("|", "_")
        while (n.contains("..")) n = n.replace("..", ".")
        n = n.trim().trimStart('.')
        if (n.length > 120) {
            val ext = n.substringAfterLast('.', "").take(8)
            n = n.take(100) + if (ext.isNotEmpty()) ".$ext" else ""
        }
        return n.ifBlank { fallback }
    }

    /** Extension (without dot) for the app-private copy: txt, zip, or a short alnum extension, else bin. */
    fun extensionFor(displayName: String?, mimeType: String?): String {
        val fromName = displayName?.substringAfterLast('.', "")?.lowercase().orEmpty()
        if (fromName == "txt" || fromName == "zip") return fromName
        val m = mimeType?.lowercase().orEmpty()
        if (m == "text/plain") return "txt"
        if (m == "application/zip" || m == "application/x-zip-compressed") return "zip"
        if (fromName.isNotEmpty() && fromName.length <= 5 && fromName.all { it.isLetterOrDigit() }) return fromName
        return "bin"
    }

    fun mimeForExtension(ext: String, declared: String?): String {
        val d = declared?.lowercase()
        if (d != null && d != "*/*" && d != "application/octet-stream") return d
        return when (ext) {
            "txt" -> "text/plain"
            "zip" -> "application/zip"
            else -> d ?: "application/octet-stream"
        }
    }
}
