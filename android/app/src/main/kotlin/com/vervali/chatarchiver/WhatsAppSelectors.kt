package com.vervali.chatarchiver

/**
 * EVERY WhatsApp view id, text and content-description the automation depends on lives in this file.
 *
 * !!! UNVERIFIED !!!
 * These were written from memory of WhatsApp's UI without access to a real device. Treat every entry as a
 * GUESS until confirmed on a phone: run the app's "dumpScreen" diagnostic on each screen (chat list, search,
 * conversation, overflow menu, More submenu, export dialog, share sheet) and tune the lists below.
 * Entries marked [guess-id] are view ids that are especially likely to be wrong or version-dependent;
 * entries marked [guess-text] are label wording that varies by version/locale.
 *
 * Selector order matters: each target is an ordered list; the first selector that matches anything wins.
 * Order is always: view id, then text, then content-description.
 *
 * Fail-safe rules (enforced in ScreenReader / ScreenState / ExportRunner, not here):
 *  - nothing on [FORBIDDEN_IDS] / [FORBIDDEN_DESCS] is ever clicked (send, mic, call, attach, message box...);
 *  - "More", "Export chat" and "Without media" are only accepted in a window WITHOUT conversation markers
 *    (popup menus and dialogs are their own windows), so text inside the chat can never be tapped;
 *  - the conversation title must equal the group name before AND right before the first menu tap;
 *  - every step has a timeout that ends the group with a contract error code; nothing is guessed.
 * When a dump shows that WhatsApp draws a menu/dialog inside the chat window, the step fails with
 * menu_not_found / export_not_found: adjust the rule deliberately, do not loosen the selectors.
 *
 * Localisation: English only for the pilot. To add a language, add another [WaStrings] to [locales].
 */

/** All user-visible wording for one locale. */
data class WaStrings(
    val search: List<String>,
    val searchBarHints: List<String>,
    val moreOptions: List<String>,
    val more: List<String>,
    val exportChat: List<String>,
    val withoutMedia: List<String>,
    val chatsTab: List<String>,
    val callsTab: List<String>,
)

object WhatsAppSelectors {
    /** Consumer and Business WhatsApp. Tried in this order. */
    val PACKAGES = listOf("com.whatsapp", "com.whatsapp.w4b")

    /** Packages whose windows must never be touched while looking for the share target. */
    val NOT_SHARE_SHEET_PACKAGES = setOf("com.whatsapp", "com.whatsapp.w4b", "com.android.systemui")

    val EN = WaStrings(
        search = listOf("Search"),                                           // [guess-text]
        searchBarHints = listOf("Ask Meta AI or Search", "Search"),          // [guess-text] newer top bar
        moreOptions = listOf("More options"),                                // standard action-bar overflow desc
        more = listOf("More"),                                               // [guess-text] item in overflow menu
        exportChat = listOf("Export chat"),                                  // [guess-text]
        withoutMedia = listOf("Without media", "WITHOUT MEDIA"),             // [guess-text] dialog button
        chatsTab = listOf("Chats"),
        callsTab = listOf("Calls"),
    )

    /** Add more locales here; every selector below is built from all of them. */
    val locales: List<WaStrings> = listOf(EN)

    private fun <T> perLocale(f: (WaStrings) -> List<T>): List<T> = locales.flatMap(f)

    // ---- Chats list / screen detection ------------------------------------------------------------

    /** Rows of the chat list (and of search results). [guess-id] */
    val CHAT_ROW_TITLE_IDS = listOf("conversations_row_contact_name")

    /** Title in the conversation toolbar. [guess-id] */
    val CONVERSATION_TITLE_IDS = listOf("conversation_contact_name")

    /** Views that exist only inside an open conversation. [guess-id] */
    val CONVERSATION_MARKER_IDS = listOf("conversation_contact_name", "entry", "conversation_contact_status")

    /** Tab labels used to recognise the Chats list when no row ids match. */
    val CHATS_TAB: List<Sel> = perLocale { l -> l.chatsTab.map { Sel.Text(it) } }
    val CALLS_TAB: List<Sel> = perLocale { l -> l.callsTab.map { Sel.Text(it) } }

    /** Chat-row title nodes (also used for search result rows). */
    val CHAT_ROW_TITLE: List<Sel> = CHAT_ROW_TITLE_IDS.map { Sel.Id(it) }

    val CONVERSATION_TITLE: List<Sel> = CONVERSATION_TITLE_IDS.map { Sel.Id(it) }

    // ---- Search ----------------------------------------------------------------------------------

    /** The search text field once search is open. [guess-id] then hint. */
    val SEARCH_FIELD: List<Sel> =
        listOf(Sel.Id("search_src_text"), Sel.Id("search_input")) +
            perLocale { l -> l.searchBarHints.map { Sel.HintContains(it) } } +
            perLocale { l -> l.searchBarHints.map { Sel.TextContains(it) } }

    /** What to tap to open search: old toolbar icon, then the newer top search bar. [guess-id] */
    val SEARCH_ENTRY: List<Sel> =
        listOf(Sel.Id("menuitem_search"), Sel.Id("search_bar"), Sel.Id("my_search_bar")) +
            perLocale { l -> l.search.map { Sel.Desc(it) } } +
            perLocale { l -> l.searchBarHints.map { Sel.TextContains(it) } } +
            perLocale { l -> l.searchBarHints.map { Sel.DescContains(it) } } +
            perLocale { l -> l.searchBarHints.map { Sel.HintContains(it) } }

    // ---- Export path -----------------------------------------------------------------------------

    /** Overflow ("three dots") button in the conversation toolbar. [guess-id] */
    val OVERFLOW: List<Sel> =
        listOf(Sel.Id("menuitem_overflow")) + perLocale { l -> l.moreOptions.map { Sel.Desc(it) } }

    /** "More" entry of the overflow menu. [guess-text] */
    val MORE: List<Sel> = perLocale { l -> l.more.map { Sel.Text(it) } }

    /** "Export chat" entry of the More submenu. [guess-text] */
    val EXPORT_CHAT: List<Sel> = perLocale { l -> l.exportChat.map { Sel.Text(it) } }

    /** "Without media" button of the export dialog. [guess-text] */
    val WITHOUT_MEDIA: List<Sel> = perLocale { l -> l.withoutMedia.map { Sel.Text(it) } }

    /** Message-bubble text views: never treat their text as a menu entry (e.g. a message saying "More"). [guess-id] */
    val MESSAGE_CONTENT_IDS = setOf("message_text", "caption", "quoted_message_text", "conversation_row_text")

    // ---- Safety: things the automation must NEVER click ---------------------------------------------

    val FORBIDDEN_IDS = setOf(
        "send", "voice_note_btn", "entry", "conversation_entry_action_button", "input_attach_button",
        "camera_btn", "emoji_picker_btn", "call_btn", "menuitem_call", "menuitem_voice_call",
        "menuitem_video_call", "menuitem_conversations_new_chat", "fab", "extended_mini_fab",
    )

    val FORBIDDEN_DESCS = listOf(
        "Send", "Voice message", "Voice call", "Video call", "Attach", "Camera", "Emoji", "Call",
        "New chat", "Message",
    )

    fun isForbidden(n: UiNode): Boolean {
        if (n.idName in FORBIDDEN_IDS) return true
        val d = n.desc
        if (!d.isNullOrEmpty() && FORBIDDEN_DESCS.any { ChatNames.labelEquals(d, it) }) return true
        return false
    }
}
