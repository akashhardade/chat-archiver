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

    /**
     * Exact-title chat rows to open after search.
     *
     * WhatsApp's Meta AI search UI often shows the same title under **Chats** and again under
     * **Messages** (and may duplicate a11y nodes). We keep only Chats-section / contact-row hits,
     * spatially de-dupe near-identical nodes, and return distinct Y-ordered candidates.
     */
    fun exactResultRows(wa: List<UiNode>, groupName: String): List<UiNode> {
        val field = searchField(wa)
        val minTop = field?.bounds?.bottom ?: 0

        val byId = Finders.find(wa, WhatsAppSelectors.CHAT_ROW_TITLE) {
            !it.editable && it.bounds.top >= minTop && ChatNames.matches(it.text, groupName)
        }
        val raw = if (byId.isNotEmpty()) {
            byId
        } else {
            Finders.dedupe(
                wa.filter {
                    !it.editable &&
                        it.bounds.top >= minTop &&
                        !isConversation(wa) &&
                        ChatNames.matches(it.text, groupName) &&
                        !looksLikeMetaAi(it)
                },
            )
        }

        val inChatsSection = filterToChatsSearchSection(wa, raw)
        val preferred = preferContactRows(inChatsSection.ifEmpty { raw })
            .filter { !looksLikeMetaAi(it) }
        return spatialDedupe(preferred)
    }

    /** True when this node (or an ancestor) is the Meta AI suggestion row, not a chat. */
    private fun looksLikeMetaAi(n: UiNode): Boolean {
        var cur: UiNode? = n
        var hops = 0
        while (cur != null && hops < 8) {
            val id = cur.idName.orEmpty().lowercase()
            if (id.contains("meta_ai") || id.contains("ai_bot") || id.contains("bot_search")) return true
            val blob = listOfNotNull(cur.text, cur.desc, cur.hint).joinToString(" ")
            if (ChatNames.labelContains(blob, "Meta AI") || ChatNames.labelEquals(blob, "Ask Meta AI")) {
                return true
            }
            cur = cur.parent
            hops++
        }
        return false
    }

    /**
     * If search shows section headers (Chats / Messages / …), keep only nodes whose top is at or
     * below the Chats header and above the next skip-section header.
     */
    private fun filterToChatsSearchSection(wa: List<UiNode>, rows: List<UiNode>): List<UiNode> {
        if (rows.isEmpty()) return rows
        // Ignore the bottom-nav "Chats" tab (lower half); only the search-result section header counts.
        val screenH = screenHeight(wa)
        val maxHeaderTop = if (screenH > 0) (screenH * 0.55).toInt() else Int.MAX_VALUE
        val chatsHeader = wa.filter {
            !it.editable &&
                it.bounds.top <= maxHeaderTop &&
                WhatsAppSelectors.SEARCH_SECTION_CHATS.any { label ->
                    ChatNames.labelEquals(it.text, label)
                }
        }.minByOrNull { it.bounds.top } ?: return rows

        val chatsTop = chatsHeader.bounds.top
        val nextSectionTop = wa.filter { n ->
            !n.editable &&
                n.bounds.top > chatsTop + 8 &&
                n.bounds.top <= maxHeaderTop &&
                WhatsAppSelectors.SEARCH_SECTION_SKIP.any { label ->
                    ChatNames.labelEquals(n.text, label)
                }
        }.minOfOrNull { it.bounds.top } ?: Int.MAX_VALUE

        val sectioned = rows.filter { it.bounds.top >= chatsTop && it.bounds.top < nextSectionTop }
        return sectioned.ifEmpty { rows }
    }

    /** Prefer titles that sit inside a known chat-row container when those exist. */
    private fun preferContactRows(rows: List<UiNode>): List<UiNode> {
        if (rows.isEmpty()) return rows
        fun underContactRow(n: UiNode): Boolean {
            var cur: UiNode? = n
            var hops = 0
            while (cur != null && hops < 8) {
                if (cur.idName in WhatsAppSelectors.CHAT_ROW_CONTAINER_IDS) return true
                cur = cur.parent
                hops++
            }
            return false
        }
        val nested = rows.filter(::underContactRow)
        return nested.ifEmpty { rows }
    }

    /** Merge title nodes that are clearly the same on-screen row (overlapping / near-identical Y). */
    private fun spatialDedupe(rows: List<UiNode>): List<UiNode> {
        if (rows.size <= 1) return rows
        val ordered = rows.sortedBy { it.bounds.top }
        val out = mutableListOf<UiNode>()
        for (n in ordered) {
            val prev = out.lastOrNull()
            if (prev != null) {
                val sameBand = kotlin.math.abs(prev.bounds.centerY - n.bounds.centerY) <= 48
                val overlap = prev.bounds.top < n.bounds.bottom && n.bounds.top < prev.bounds.bottom
                if (sameBand || overlap) continue
            }
            out.add(n)
        }
        return out
    }
}
