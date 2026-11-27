package com.vervali.chatarchiver

/** Pure screen-classification logic over WhatsApp's nodes (unit-testable). */
object ScreenState {

    sealed class Title {
        /** Not looking at a conversation (or cannot tell). */
        object NotInChat : Title()
        data class Found(val text: String) : Title()
    }

    private fun screenHeight(wa: List<UiNode>): Int = wa.maxOfOrNull { it.bounds.bottom } ?: 0

    fun isConversation(wa: List<UiNode>): Boolean =
        wa.any { it.idName in WhatsAppSelectors.CONVERSATION_MARKER_IDS }

    fun searchField(wa: List<UiNode>): UiNode? =
        Finders.find(wa, WhatsAppSelectors.SEARCH_FIELD) { it.editable }.firstOrNull()

    /**
     * True when the main Chats list is showing (and not a conversation or an open search field).
     * Heuristic: chat rows exist, or both the "Chats" and "Calls" tab labels are visible.
     */
    fun isChatsList(wa: List<UiNode>): Boolean {
        if (wa.isEmpty()) return false
        if (isConversation(wa)) return false
        if (searchField(wa) != null) return false
        val rows = Finders.find(wa, WhatsAppSelectors.CHAT_ROW_TITLE).isNotEmpty()
        val tabs = Finders.find(wa, WhatsAppSelectors.CHATS_TAB).isNotEmpty() &&
            Finders.find(wa, WhatsAppSelectors.CALLS_TAB).isNotEmpty()
        return rows || tabs
    }

    /**
     * Title of the open conversation. Primary: the toolbar title view id. Fallback (only when no id matched):
     * a non-editable node in the top ~18% of the screen whose text equals [expected] exactly.
     */
    fun conversationTitle(wa: List<UiNode>, expected: String): Title {
        val byId = Finders.find(wa, WhatsAppSelectors.CONVERSATION_TITLE)
            .filter { !it.text.isNullOrBlank() }
        if (byId.isNotEmpty()) {
            // Prefer the topmost one (the toolbar).
            return Title.Found(byId.minByOrNull { it.bounds.top }!!.text!!)
        }
        val h = screenHeight(wa)
        if (h > 0 && isConversation(wa)) {
            val top = wa.filter {
                !it.editable && it.bounds.bottom <= h * 0.18 && ChatNames.matches(it.text, expected)
            }
            if (top.isNotEmpty()) return Title.Found(top.first().text!!)
        }
        return Title.NotInChat
    }

    /**
     * Candidates for an overflow-menu / submenu / dialog entry ("More", "Export chat", "Without media").
     * Popup menus and dialogs are separate windows, so a match is only accepted if it is NOT in a window that
     * shows the conversation itself (a window holding a conversation marker such as the toolbar title or the
     * message box). This way a message, link preview or caption that happens to read "More" or "Export chat"
     * can never be tapped; if WhatsApp ever renders its menu inside the chat window the step times out
     * (`menu_not_found` / `export_not_found`) instead of tapping something wrong.
     */
    fun menuItems(wa: List<UiNode>, sels: List<Sel>): List<UiNode> {
        val chatWindows = wa.filter { it.idName in WhatsAppSelectors.CONVERSATION_MARKER_IDS }
            .map { it.windowIndex }
            .toSet()
        return Finders.find(wa, sels) {
            !it.editable &&
                it.idName !in WhatsAppSelectors.MESSAGE_CONTENT_IDS &&
                it.windowIndex !in chatWindows
        }
    }

    /** Exact-title rows (after normalisation) among chat-row title nodes. */
    fun exactResultRows(wa: List<UiNode>, groupName: String): List<UiNode> {
        val rows = Finders.find(wa, WhatsAppSelectors.CHAT_ROW_TITLE) { !it.editable }
            .filter { ChatNames.matches(it.text, groupName) }
        if (rows.isNotEmpty()) return rows
        // Fallback when row ids do not match: any non-editable, non-toolbar node with exactly that text,
        // below the search field (avoid the search box itself and the conversation toolbar).
        val field = searchField(wa)
        val minTop = field?.bounds?.bottom ?: 0
        return Finders.dedupe(
            wa.filter {
                !it.editable && it.bounds.top >= minTop && !isConversation(wa) &&
                    ChatNames.matches(it.text, groupName)
            },
        )
    }
}
