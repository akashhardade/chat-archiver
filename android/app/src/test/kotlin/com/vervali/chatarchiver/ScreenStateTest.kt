package com.vervali.chatarchiver

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScreenStateTest {
    private fun n(
        id: String? = null, text: String? = null, desc: String? = null, hint: String? = null,
        clickable: Boolean = false, editable: Boolean = false,
        top: Int = 0, bottom: Int = top + 50, pkg: String = "com.whatsapp", window: Int = 0,
    ) = UiNode(
        id = id?.let { "$pkg:id/$it" }, text = text, desc = desc, hint = hint, className = "android.widget.TextView",
        pkg = pkg, clickable = clickable, scrollable = false, editable = editable, visible = true,
        bounds = Bounds(0, top, 1000, bottom), depth = 0, windowIndex = window,
    )

    private val screenBottom = n(top = 2300, bottom = 2400) // gives the screen height

    @Test fun chatsListDetectedByRowIds() {
        val wa = listOf(screenBottom, n("conversations_row_contact_name", "Alpha", top = 300))
        assertTrue(ScreenState.isChatsList(wa))
    }

    @Test fun chatsListDetectedByTabs() {
        val wa = listOf(screenBottom, n(text = "Chats", top = 2200), n(text = "Calls", top = 2200))
        assertTrue(ScreenState.isChatsList(wa))
    }

    @Test fun conversationIsNotChatsList() {
        val wa = listOf(
            screenBottom, n("conversations_row_contact_name", "Alpha", top = 300),
            n("conversation_contact_name", "Alpha", top = 50),
        )
        assertFalse(ScreenState.isChatsList(wa))
    }

    @Test fun openSearchFieldIsNotChatsList() {
        val wa = listOf(screenBottom, n("search_src_text", "", editable = true), n("conversations_row_contact_name", "Alpha", top = 300))
        assertFalse(ScreenState.isChatsList(wa))
    }

    @Test fun searchFieldFoundByHint() {
        val wa = listOf(n(hint = "Ask Meta AI or Search", editable = true))
        assertTrue(ScreenState.searchField(wa) != null)
    }

    @Test fun exactResultRowsNormalisesAndRejectsPartials() {
        val wa = listOf(
            n("search_src_text", "Alpha", editable = true, top = 0),
            n("conversations_row_contact_name", "‎Alpha ", top = 300),
            n("conversations_row_contact_name", "Alpha Team", top = 400),
            n("conversations_row_contact_name", "alpha", top = 500),
        )
        val rows = ScreenState.exactResultRows(wa, "Alpha")
        assertEquals(1, rows.size)
        assertEquals(300, rows[0].bounds.top)
    }

    @Test fun twoExactRowsAreBothReported() {
        val wa = listOf(
            n("conversations_row_contact_name", "Alpha", top = 300),
            n("conversations_row_contact_name", "Alpha", top = 600),
        )
        assertEquals(2, ScreenState.exactResultRows(wa, "Alpha").size)
    }

    @Test fun sameViewSeenTwiceCountsOnce() {
        val a = n("conversations_row_contact_name", "Alpha", top = 300)
        val b = n("conversations_row_contact_name", "Alpha", top = 300)
        assertEquals(1, ScreenState.exactResultRows(listOf(a, b), "Alpha").size)
    }

    @Test fun noRowsWhenNameAbsent() {
        val wa = listOf(n("conversations_row_contact_name", "Beta", top = 300))
        assertTrue(ScreenState.exactResultRows(wa, "Alpha").isEmpty())
    }

    @Test fun conversationTitleById() {
        val wa = listOf(screenBottom, n("conversation_contact_name", "Alpha", top = 60))
        val t = ScreenState.conversationTitle(wa, "Alpha")
        assertTrue(t is ScreenState.Title.Found)
        assertEquals("Alpha", (t as ScreenState.Title.Found).text)
        val wrong = ScreenState.conversationTitle(listOf(screenBottom, n("conversation_contact_name", "Beta", top = 60)), "Alpha")
        assertEquals("Beta", (wrong as ScreenState.Title.Found).text)
    }

    @Test fun conversationTitleFallbackNeedsConversationAndTopArea() {
        val inChat = listOf(screenBottom, n("entry", "", editable = true, top = 2200), n(text = "Alpha", top = 60))
        assertTrue(ScreenState.conversationTitle(inChat, "Alpha") is ScreenState.Title.Found)
        val listOnly = listOf(screenBottom, n(text = "Alpha", top = 60))
        assertTrue(ScreenState.conversationTitle(listOnly, "Alpha") is ScreenState.Title.NotInChat)
        val low = listOf(screenBottom, n("entry", "", editable = true, top = 2200), n(text = "Alpha", top = 1200))
        assertTrue(ScreenState.conversationTitle(low, "Alpha") is ScreenState.Title.NotInChat)
    }

    @Test fun selectorsAreOrderedIdThenTextThenDesc() {
        val byDesc = n(desc = "More options", top = 40)
        val byId = n("menuitem_overflow", top = 80)
        // id selector wins even though the desc node also matches and comes first.
        val hit = Finders.find(listOf(byDesc, byId), WhatsAppSelectors.OVERFLOW)
        assertEquals(listOf(byId), hit)
        assertEquals(listOf(byDesc), Finders.find(listOf(byDesc), WhatsAppSelectors.OVERFLOW))
    }

    @Test fun clickableTargetClimbsToClickableAncestor() {
        val parent = n(clickable = true, top = 10)
        val child = n(text = "Export chat", top = 12)
        child.parent = parent
        assertTrue(Finders.clickableTarget(child) === parent)
    }

    @Test fun forbiddenNodes() {
        assertTrue(WhatsAppSelectors.isForbidden(n("send", desc = "Send")))
        assertTrue(WhatsAppSelectors.isForbidden(n(desc = "Voice call")))
        assertTrue(WhatsAppSelectors.isForbidden(n("entry")))
        assertFalse(WhatsAppSelectors.isForbidden(n(desc = "More options")))
        assertFalse(WhatsAppSelectors.isForbidden(n(text = "Export chat")))
    }

    @Test fun menuItemsNeverComeFromTheConversationWindow() {
        // Window 1 = the open chat (toolbar title + message box) with a message that reads "Export chat".
        val chatTitle = n("conversation_contact_name", "Alpha", top = 50, window = 1)
        val entry = n("entry", "", editable = true, top = 2200, window = 1)
        val bubbleNoId = n(text = "Export chat", top = 900, window = 1)
        val bubbleById = n("message_text", "More", top = 1000, window = 1)
        val chat = listOf(chatTitle, entry, bubbleNoId, bubbleById)
        assertTrue(ScreenState.menuItems(chat, WhatsAppSelectors.EXPORT_CHAT).isEmpty())
        assertTrue(ScreenState.menuItems(chat, WhatsAppSelectors.MORE).isEmpty())

        // Window 0 = the popup menu on top of the chat.
        val menuItem = n(text = "Export chat", top = 300, window = 0)
        val more = n(text = "More", top = 600, window = 0)
        val withMenu = chat + listOf(menuItem, more)
        assertEquals(listOf(menuItem), ScreenState.menuItems(withMenu, WhatsAppSelectors.EXPORT_CHAT))
        assertEquals(listOf(more), ScreenState.menuItems(withMenu, WhatsAppSelectors.MORE))
    }

    @Test fun withoutMediaButtonInDialogWindowIsAccepted() {
        val chat = listOf(n("conversation_contact_name", "Alpha", top = 50, window = 1))
        val button = n(text = "WITHOUT MEDIA", clickable = true, top = 1400, window = 0)
        assertEquals(listOf(button), ScreenState.menuItems(chat + button, WhatsAppSelectors.WITHOUT_MEDIA))
    }
}
