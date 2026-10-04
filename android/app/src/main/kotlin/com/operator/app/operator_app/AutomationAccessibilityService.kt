package com.operator.app.operator_app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import android.os.Handler
import android.os.Looper
import kotlinx.coroutines.*

object AutomationAccessibilityServiceHolder {
    var instance: AutomationAccessibilityService? = null
}

class AutomationAccessibilityService : AccessibilityService() {

    private var isRecording = false
    private var recordedPackage: String? = null
    private val recordedSteps = mutableListOf<Map<String, Any?>>()
    private val serviceScope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (!isRecording || event == null) return
        // Capture package for target inference (ignore our own app)
        val pkg = event.packageName?.toString()
        if (!pkg.isNullOrBlank() && pkg != packageName && pkg != "com.android.systemui") {
            if (recordedPackage == null) recordedPackage = pkg
        }
        // Only record click events while recording
        if (event.eventType == AccessibilityEvent.TYPE_VIEW_CLICKED) {
            val source = event.source ?: return
            try {
                val rect = Rect()
                source.getBoundsInScreen(rect)
                val className = source.className?.toString() ?: ""
                val text = source.text?.toString()
                val contentDesc = source.contentDescription?.toString()
                val viewId = source.viewIdResourceName

                val displayMetrics = resources.displayMetrics
                val screenW = displayMetrics.widthPixels.toFloat()
                val screenH = displayMetrics.heightPixels.toFloat()
                val centerX = (rect.left + rect.right) / 2f
                val centerY = (rect.top + rect.bottom) / 2f
                val xPct = if (screenW > 0) (centerX / screenW).toDouble() else 0.5
                val yPct = if (screenH > 0) (centerY / screenH).toDouble() else 0.5

                val step = mutableMapOf<String, Any?>(
                    "type" to "findAndTap",
                    "xPct" to xPct.coerceIn(0.0, 1.0),
                    "yPct" to yPct.coerceIn(0.0, 1.0),
                    "selectorValue" to (viewId ?: text ?: contentDesc),
                    "contains" to false,
                    "packageName" to pkg,
                )
                // Prefer viewId if available and not blank
                if (!viewId.isNullOrBlank()) {
                    step["selectorType"] = "id"
                    step["selectorValue"] = viewId
                } else if (!text.isNullOrBlank()) {
                    step["selectorType"] = "text"
                    step["selectorValue"] = text
                } else if (!contentDesc.isNullOrBlank()) {
                    step["selectorType"] = "desc"
                    step["selectorValue"] = contentDesc
                } else {
                    step["selectorType"] = "tap"
                    step["selectorValue"] = null
                }
                recordedSteps.add(step)
            } catch (_: Exception) {
            } finally {
                try { source.recycle() } catch (_: Exception) {}
            }
        }
    }

    override fun onInterrupt() {}

    override fun onServiceConnected() {
        super.onServiceConnected()
        AutomationAccessibilityServiceHolder.instance = this
        try {
            val info = serviceInfo ?: android.accessibilityservice.AccessibilityServiceInfo()
            info.eventTypes = AccessibilityEvent.TYPES_ALL_MASK
            info.feedbackType = android.accessibilityservice.AccessibilityServiceInfo.FEEDBACK_GENERIC
            info.flags = info.flags or
                android.accessibilityservice.AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                android.accessibilityservice.AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS or
                android.accessibilityservice.AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
            serviceInfo = info
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        if (AutomationAccessibilityServiceHolder.instance === this) {
            AutomationAccessibilityServiceHolder.instance = null
        }
        serviceScope.cancel()
        super.onDestroy()
    }

    fun isEnabled(): Boolean = true

    private fun isFridayWindow(win: AccessibilityWindowInfo, activeWinId: Int): Boolean {
        if (activeWinId != -1 && win.id == activeWinId) {
            return true
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val title = win.title?.toString() ?: ""
            if (title.contains("FRIDAY", ignoreCase = true) || title.contains("Operator", ignoreCase = true)) {
                return true
            }
        }

        val r = win.root ?: return false
        val p = r.packageName?.toString() ?: ""

        if (p.contains("operator", ignoreCase = true) ||
            p.contains("friday", ignoreCase = true) ||
            p.equals(packageName, ignoreCase = true)
        ) {
            return true
        }

        try {
            val text = r.text?.toString() ?: ""
            val desc = r.contentDescription?.toString() ?: ""
            val selfString = "$text $desc".lowercase()
            if (selfString.contains("speak your command") ||
                selfString.contains("listening") ||
                selfString.contains("thinking") ||
                selfString.contains("mini_globe") ||
                selfString.contains("friday")
            ) {
                return true
            }

            val count = r.childCount.coerceAtMost(15)
            for (i in 0 until count) {
                val child = r.getChild(i) ?: continue
                val cp = child.packageName?.toString() ?: ""
                if (cp.contains("operator", ignoreCase = true) || cp.contains("friday", ignoreCase = true)) {
                    return true
                }
                val ct = child.text?.toString() ?: ""
                val cd = child.contentDescription?.toString() ?: ""
                val childStr = "$ct $cd".lowercase()
                if (childStr.contains("speak your command") ||
                    childStr.contains("mini_globe") ||
                    childStr.contains("tap to speak") ||
                    childStr.contains("listening")
                ) {
                    return true
                }
            }
        } catch (_: Exception) {}

        return false
    }

    /**
     * Friday Eyes skeleton (Part 1): small, useful summary of the active
     * window's accessibility tree. Call only after the user enables the
     * service. All nodes handled safely (null root, missing text, recycle).
     * No MediaProjection here. Note: accessibility trees may miss some
     * pixels/views (WebView, canvas, custom drawing).
     */
    fun getEyesSummary(maxNodes: Int = 40): String {
        val safeMax = maxNodes.coerceIn(1, 100)
        var targetRoot: AccessibilityNodeInfo? = null
        val myPkg = try { packageName } catch (_: Exception) { "com.operator.app.operator_app" }

        try {
            val info = serviceInfo
            if (info != null && (info.flags and android.accessibilityservice.AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS) == 0) {
                info.flags = info.flags or
                    android.accessibilityservice.AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                    android.accessibilityservice.AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS or
                    android.accessibilityservice.AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
                serviceInfo = info
            }
        } catch (_: Exception) {}

        val activeWinId = try { rootInActiveWindow?.windowId ?: -1 } catch (_: Exception) { -1 }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                val winList = windows
                if (!winList.isNullOrEmpty()) {
                    // 1. Try to find the top active non-Friday application window first
                    for (win in winList) {
                        if (isFridayWindow(win, activeWinId)) continue
                        if (win.type != AccessibilityWindowInfo.TYPE_APPLICATION) continue

                        val r = win.root ?: continue
                        val p = r.packageName?.toString() ?: ""
                        if (p.equals("android", ignoreCase = true) || p.contains("systemui", ignoreCase = true)) {
                            continue
                        }
                        targetRoot = r
                        break
                    }
                    // 2. Fallback: search for any non-Friday, non-SystemUI, non-android window
                    if (targetRoot == null) {
                        for (win in winList) {
                            if (isFridayWindow(win, activeWinId)) continue
                            if (win.type == AccessibilityWindowInfo.TYPE_SYSTEM ||
                                win.type == AccessibilityWindowInfo.TYPE_INPUT_METHOD
                            ) continue

                            val r = win.root ?: continue
                            val p = r.packageName?.toString() ?: ""
                            if (p.isNotBlank() &&
                                !p.equals("android", ignoreCase = true) &&
                                !p.contains("systemui", ignoreCase = true)
                            ) {
                                targetRoot = r
                                break
                            }
                        }
                    }
                    // 3. Fallback: any non-Friday window at all
                    if (targetRoot == null) {
                        for (win in winList) {
                            if (isFridayWindow(win, activeWinId)) continue
                            val r = win.root ?: continue
                            targetRoot = r
                            break
                        }
                    }
                }
            }
        } catch (_: Exception) {}

        if (targetRoot == null) {
            try {
                val rawRoot = rootInActiveWindow
                if (rawRoot != null) {
                    val p = rawRoot.packageName?.toString() ?: ""
                    if (p.isNotBlank() &&
                        !p.equals(myPkg, ignoreCase = true) &&
                        !p.contains("operator", ignoreCase = true) &&
                        !p.contains("friday", ignoreCase = true)
                    ) {
                        targetRoot = rawRoot
                    }
                }
            } catch (_: Exception) {}
        }

        val root = targetRoot ?: return "EYES_EMPTY: no active background window (enable service / open an app)"
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        try {
            var pkg = try {
                root.packageName?.toString() ?: ""
            } catch (_: Exception) { "" }

            if (pkg.isBlank() || pkg.equals("android", ignoreCase = true)) {
                try {
                    val count = root.childCount.coerceAtMost(10)
                    for (i in 0 until count) {
                        val cp = root.getChild(i)?.packageName?.toString() ?: ""
                        if (cp.isNotBlank() && !cp.equals("android", ignoreCase = true)) {
                            pkg = cp
                            break
                        }
                    }
                } catch (_: Exception) {}
            }
            if (pkg.isBlank()) pkg = "unknown"

            val lines = mutableListOf<String>()
            var visited = 0
            while (queue.isNotEmpty() && lines.size < safeMax && visited < 800) {
                visited++
                val node = try {
                    queue.removeFirst()
                } catch (_: Exception) {
                    break
                }
                try {
                    val text = try {
                        node.text?.toString()?.trim() ?: ""
                    } catch (_: Exception) {
                        ""
                    }
                    val desc = try {
                        node.contentDescription?.toString()?.trim() ?: ""
                    } catch (_: Exception) {
                        ""
                    }
                    val cls = try {
                        node.className?.toString()?.substringAfterLast('.') ?: ""
                    } catch (_: Exception) {
                        ""
                    }
                    val clickable = try {
                        node.isClickable
                    } catch (_: Exception) {
                        false
                    }
                    val editable = try {
                        node.isEditable
                    } catch (_: Exception) {
                        false
                    }
                    val label = when {
                        text.isNotBlank() -> text.take(60)
                        desc.isNotBlank() -> desc.take(60)
                        else -> ""
                    }

                    // Exclude any stray Friday assist UI labels
                    val lowerLabel = label.lowercase()
                    if (lowerLabel == "friday" ||
                        lowerLabel.startsWith("listening") ||
                        lowerLabel.startsWith("thinking") ||
                        lowerLabel.contains("speak your command") ||
                        lowerLabel.contains("tap to speak")
                    ) {
                        continue
                    }
                    if (label.isNotBlank() || clickable || editable) {
                        val tags = mutableListOf<String>()
                        if (clickable) tags.add("tap")
                        if (editable) tags.add("edit")
                        // Fractions (not pixels) so the agent loop can tap
                        // without knowing this device's screen size.
                        var boundsStr = ""
                        try {
                            val r = Rect()
                            node.getBoundsInScreen(r)
                            if (!r.isEmpty) {
                                val dm = resources.displayMetrics
                                val fx = (r.left + r.right) / 2f / dm.widthPixels
                                val fy = (r.top + r.bottom) / 2f / dm.heightPixels
                                boundsStr = " @[%.3f,%.3f]".format(fx, fy)
                            }
                        } catch (_: Exception) {}
                        val tagStr = if (tags.isNotEmpty()) " [${tags.joinToString(",")}]" else ""
                        lines.add("- [$cls] \"$label\"$tagStr$boundsStr")
                    }
                } catch (_: Exception) {
                }
                try {
                    val count = try {
                        node.childCount
                    } catch (_: Exception) {
                        0
                    }
                    for (i in 0 until count) {
                        try {
                            node.getChild(i)?.let { queue.add(it) }
                        } catch (_: Exception) {}
                    }
                } catch (_: Exception) {}
                try {
                    if (node !== root) node.recycle()
                } catch (_: Exception) {}
            }
            // Recycle any nodes left queued by the cap so we don't leak.
            while (queue.isNotEmpty()) {
                try {
                    val n = queue.removeFirst()
                    if (n !== root) n.recycle()
                } catch (_: Exception) {
                    break
                }
            }
            if (lines.isEmpty()) return "EYES_EMPTY: package=$pkg (no readable text/buttons)"
            return "EYES pkg=$pkg nodes=${lines.size}\n" + lines.joinToString("\n")
        } catch (e: Exception) {
            return "EYES_ERROR: ${e.localizedMessage ?: "unavailable"}"
        } finally {
            try {
                root.recycle()
            } catch (_: Exception) {}
        }
    }

    // ─── Friday Hands skeleton (Part 3): armed-only manual test actions ───
    // The service takes NO Hands actions until the user explicitly arms the
    // manual test from the test screen. No silent capture, no automatic
    // background actions. Banking/payment apps are refused (blocklist below
    // is best-effort and incomplete).
    @Volatile
    var manualTestArmed: Boolean = false

    fun armManualTest(): Boolean {
        manualTestArmed = true
        return true
    }

    fun disarmManualTest(): Boolean {
        manualTestArmed = false
        return true
    }

    private fun activePackageName(): String? {
        val root = try {
            rootInActiveWindow
        } catch (_: Exception) {
            null
        } ?: return null
        try {
            return try {
                root.packageName?.toString()
            } catch (_: Exception) {
                null
            }
        } finally {
            try {
                root.recycle()
            } catch (_: Exception) {}
        }
    }

    private fun isBankingPackage(pkg: String?): Boolean {
        if (pkg.isNullOrBlank()) return false
        val p = pkg.lowercase()
        // Best-effort, incomplete: substring match on package name.
        val keys = listOf(
            "bank", "pay", "upi", "phonepe", "paytm", "gpay", "tez",
            "bhim", "icici", "hdfc", "sbi", "axis", "kotak", "pnb",
            "bob", "wallet", "finance"
        )
        return keys.any { p.contains(it) }
    }

    private fun handsGuard(): Map<String, Any?>? {
        if (!manualTestArmed) {
            return mapOf(
                "success" to false,
                "status" to "DISARMED",
                "errorMessage" to "Manual test is not armed. Tap Arm first."
            )
        }
        if (!isAccessibilityEnabled(this)) {
            return mapOf(
                "success" to false,
                "status" to "ACCESSIBILITY_DISABLED",
                "errorMessage" to "Accessibility service is disabled."
            )
        }
        val pkg = activePackageName()
        if (isBankingPackage(pkg)) {
            return mapOf(
                "success" to false,
                "status" to "BANKING_BLOCKED",
                "errorMessage" to "Refused: banking/payment app ($pkg)."
            )
        }
        return null
    }

    /** Manual-test tap via dispatchGesture. Armed-only. */
    suspend fun manualTap(xPct: Double, yPct: Double): Map<String, Any?> {
        handsGuard()?.let { return it }
        val ok = try {
            performTap(xPct, yPct)
        } catch (e: Exception) {
            return mapOf(
                "success" to false,
                "status" to "GESTURE_FAILED",
                "errorMessage" to (e.localizedMessage ?: "Tap dispatch failed")
            )
        }
        return if (ok) {
            mapOf("success" to true, "status" to "SUCCESS")
        } else {
            mapOf(
                "success" to false,
                "status" to "GESTURE_FAILED",
                "errorMessage" to "System rejected the gesture"
            )
        }
    }

    /**
     * Manual-test text entry via ACTION_SET_TEXT. Armed-only.
     * Tries the focused input node first, then falls back to the first
     * editable node in the active window (the test screen has exactly one).
     */
    suspend fun manualEnterText(text: String): Map<String, Any?> {
        handsGuard()?.let { return it }
        if (text.isBlank()) {
            return mapOf(
                "success" to false,
                "status" to "INVALID_REQUEST",
                "errorMessage" to "Text is blank"
            )
        }
        // 1. Focused input node.
        try {
            val focused = try {
                findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            } catch (_: Exception) {
                null
            }
            if (focused != null) {
                try {
                    val args = android.os.Bundle().apply {
                        putCharSequence(
                            AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                            text
                        )
                    }
                    val ok = try {
                        focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
                    } catch (_: Exception) {
                        false
                    }
                    if (ok) return mapOf("success" to true, "status" to "SUCCESS")
                } finally {
                    try {
                        focused.recycle()
                    } catch (_: Exception) {}
                }
            }
        } catch (_: Exception) {}
        // 2. Fallback: first editable node in the active window.
        val root = try {
            rootInActiveWindow
        } catch (_: Exception) {
            null
        } ?: return mapOf(
            "success" to false,
            "status" to "NO_FOCUS",
            "errorMessage" to "No active window / no editable node"
        )
        try {
            val target = findFirstEditable(root)
            if (target == null) {
                return mapOf(
                    "success" to false,
                    "status" to "NO_FOCUS",
                    "errorMessage" to "No editable field found"
                )
            }
            try {
                val args = android.os.Bundle().apply {
                    putCharSequence(
                        AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                        text
                    )
                }
                val ok = try {
                    target.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
                } catch (_: Exception) {
                    false
                }
                return if (ok) {
                    mapOf("success" to true, "status" to "SUCCESS")
                } else {
                    mapOf(
                        "success" to false,
                        "status" to "SET_TEXT_FAILED",
                        "errorMessage" to "Node rejected ACTION_SET_TEXT"
                    )
                }
            } finally {
                try {
                    target.recycle()
                } catch (_: Exception) {}
            }
        } finally {
            try {
                root.recycle()
            } catch (_: Exception) {}
        }
    }

    private fun findFirstEditable(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        try {
            if (try {
                    node.isEditable
                } catch (_: Exception) {
                    false
                }
            ) return node
        } catch (_: Exception) {}
        val count = try {
            node.childCount
        } catch (_: Exception) {
            0
        }
        for (i in 0 until count) {
            val child = try {
                node.getChild(i)
            } catch (_: Exception) {
                null
            } ?: continue
            val found = findFirstEditable(child)
            if (found != null) {
                if (found !== child) {
                    try {
                        child.recycle()
                    } catch (_: Exception) {}
                }
                return found
            }
            try {
                child.recycle()
            } catch (_: Exception) {}
        }
        return null
    }

    /** Public tap helper for first-party features (e.g. YouTube auto-play). */
    suspend fun tapAt(xPct: Double, yPct: Double): Boolean = performTap(xPct, yPct)

    /** Public swipe helper for first-party features (e.g. YouTube auto-play). */
    suspend fun swipeAt(xPct: Double, yPct: Double, x2Pct: Double, y2Pct: Double, dur: Long): Boolean =
        performSwipe(xPct, yPct, x2Pct, y2Pct, dur)

    /**
     * Clicks the Nth YouTube search result (1-based) via the accessibility
     * tree, with coordinate-tap fallback.
     *
     * YouTube result rows expose thumbnails/titles as distinct nodes. We
     * collect thumbnail-like nodes in top-to-bottom traversal order and click
     * the requested one through its clickable ancestor (ACTION_CLICK), which
     * is far more reliable than fixed screen fractions across devices,
     * orientations and UI variants (ads, Shorts shelf, tablets).
     *
     * Returns true when a click/tap was dispatched.
     */
    suspend fun clickNthYouTubeResult(index: Int): Boolean {
        val safeIndex = index.coerceIn(1, 50)
        // Poll for results to load (slow networks): up to ~8s.
        val deadline = System.currentTimeMillis() + 8000
        var attempt = 0
        while (System.currentTimeMillis() < deadline) {
            attempt++
            // 1. Node-based click (preferred).
            try {
                if (clickNthVideoNode(safeIndex)) return true
            } catch (_: Exception) {}
            // 2. Coordinate fallback with layout-aware positions + scroll for deep indices.
            try {
                if (safeIndex > 4 && attempt == 2) {
                    swipeAt(0.5, 0.7, 0.5, 0.3, 350)
                    delay(900)
                }
                val y = when (safeIndex) {
                    1 -> 0.34
                    2 -> 0.55
                    3 -> 0.76
                    else -> 0.55
                }
                if (performTap(0.5, y)) {
                    // Give the player a moment; caller treats dispatch as success.
                    return true
                }
            } catch (_: Exception) {}
            delay(1200)
        }
        return false
    }

    private suspend fun clickNthVideoNode(wantIndex: Int): Boolean {
        val root = rootInActiveWindow ?: return false
        try {
            val thumbnails = mutableListOf<AccessibilityNodeInfo>()
            val titles = mutableListOf<AccessibilityNodeInfo>()
            collectYouTubeResultNodes(root, thumbnails, titles)
            val candidates = if (thumbnails.size >= wantIndex) thumbnails else titles
            if (candidates.size < wantIndex) return false
            val node = candidates[wantIndex - 1]
            // Prefer ACTION_CLICK on self or nearest clickable ancestor.
            var cur: AccessibilityNodeInfo? = node
            var depth = 0
            var clicked = false
            while (cur != null && depth < 8) {
                try {
                    if (cur.isClickable) {
                        clicked = cur.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                        if (clicked) break
                    }
                } catch (_: Exception) {}
                cur = try { cur.parent } catch (_: Exception) { null }
                depth++
            }
            if (!clicked) {
                // Bounds-tap fallback for this exact node.
                try {
                    val rect = Rect()
                    node.getBoundsInScreen(rect)
                    if (!rect.isEmpty) {
                        val metrics = resources.displayMetrics
                        val xPct = ((rect.left + rect.right) / 2f / metrics.widthPixels).toDouble()
                        val yPct = ((rect.top + rect.bottom) / 2f / metrics.heightPixels).toDouble()
                        clicked = performTap(xPct.coerceIn(0.0, 1.0), yPct.coerceIn(0.0, 1.0))
                    }
                } catch (_: Exception) {}
            }
            return clicked
        } finally {
            try { root.recycle() } catch (_: Exception) {}
        }
    }

    private fun collectYouTubeResultNodes(
        root: AccessibilityNodeInfo,
        thumbnails: MutableList<AccessibilityNodeInfo>,
        titles: MutableList<AccessibilityNodeInfo>
    ) {
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        var iterations = 0
        val seen = HashSet<Int>()
        while (queue.isNotEmpty() && iterations < 1200) {
            iterations++
            val node = queue.removeFirst()
            try {
                val viewId = try { node.viewIdResourceName ?: "" } catch (_: Exception) { "" }
                val idLower = viewId.lowercase()
                val text = try { node.text?.toString() ?: "" } catch (_: Exception) { "" }
                val desc = try { node.contentDescription?.toString() ?: "" } catch (_: Exception) { "" }
                val hash = System.identityHashCode(node)
                if (idLower.contains("thumbnail") && seen.add(hash)) {
                    thumbnails.add(node)
                    // Do not recycle kept nodes here; caller recycles root only.
                    // Children still traversed for sibling titles.
                } else if ((idLower.contains("video_title") || idLower.endsWith("/title")) &&
                    text.trim().length > 2 && seen.add(hash)) {
                    titles.add(node)
                } else if (desc.contains(Regex("\\d+:\\d+")) && seen.add(hash)) {
                    // Duration badge (e.g. "12:34") marks a video row; keep its parent row
                    // via the node itself as a last-resort candidate.
                    if (titles.size < 50) titles.add(node)
                }
            } catch (_: Exception) {}
            try {
                for (i in 0 until node.childCount) {
                    val child = try { node.getChild(i) } catch (_: Exception) { null } ?: continue
                    queue.add(child)
                }
            } catch (_: Exception) {}
        }
    }

    fun startRecording(): Boolean {
        if (!isAccessibilityEnabled(this)) return false
        recordedSteps.clear()
        recordedPackage = null
        isRecording = true
        return true
    }

    fun getRecordedPackage(): String? = recordedPackage

    fun stopRecording(): List<Map<String, Any?>> {
        isRecording = false
        val copy = recordedSteps.toList()
        val pkg = recordedPackage
        recordedSteps.clear()
        recordedPackage = null
        // Convert findAndTap internal to TapStep json format
        val steps = copy.map { m ->
            val type = m["selectorType"] as? String
            when (type) {
                "id" -> mapOf(
                    "type" to "findById",
                    "selectorValue" to m["selectorValue"],
                    "xPct" to m["xPct"],
                    "yPct" to m["yPct"],
                    "packageName" to m["packageName"],
                    "delayAfterMs" to 500
                )
                "text" -> mapOf(
                    "type" to "findByText",
                    "selectorValue" to m["selectorValue"],
                    "xPct" to m["xPct"],
                    "yPct" to m["yPct"],
                    "packageName" to m["packageName"],
                    "delayAfterMs" to 500
                )
                "desc" -> mapOf(
                    "type" to "findByDesc",
                    "selectorValue" to m["selectorValue"],
                    "xPct" to m["xPct"],
                    "yPct" to m["yPct"],
                    "packageName" to m["packageName"],
                    "delayAfterMs" to 500
                )
                else -> mapOf(
                    "type" to "tap",
                    "xPct" to m["xPct"],
                    "yPct" to m["yPct"],
                    "packageName" to m["packageName"],
                    "delayAfterMs" to 500
                )
            }
        }.toMutableList()
        // Prepend openApp if we inferred a package and steps don't already start with open
        if (pkg != null && steps.isNotEmpty()) {
            val firstType = (steps.first()["type"] as? String)?.lowercase()
            if (firstType != "open_app" && firstType != "openapp" && firstType != "launch_app") {
                steps.add(0, mapOf(
                    "type" to "openApp",
                    "targetPackage" to pkg,
                    "delayAfterMs" to 1200
                ))
            }
        }
        // Filter out find steps with blank selector (fallback to tap)
        return steps.map { s ->
            val t = (s["type"] as? String)?.lowercase()
            val sel = s["selectorValue"] as? String
            if ((t == "findbyid" || t == "findbytext" || t == "findbydesc") && sel.isNullOrBlank()) {
                mapOf(
                    "type" to "tap",
                    "xPct" to s["xPct"],
                    "yPct" to s["yPct"],
                    "packageName" to s["packageName"],
                    "delayAfterMs" to s["delayAfterMs"]
                )
            } else s
        }
    }

    fun cancelRecording() {
        isRecording = false
        recordedSteps.clear()
    }

    suspend fun executeSteps(steps: List<Map<String, Any?>>, targetPackage: String?): Map<String, Any?> {
        val collected = mutableListOf<String>()
        // Auto-launch target package if provided and not already handled by first step
        var effectivePackage = targetPackage
        if (effectivePackage.isNullOrBlank()) {
            // Try to infer from first step's package
            for (s in steps) {
                val pkg = s["packageName"] as? String ?: s["targetPackage"] as? String
                if (!pkg.isNullOrBlank() && pkg != packageName) {
                    effectivePackage = pkg
                    break
                }
            }
        }
        if (!effectivePackage.isNullOrBlank() && effectivePackage != packageName) {
            // If first step is not already openApp, launch now
            val firstType = (steps.firstOrNull()?.get("type") as? String)?.lowercase()
            if (firstType != "open_app" && firstType != "openapp" && firstType != "launch_app") {
                val launched = launchPackage(effectivePackage)
                if (!launched) {
                    return errorMap("APP_NOT_FOUND", "Cannot launch $effectivePackage. Is it installed?")
                }
                delay(1200)
            }
        }

        for ((index, step) in steps.withIndex()) {
            val type = (step["type"] as? String)?.lowercase() ?: "tap"
            val delayAfter = (step["delayAfterMs"] as? Number)?.toLong() ?: 400L
            try {
                when (type) {
                    "tap" -> {
                        val xPct = (step["xPct"] as? Number)?.toDouble() ?: 0.5
                        val yPct = (step["yPct"] as? Number)?.toDouble() ?: 0.5
                        val ok = performTap(xPct, yPct)
                        if (!ok) return errorMap("GESTURE_FAILED", "Tap failed at step $index")
                    }
                    "swipe" -> {
                        val x = (step["xPct"] as? Number)?.toDouble() ?: 0.5
                        val y = (step["yPct"] as? Number)?.toDouble() ?: 0.5
                        val x2 = (step["x2Pct"] as? Number)?.toDouble() ?: 0.5
                        val y2 = (step["y2Pct"] as? Number)?.toDouble() ?: 0.5
                        val dur = (step["durationMs"] as? Number)?.toLong() ?: 300L
                        val ok = performSwipe(x, y, x2, y2, dur)
                        if (!ok) return errorMap("GESTURE_FAILED", "Swipe failed at step $index")
                    }
                    "wait", "delay" -> {
                        val ms = (step["durationMs"] as? Number)?.toLong()
                            ?: (step["delayAfterMs"] as? Number)?.toLong()
                            ?: (step["ms"] as? Number)?.toLong()
                            ?: 500L
                        delay(ms)
                    }
                    "open_app", "openapp", "launch_app", "openApp" -> {
                        val target = (step["targetPackage"] as? String)
                            ?: (step["target"] as? String)
                            ?: targetPackage
                        if (target != null) {
                            val launched = launchPackage(target)
                            if (!launched) return errorMap("APP_NOT_FOUND", "Cannot launch $target")
                        }
                        delay(1200)
                    }
                    "input_text", "input", "set_text", "type_text", "inputText", "inputtext" -> {
                        val text = (step["inputValue"] as? String)
                            ?: (step["text"] as? String)
                            ?: (step["value"] as? String) ?: ""
                        if (text.isNotEmpty()) {
                            // 1. Try the focused input node first.
                            var done = false
                            val focused = try { findFocus(AccessibilityNodeInfo.FOCUS_INPUT) } catch (_: Exception) { null }
                            if (focused != null) {
                                try {
                                    val args = android.os.Bundle().apply {
                                        putCharSequence(
                                            AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                                            text
                                        )
                                    }
                                    if (focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)) done = true
                                } catch (_: Exception) {}
                                try { focused.recycle() } catch (_: Exception) {}
                            }
                            // 2. Fallback: first editable node in the active window.
                            // This is what fixes DeepSeek: its composer hint differs
                            // ("Message DeepSeek"), so focus taps can miss and the
                            // old code silently typed nothing.
                            if (!done) {
                                val root = try { rootInActiveWindow } catch (_: Exception) { null }
                                if (root != null) {
                                    try {
                                        val target = findFirstEditable(root)
                                        if (target != null) {
                                            try {
                                                val args = android.os.Bundle().apply {
                                                    putCharSequence(
                                                        AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                                                        text
                                                    )
                                                }
                                                target.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
                                            } catch (_: Exception) {}
                                            try { target.recycle() } catch (_: Exception) {}
                                        }
                                    } finally {
                                        try { root.recycle() } catch (_: Exception) {}
                                    }
                                }
                            }
                        }
                    }
                    "find_by_text", "findbytext", "find_text", "findByText" -> {
                        val query = (step["selectorValue"] as? String)
                            ?: (step["text"] as? String) ?: ""
                        val contains = (step["contains"] as? Boolean) ?: false
                        val tapped = findAndTapText(query, contains)
                        if (!tapped) {
                            // Fallback to coordinate tap if available
                            val xPct = (step["xPct"] as? Number)?.toDouble()
                            val yPct = (step["yPct"] as? Number)?.toDouble()
                            if (xPct != null && yPct != null) {
                                val ok = performTap(xPct, yPct)
                                if (!ok) return errorMap("TIMEOUT", "Could not find text \"$query\" at step $index")
                            } else {
                                return errorMap("TIMEOUT", "Could not find text \"$query\" at step $index")
                            }
                        }
                    }
                    "find_by_desc", "findbydesc", "find_desc", "findByDesc" -> {
                        val query = (step["selectorValue"] as? String)
                            ?: (step["desc"] as? String) ?: ""
                        val contains = (step["contains"] as? Boolean) ?: false
                        val tapped = findAndTapDesc(query, contains)
                        if (!tapped) {
                            val xPct = (step["xPct"] as? Number)?.toDouble()
                            val yPct = (step["yPct"] as? Number)?.toDouble()
                            if (xPct != null && yPct != null) {
                                val ok = performTap(xPct, yPct)
                                if (!ok) return errorMap("TIMEOUT", "Could not find desc \"$query\" at step $index")
                            } else {
                                return errorMap("TIMEOUT", "Could not find desc \"$query\" at step $index")
                            }
                        }
                    }
                    "find_by_id", "findbyid", "find_id", "findById" -> {
                        val viewId = (step["selectorValue"] as? String)
                            ?: (step["viewId"] as? String) ?: ""
                        val tapped = findAndTapId(viewId)
                        if (!tapped) {
                            val xPct = (step["xPct"] as? Number)?.toDouble()
                            val yPct = (step["yPct"] as? Number)?.toDouble()
                            if (xPct != null && yPct != null) {
                                val ok = performTap(xPct, yPct)
                                if (!ok) return errorMap("TIMEOUT", "Could not find id \"$viewId\" at step $index")
                            } else {
                                return errorMap("TIMEOUT", "Could not find id \"$viewId\" at step $index")
                            }
                        }
                    }
                    "back" -> {
                        performGlobalAction(GLOBAL_ACTION_BACK)
                    }
                    "collect", "collect_text", "collect_texts" -> {
                        val selector = (step["collectSelector"] as? String)
                            ?: (step["selectorValue"] as? String) ?: ""
                        val count = (step["collectCount"] as? Number)?.toInt() ?: 10
                        val texts = collectTexts(selector, count)
                        collected.addAll(texts)
                    }
                    else -> {
                        // Unknown type treated as wait
                        delay(300)
                    }
                }
            } catch (e: Exception) {
                return errorMap("EXECUTION_FAILED", e.localizedMessage ?: "Failed at step $index: $type")
            }
            if (delayAfter > 0) delay(delayAfter)
        }
        return mapOf(
            "success" to true,
            "status" to "SUCCESS",
            "collectedTexts" to collected
        )
    }

    private fun errorMap(status: String, msg: String): Map<String, Any?> = mapOf(
        "success" to false,
        "status" to status,
        "errorMessage" to msg,
        "collectedTexts" to emptyList<String>()
    )

    private suspend fun performTap(xPct: Double, yPct: Double): Boolean {
        val metrics = resources.displayMetrics
        val x = (xPct.coerceIn(0.0, 1.0) * metrics.widthPixels).toFloat()
        val y = (yPct.coerceIn(0.0, 1.0) * metrics.heightPixels).toFloat()
        val path = Path().apply { moveTo(x, y) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 80))
            .build()
        return dispatchGestureSuspend(gesture)
    }

    private suspend fun performSwipe(xPct: Double, yPct: Double, x2Pct: Double, y2Pct: Double, dur: Long): Boolean {
        val metrics = resources.displayMetrics
        val x = (xPct.coerceIn(0.0, 1.0) * metrics.widthPixels).toFloat()
        val y = (yPct.coerceIn(0.0, 1.0) * metrics.heightPixels).toFloat()
        val x2 = (x2Pct.coerceIn(0.0, 1.0) * metrics.widthPixels).toFloat()
        val y2 = (y2Pct.coerceIn(0.0, 1.0) * metrics.heightPixels).toFloat()
        val path = Path().apply {
            moveTo(x, y)
            lineTo(x2, y2)
        }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, dur.coerceIn(50, 2000)))
            .build()
        return dispatchGestureSuspend(gesture)
    }

    private suspend fun dispatchGestureSuspend(gesture: GestureDescription): Boolean {
        // Use suspendCancellableCoroutine with callback
        return withContext(Dispatchers.Main) {
            var result = false
            var completed = false
            val latch = CompletableDeferred<Boolean>()
            val callback = object : GestureResultCallback() {
                override fun onCompleted(gesture: GestureDescription?) {
                    if (!completed) {
                        completed = true
                        latch.complete(true)
                    }
                }
                override fun onCancelled(gesture: GestureDescription?) {
                    if (!completed) {
                        completed = true
                        latch.complete(false)
                    }
                }
            }
            try {
                dispatchGesture(gesture, callback, null)
                // Wait with timeout
                withTimeoutOrNull(2000) { latch.await() } ?: false
            } catch (_: Exception) {
                false
            }
        }
    }

    private fun findAndTapText(query: String, contains: Boolean): Boolean {
        if (query.isBlank()) return false
        // Poll for up to 3s
        val deadline = System.currentTimeMillis() + 3000
        while (System.currentTimeMillis() < deadline) {
            val root = rootInActiveWindow ?: run { Thread.sleep(200); continue }
            val found = findNodeByText(root, query, contains)
            if (found != null) {
                var node: AccessibilityNodeInfo? = found
                // Walk up to clickable parent
                var clickable: AccessibilityNodeInfo? = null
                var cur: AccessibilityNodeInfo? = node
                var depth = 0
                while (cur != null && depth < 8) {
                    if (cur.isClickable) { clickable = cur; break }
                    val parent = cur.parent
                    // Avoid leaking root
                    if (parent == null) break
                    // Don't recycle root yet
                    if (cur !== found && cur !== root) try { cur.recycle() } catch(_:Exception){}
                    cur = parent
                    depth++
                }
                val target = clickable ?: node
                val success = target?.performAction(AccessibilityNodeInfo.ACTION_CLICK) ?: false
                // Cleanup
                try { if (target !== node && target !== root) target?.recycle() } catch(_:Exception){}
                try { if (node !== root) node?.recycle() } catch(_:Exception){}
                try { if (root !== node && root !== target) root.recycle() } catch(_:Exception){} 
                if (success) return true
                // Try tapping via bounds gesture as fallback
                val rect = Rect()
                target?.getBoundsInScreen(rect)
                if (!rect.isEmpty) {
                    val metrics = resources.displayMetrics
                    val xPct = ((rect.left+rect.right)/2f / metrics.widthPixels).toDouble()
                    val yPct = ((rect.top+rect.bottom)/2f / metrics.heightPixels).toDouble()
                    // Fire gesture async
                    serviceScope.launch { performTap(xPct, yPct) }
                    return true
                }
            } else {
                try { root.recycle() } catch(_:Exception){}
            }
            Thread.sleep(250)
        }
        return false
    }

    private fun findAndTapDesc(query: String, contains: Boolean): Boolean {
        if (query.isBlank()) return false
        val deadline = System.currentTimeMillis() + 3000
        while (System.currentTimeMillis() < deadline) {
            val root = rootInActiveWindow ?: run { Thread.sleep(200); continue }
            val found = findNodeByDesc(root, query, contains)
            if (found != null) {
                var target: AccessibilityNodeInfo? = found
                var cur: AccessibilityNodeInfo? = found
                var depth = 0
                while (cur != null && depth < 8) {
                    if (cur.isClickable) { target = cur; break }
                    cur = cur.parent
                    depth++
                }
                val success = target?.performAction(AccessibilityNodeInfo.ACTION_CLICK) ?: false
                try { if (target !== found) target?.recycle() } catch(_:Exception){}
                try { found.recycle() } catch(_:Exception){}
                try { root.recycle() } catch(_:Exception){}
                if (success) return true
            } else {
                try { root.recycle() } catch(_:Exception){}
            }
            Thread.sleep(250)
        }
        return false
    }

    private fun findAndTapId(viewId: String): Boolean {
        if (viewId.isBlank()) return false
        val deadline = System.currentTimeMillis() + 3000
        while (System.currentTimeMillis() < deadline) {
            val root = rootInActiveWindow ?: run { Thread.sleep(200); continue }
            val nodes = root.findAccessibilityNodeInfosByViewId(viewId)
            val found = nodes?.firstOrNull()
            if (found != null) {
                var target: AccessibilityNodeInfo? = found
                var cur: AccessibilityNodeInfo? = found
                var depth = 0
                while (cur != null && depth < 8) {
                    if (cur.isClickable) { target = cur; break }
                    cur = cur.parent
                    depth++
                }
                val success = target?.performAction(AccessibilityNodeInfo.ACTION_CLICK) ?: false
                try { nodes.forEach { if (it !== target && it !== found) it.recycle() } } catch(_:Exception){}
                try { if (target !== found) target?.recycle() } catch(_:Exception){}
                try { found.recycle() } catch(_:Exception){}
                try { root.recycle() } catch(_:Exception){}
                if (success) return true
            } else {
                try { root.recycle() } catch(_:Exception){}
            }
            Thread.sleep(250)
        }
        return false
    }

    private fun findNodeByText(root: AccessibilityNodeInfo, query: String, contains: Boolean): AccessibilityNodeInfo? {
        // Try framework find first
        try {
            val list = root.findAccessibilityNodeInfosByText(query)
            if (!list.isNullOrEmpty()) {
                val exact = list.firstOrNull { it.text?.toString()?.equals(query, ignoreCase = true) == true }
                val chosen = exact ?: list.first()
                // Keep chosen, recycle others
                list.forEach { if (it !== chosen) try{it.recycle()}catch(_:Exception){} }
                return chosen
            } else {
                list?.forEach { try{it.recycle()}catch(_:Exception){} }
            }
        } catch(_:Exception){}
        // Fallback: BFS with contains
        return bfsFind(root) { node ->
            val text = node.text?.toString() ?: ""
            val desc = node.contentDescription?.toString() ?: ""
            if (contains) text.contains(query, ignoreCase = true) || desc.contains(query, ignoreCase = true)
            else text.equals(query, ignoreCase = true) || desc.equals(query, ignoreCase = true)
        }
    }

    private fun findNodeByDesc(root: AccessibilityNodeInfo, query: String, contains: Boolean): AccessibilityNodeInfo? {
        return bfsFind(root) { node ->
            val desc = node.contentDescription?.toString() ?: ""
            if (contains) desc.contains(query, ignoreCase = true)
            else desc.equals(query, ignoreCase = true)
        }
    }

    private fun bfsFind(root: AccessibilityNodeInfo, predicate: (AccessibilityNodeInfo)->Boolean): AccessibilityNodeInfo? {
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        val visited = mutableSetOf<AccessibilityNodeInfo>()
        var iterations = 0
        while (queue.isNotEmpty() && iterations < 800) {
            iterations++
            val node = queue.removeFirst()
            if (predicate(node)) return node
            for (i in 0 until node.childCount) {
                val child = node.getChild(i) ?: continue
                queue.add(child)
            }
        }
        return null
    }

    private fun collectTexts(selector: String, maxCount: Int): List<String> {
        val root = rootInActiveWindow ?: return emptyList()
        try {
            val texts = mutableListOf<String>()
            collectTextsRecursive(root, texts, selector)
            // Deduplicate, keep last maxCount
            val distinct = texts.distinct().filter { it.isNotBlank() && it.length > 1 }
            return if (distinct.size > maxCount) distinct.takeLast(maxCount) else distinct
        } finally {
            try { root.recycle() } catch(_:Exception){}
        }
    }

    private fun collectTextsRecursive(node: AccessibilityNodeInfo, out: MutableList<String>, selector: String) {
        val text = node.text?.toString()?.trim()
        val desc = node.contentDescription?.toString()?.trim()
        val candidate = when {
            !text.isNullOrBlank() -> text
            !desc.isNullOrBlank() -> desc
            else -> null
        }
        if (candidate != null) {
            if (selector.isBlank() || candidate.contains(selector, ignoreCase = true) || node.viewIdResourceName?.contains(selector) == true || node.className?.toString()?.contains(selector, ignoreCase = true) == true) {
                out.add(candidate)
            } else if (selector.isBlank()) {
                out.add(candidate)
            }
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            collectTextsRecursive(child, out, selector)
            // Do not recycle child aggressively if we need traversal? But recycle leaf children
            // Keep traversal: don't recycle intermediate until done.
        }
    }

    private fun launchPackage(packageName: String): Boolean {
        return try {
            val intent = packageManager.getLaunchIntentForPackage(packageName)
                ?: return tryLaunchByQuery(packageName)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun tryLaunchByQuery(target: String): Boolean {
        // Try via AppLauncher logic: query and launch
        try {
            val pm = packageManager
            val intent = Intent(Intent.ACTION_MAIN).apply { addCategory(Intent.CATEGORY_LAUNCHER) }
            val infos = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION") pm.queryIntentActivities(intent, 0)
            }
            val clean = target.lowercase().filter { it.isLetterOrDigit() }
            for (info in infos) {
                val pkg = info.activityInfo.packageName ?: continue
                val label = try { info.loadLabel(pm).toString() } catch(_:Exception){ continue }
                val norm = label.filter{it.isLetterOrDigit()}.lowercase()
                if (norm == clean || pkg.contains(target, ignoreCase = true) || label.contains(target, ignoreCase = true)) {
                    val launch = pm.getLaunchIntentForPackage(pkg) ?: continue
                    launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(launch)
                    return true
                }
            }
        } catch (_:Exception){}
        return false
    }

    companion object {
        fun isAccessibilityEnabled(context: Context): Boolean {
            val enabledServices = Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
            val packageName = context.packageName
            // Check if our service is in enabled list
            return enabledServices.contains(packageName)
        }
    }
}
