package com.vervali.chatarchiver

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatNamesTest {
    @Test fun normalizeTrimsCollapsesAndStripsMarks() {
        assertEquals("Project Alpha", ChatNames.normalize("  Project ‎  Alpha‏ "))
        assertEquals("a b", ChatNames.normalize("a   b"))
        assertEquals("", ChatNames.normalize(null))
    }

    @Test fun matchesIsExactAfterNormalisation() {
        assertTrue(ChatNames.matches("‎Project  Alpha", "Project Alpha"))
        assertFalse(ChatNames.matches("Project Alpha 2", "Project Alpha"))
        assertFalse(ChatNames.matches("project alpha", "Project Alpha")) // case-sensitive
        assertFalse(ChatNames.matches("", ""))
        assertFalse(ChatNames.matches(null, "x"))
    }

    @Test fun labelEqualsIgnoresCase() {
        assertTrue(ChatNames.labelEquals("WITHOUT MEDIA", "Without media"))
        assertFalse(ChatNames.labelEquals("Without media now", "Without media"))
        assertTrue(ChatNames.labelContains("Ask Meta AI or Search", "search"))
    }

    @Test fun parsesSubject() {
        assertEquals("Project Alpha", ChatNames.parseGroupName("WhatsApp Chat with Project Alpha", null))
        assertEquals("Project Alpha", ChatNames.parseGroupName("WhatsApp Chat - Project Alpha", null))
        assertEquals("Family (2)", ChatNames.parseGroupName("WhatsApp Chat with Family (2)", null))
    }

    @Test fun parsesFileNameFallback() {
        assertEquals("Project Alpha", ChatNames.parseGroupName(null, "WhatsApp Chat with Project Alpha.txt"))
        assertEquals("Project Alpha", ChatNames.parseGroupName("", "WhatsApp Chat - Project Alpha.zip"))
        assertEquals("Project Alpha", ChatNames.parseGroupName(null, "/sdcard/x/WhatsApp Chat with Project Alpha (1).txt"))
        assertNull(ChatNames.parseGroupName("Hello", "notes.txt"))
        assertNull(ChatNames.parseGroupName(null, null))
    }

    @Test fun sanitizeBlocksTraversal() {
        assertEquals("passwd", ChatNames.sanitizeFileName("../../etc/passwd"))
        assertEquals("evil.txt", ChatNames.sanitizeFileName("..\\..\\evil.txt"))
        assertEquals("export", ChatNames.sanitizeFileName(".."))
        assertEquals("export", ChatNames.sanitizeFileName(null))
        assertEquals("WhatsApp Chat with A_B.txt", ChatNames.sanitizeFileName("WhatsApp Chat with A:B.txt"))
        assertFalse(ChatNames.sanitizeFileName("a..b/..c").contains(".."))
    }

    @Test fun extensions() {
        assertEquals("txt", ChatNames.extensionFor("x.TXT", null))
        assertEquals("zip", ChatNames.extensionFor("x", "application/x-zip-compressed"))
        assertEquals("txt", ChatNames.extensionFor("noext", "text/plain"))
        assertEquals("bin", ChatNames.extensionFor("noext", "application/octet-stream"))
        assertEquals("text/plain", ChatNames.mimeForExtension("txt", "*/*"))
    }
}
