package com.vervali.chatarchiver

/** Screen-space rectangle (own type so pure logic runs in JVM unit tests). */
data class Bounds(val left: Int, val top: Int, val right: Int, val bottom: Int) {
    val width: Int get() = right - left
    val height: Int get() = bottom - top
    val centerY: Int get() = (top + bottom) / 2
    override fun toString() = "[$left,$top][$right,$bottom]"
}

/**
 * Immutable-ish snapshot of one accessibility node. [info] is the live node used for actions
 * (null in unit tests).
 */
class UiNode(
    val id: String?,
    val text: String?,
    val desc: String?,
    val hint: String?,
    val className: String?,
    val pkg: String?,
    val clickable: Boolean,
    val scrollable: Boolean,
    val editable: Boolean,
    val visible: Boolean,
    val bounds: Bounds,
    val depth: Int,
    val windowIndex: Int,
    val info: android.view.accessibility.AccessibilityNodeInfo? = null,
) {
    var parent: UiNode? = null
    val children: MutableList<UiNode> = mutableListOf()

    /** `com.whatsapp:id/foo` -> `foo` (package-independent so WhatsApp Business works the same). */
    val idName: String? get() = id?.substringAfter(":id/", id)

    fun describe(): String = buildString {
        append(className?.substringAfterLast('.') ?: "?")
        if (id != null) append(" id=").append(id)
        if (!text.isNullOrEmpty()) append(" text=\"").append(text.replace("\n", "\\n")).append('"')
        if (!desc.isNullOrEmpty()) append(" desc=\"").append(desc.replace("\n", "\\n")).append('"')
        if (!hint.isNullOrEmpty()) append(" hint=\"").append(hint).append('"')
        if (clickable) append(" clickable")
        if (scrollable) append(" scrollable")
        if (editable) append(" editable")
        if (!visible) append(" INVISIBLE")
        append(' ').append(bounds)
    }
}

/** One window of the screen as seen by the service. */
data class WindowSummary(
    val index: Int,
    val pkg: String?,
    val type: Int,
    val layer: Int,
    val active: Boolean,
    val focused: Boolean,
    val title: String?,
)

class Screen(val nodes: List<UiNode>, val windows: List<WindowSummary>) {
    fun inPackages(pkgs: Collection<String>): List<UiNode> = nodes.filter { it.pkg in pkgs }
    fun hasPackage(pkgs: Collection<String>): Boolean = nodes.any { it.pkg in pkgs }

    companion object {
        val EMPTY = Screen(emptyList(), emptyList())
    }
}

/** One selector alternative. A target is an ORDERED list of these (view id first, then text, then desc). */
sealed class Sel {
    abstract fun matches(n: UiNode): Boolean

    /** View id short name (`menuitem_search` for `com.whatsapp:id/menuitem_search`). */
    data class Id(val name: String) : Sel() {
        override fun matches(n: UiNode) = n.idName == name
    }

    data class Text(val value: String) : Sel() {
        override fun matches(n: UiNode) = ChatNames.labelEquals(n.text, value)
    }

    data class TextContains(val value: String) : Sel() {
        override fun matches(n: UiNode) = ChatNames.labelContains(n.text, value)
    }

    data class Desc(val value: String) : Sel() {
        override fun matches(n: UiNode) = ChatNames.labelEquals(n.desc, value)
    }

    data class DescContains(val value: String) : Sel() {
        override fun matches(n: UiNode) = ChatNames.labelContains(n.desc, value)
    }

    data class HintContains(val value: String) : Sel() {
        override fun matches(n: UiNode) = ChatNames.labelContains(n.hint, value)
    }
}

object Finders {
    /**
     * Applies selectors in order and returns the matches of the first selector that has any.
     * Matches are de-duplicated by (id, bounds) so the same view seen via two windows counts once.
     */
    fun find(nodes: List<UiNode>, sels: List<Sel>, filter: (UiNode) -> Boolean = { true }): List<UiNode> {
        for (s in sels) {
            val hits = nodes.filter { filter(it) && s.matches(it) }
            if (hits.isNotEmpty()) return dedupe(hits)
        }
        return emptyList()
    }

    fun dedupe(hits: List<UiNode>): List<UiNode> {
        val seen = HashSet<String>()
        return hits.filter { seen.add("${it.id}|${it.bounds}|${it.text}") }
    }

    /**
     * Nearest clickable node: the node itself, an ancestor (up to [maxUp] levels), or — if still
     * not clickable — the first clickable descendant. WhatsApp's Meta AI search wraps the real
     * tap target (`search_bar_inner_layout`) inside a non-clickable `my_search_bar` frame.
     */
    fun clickableTarget(n: UiNode, maxUp: Int = 6): UiNode {
        var cur: UiNode? = n
        var i = 0
        while (cur != null && i <= maxUp) {
            if (cur.clickable) return cur
            cur = cur.parent
            i++
        }
        return clickableDescendant(n) ?: n
    }

    private fun clickableDescendant(n: UiNode): UiNode? {
        for (child in n.children) {
            if (child.clickable) return child
            clickableDescendant(child)?.let { return it }
        }
        return null
    }
}
