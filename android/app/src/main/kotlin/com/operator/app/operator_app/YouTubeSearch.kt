package com.operator.app.operator_app

import android.app.SearchManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import kotlinx.coroutines.delay

class YouTubeSearch(private val context: Context) {

    companion object {
        const val YOUTUBE_PACKAGE = "com.google.android.youtube"
    }

    /**
     * Opens YouTube with [query] and best-effort plays the Nth result.
     *
     * Reliable part (always): opens the YouTube search-results page for the
     * query — no API key or network library needed, works offline-first.
     *
     * Best-effort part: when the FRIDAY accessibility service is enabled,
     * taps the Nth result after the page loads so the video starts playing.
     * Returns autoPlayed=true only when the tap gesture was dispatched.
     */
    suspend fun searchAndPlay(query: String?, index: Int?): Map<String, Any?> {
        val cleanQuery = query?.trim() ?: ""
        if (cleanQuery.isEmpty() || cleanQuery.length > 200) {
            return errorMap("INVALID_REQUEST", "Search query must not be empty.")
        }
        val safeIndex = (index ?: 1).coerceIn(1, 50)

        if (!isYouTubeInstalled()) {
            return errorMap("YOUTUBE_NOT_INSTALLED", "YouTube is not installed on this device.")
        }

        // 1. Open the search-results page. Prefer the native app via package.
        val encoded = Uri.encode(cleanQuery)
        val searchUri = Uri.parse("https://www.youtube.com/results?search_query=$encoded")

        val opened = tryOpenSearch(searchUri, cleanQuery)
        if (!opened) {
            return errorMap("LAUNCH_FAILED", "Could not open YouTube search.")
        }

        // 2. Best-effort auto-play of the Nth result via accessibility.
        // Requires the FRIDAY accessibility service to be enabled AND bound
        // (instance non-null). Node-based click with coordinate fallback and
        // retries inside clickNthYouTubeResult.
        var autoPlayed = false
        val accessibilityEnabled = AutomationAccessibilityService.isAccessibilityEnabled(context)
        try {
            val svc = AutomationAccessibilityServiceHolder.instance
            if (svc != null && accessibilityEnabled) {
                // Give the results page a moment to start loading; the click
                // helper itself polls up to ~8s for rows to appear.
                delay(1800)
                autoPlayed = svc.clickNthYouTubeResult(safeIndex)
            }
        } catch (_: Exception) {
            autoPlayed = false
        }

        return mapOf(
            "success" to true,
            "status" to "SUCCESS",
            "autoPlayed" to autoPlayed,
            "accessibilityEnabled" to accessibilityEnabled
        )
    }

    fun isYouTubeInstalled(): Boolean {
        return try {
            @Suppress("DEPRECATION")
            context.packageManager.getPackageInfo(YOUTUBE_PACKAGE, 0)
            true
        } catch (_: Exception) {
            // Fallback: can some activity handle a YouTube search VIEW?
            val probe = Intent(
                Intent.ACTION_VIEW,
                Uri.parse("https://www.youtube.com/results?search_query=test")
            )
            context.packageManager.resolveActivity(
                probe, PackageManager.MATCH_DEFAULT_ONLY
            ) != null
        }
    }

    private fun tryOpenSearch(searchUri: Uri, cleanQuery: String): Boolean {
        // Attempt 1: VIEW the results page directly in the YouTube app.
        try {
            val appIntent = Intent(Intent.ACTION_VIEW, searchUri).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                `package` = YOUTUBE_PACKAGE
            }
            if (context.packageManager.resolveActivity(
                    appIntent, PackageManager.MATCH_DEFAULT_ONLY
                ) != null) {
                context.startActivity(appIntent)
                return true
            }
        } catch (_: Exception) {}

        // Attempt 2: ACTION_SEARCH restricted to YouTube.
        try {
            val searchIntent = Intent(Intent.ACTION_SEARCH).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra(SearchManager.QUERY, cleanQuery)
                `package` = YOUTUBE_PACKAGE
            }
            if (context.packageManager.resolveActivity(
                    searchIntent, PackageManager.MATCH_DEFAULT_ONLY
                ) != null) {
                context.startActivity(searchIntent)
                return true
            }
        } catch (_: Exception) {}

        // Attempt 3: VIEW without a package (browser fallback).
        return try {
            val fallback = Intent(Intent.ACTION_VIEW, searchUri).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(fallback)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun errorMap(status: String, msg: String): Map<String, Any?> = mapOf(
        "success" to false,
        "status" to status,
        "errorMessage" to msg
    )
}
