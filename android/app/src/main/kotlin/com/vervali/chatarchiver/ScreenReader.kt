package com.vervali.chatarchiver

import android.accessibilityservice.AccessibilityService
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo

/** Builds [Screen] snapshots from the live accessibility windows and performs node actions. */
object ScreenReader {
    private const val TAG = "ChatArchiver"
    private const val MAX_NODES = 4000
    private const val MAX_DEPTH = 45

    /**
     * Snapshot of all interactive windows (popup menus and dialogs are separate windows) plus
     * `rootInActiveWindow`. Invisible nodes are dropped unless [includeInvisible].
     */
    fun capture(service: AccessibilityService, includeInvisible: Boolean = false): Screen {
        val roots = ArrayList<Triple<AccessibilityNodeInfo, Int, WindowSummary?>>()
        val seenWindowIds = HashSet<Int>()
        val summaries = ArrayList<WindowSummary>()
        try {
            val windows = service.windows
            if (!windows.isNullOrEmpty()) {
                windows.sortedByDescending { it.layer }.forEach { w ->
                    val root = try { w.root } catch (_: Exception) { null }
                    if (root != null && seenWindowIds.add(root.windowId)) {
                        val summary = WindowSummary(
                            index = summaries.size,
                            pkg = root.packageName?.toString(),
                            type = w.type,
                            layer = w.layer,
                            active = w.isActive,
                            focused = w.isFocused,
                            title = w.title?.toString(),
                        )
                        summaries.add(summary)
                        roots.add(Triple(root, summary.index, summary))
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "reading windows failed", e)
        }
        try {
            val active = service.rootInActiveWindow
            if (active != null && seenWindowIds.add(active.windowId)) {
                val summary = WindowSummary(summaries.size, active.packageName?.toString(), -1, -1, true, true, null)
                summaries.add(summary)
                roots.add(Triple(active, summary.index, summary))
            }
        } catch (e: Exception) {
            Log.w(TAG, "reading active window failed", e)
        }
        val out = ArrayList<UiNode>()
        for ((root, idx, _) in roots) {
            build(root, null, 0, idx, includeInvisible, out)
        }
        return Screen(out, summaries)
    }

    private fun build(
        info: AccessibilityNodeInfo,
        parent: UiNode?,
        depth: Int,
        windowIndex: Int,
        includeInvisible: Boolean,
        out: MutableList<UiNode>,
    ) {
        if (out.size >= MAX_NODES || depth > MAX_DEPTH) return
        val visible = info.isVisibleToUser
        if (!visible && !includeInvisible) return
        val r = Rect()
        info.getBoundsInScreen(r)
        val hint = if (Build.VERSION.SDK_INT >= 26) info.hintText?.toString() else null
        val node = UiNode(
            id = info.viewIdResourceName,
            text = info.text?.toString(),
            desc = info.contentDescription?.toString(),
            hint = hint,
            className = info.className?.toString(),
            pkg = info.packageName?.toString(),
            clickable = info.isClickable,
            scrollable = info.isScrollable,
            editable = info.isEditable,
            visible = visible,
            bounds = Bounds(r.left, r.top, r.right, r.bottom),
            depth = depth,
            windowIndex = windowIndex,
            info = info,
        )
        node.parent = parent
        parent?.children?.add(node)
        out.add(node)
        for (i in 0 until info.childCount) {
            val child = try { info.getChild(i) } catch (_: Exception) { null } ?: continue
            build(child, node, depth + 1, windowIndex, includeInvisible, out)
        }
    }

    // ---- actions --------------------------------------------------------------------------------

    /**
     * Click [node] (or its nearest clickable ancestor) with ACTION_CLICK. Refuses to click anything on the
     * forbidden list (send, mic, call, attach, message input...). Returns whether the action was performed.
     */
    fun click(node: UiNode, why: String): Boolean {
        val target = Finders.clickableTarget(node)
        if (WhatsAppSelectors.isForbidden(node) || WhatsAppSelectors.isForbidden(target)) {
            Log.w(TAG, "REFUSED to click forbidden node ($why): ${target.describe()}")
            return false
        }
        val ok = target.info?.performAction(AccessibilityNodeInfo.ACTION_CLICK) ?: false
        Log.d(TAG, "click($why) -> $ok on ${target.describe()}")
        return ok
    }

    fun setText(node: UiNode, text: String): Boolean {
        val info = node.info ?: return false
        info.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
        val args = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        val ok = info.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        Log.d(TAG, "setText -> $ok on ${node.describe()}")
        return ok
    }

    fun scrollForward(node: UiNode): Boolean {
        val ok = node.info?.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD) ?: false
        Log.d(TAG, "scrollForward -> $ok on ${node.describe()}")
        return ok
    }

    @Suppress("unused")
    private fun windowTypeName(t: Int) = when (t) {
        AccessibilityWindowInfo.TYPE_APPLICATION -> "application"
        AccessibilityWindowInfo.TYPE_INPUT_METHOD -> "ime"
        AccessibilityWindowInfo.TYPE_SYSTEM -> "system"
        AccessibilityWindowInfo.TYPE_ACCESSIBILITY_OVERLAY -> "a11y-overlay"
        else -> t.toString()
    }
}
