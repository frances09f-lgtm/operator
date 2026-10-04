package com.operator.app.operator_app

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build

class AppLauncher(private val context: Context) {

    data class LaunchResult(
        val success: Boolean,
        val status: String,
        val packageName: String? = null,
        val appLabel: String? = null,
        val errorMessage: String? = null
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "success" to success,
            "status" to status,
            "packageName" to packageName,
            "appLabel" to appLabel,
            "errorMessage" to errorMessage
        )
    }

    /** Result of resolving a target name to a concrete launchable app. */
    private data class Resolution(
        val status: String,
        val packageName: String? = null,
        val appLabel: String? = null,
        val errorMessage: String? = null
    )

    /**
     * Resolves an application matching [targetName] without launching it.
     * Performs strict validation on the native side and returns the app's
     * display label when found.
     */
    fun resolveApp(targetName: String?): LaunchResult {
        val resolution = resolve(targetName)
        return when (resolution.status) {
            "OK" -> LaunchResult(
                success = true,
                status = "SUCCESS",
                packageName = resolution.packageName,
                appLabel = resolution.appLabel
            )
            else -> LaunchResult(
                success = false,
                status = resolution.status,
                packageName = resolution.packageName,
                appLabel = resolution.appLabel,
                errorMessage = resolution.errorMessage
            )
        }
    }

    /**
     * Resolves and launches an application matching [targetName].
     * Performs strict validation on the native side.
     */
    fun launchApp(targetName: String?): LaunchResult {
        val resolution = resolve(targetName)
        if (resolution.status != "OK") {
            return LaunchResult(
                success = false,
                status = resolution.status,
                packageName = resolution.packageName,
                appLabel = resolution.appLabel,
                errorMessage = resolution.errorMessage
            )
        }

        val launchIntent = context.packageManager.getLaunchIntentForPackage(resolution.packageName!!)
            ?: return LaunchResult(
                success = false,
                status = "NOT_LAUNCHABLE",
                packageName = resolution.packageName,
                appLabel = resolution.appLabel,
                errorMessage = "Found ${resolution.appLabel} but it cannot be launched directly."
            )

        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

        return try {
            context.startActivity(launchIntent)
            LaunchResult(
                success = true,
                status = "SUCCESS",
                packageName = resolution.packageName,
                appLabel = resolution.appLabel
            )
        } catch (e: Exception) {
            LaunchResult(
                success = false,
                status = "LAUNCH_FAILED",
                packageName = resolution.packageName,
                appLabel = resolution.appLabel,
                errorMessage = e.localizedMessage ?: "Failed to launch application."
            )
        }
    }

    /**
     * Core validation + resolution shared by [resolveApp] and [launchApp].
     */
    private fun resolve(targetName: String?): Resolution {
        // 1. Strict native validation
        if (targetName.isNullOrBlank()) {
            return Resolution(
                status = "INVALID_REQUEST",
                errorMessage = "App target name is empty."
            )
        }

        // Clean target name: remove "app" suffix if user said e.g. "youtube app"
        var cleanTarget = targetName.trim()
        if (cleanTarget.endsWith(" app", ignoreCase = true)) {
            cleanTarget = cleanTarget.substring(0, cleanTarget.length - 4).trim()
        }

        if (cleanTarget.isBlank() || cleanTarget.length > 100) {
            return Resolution(
                status = "INVALID_REQUEST",
                errorMessage = "App target name is invalid."
            )
        }

        // 2. Query all launchable applications
        val packageManager = context.packageManager
        val launcherIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }

        val resolveInfos = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.queryIntentActivities(
                launcherIntent,
                PackageManager.ResolveInfoFlags.of(0)
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(launcherIntent, 0)
        }

        if (resolveInfos.isEmpty()) {
            return Resolution(
                status = "APP_NOT_FOUND",
                errorMessage = "No launchable applications discovered on device."
            )
        }

        // 3. Application Resolution Layer
        var bestPackageName: String? = null
        var bestAppLabel: String? = null
        var bestScore = -1

        val targetNormalized = cleanTarget.filter { it.isLetterOrDigit() }.lowercase()

        for (resolveInfo in resolveInfos) {
            val pkg = resolveInfo.activityInfo.packageName ?: continue
            val label = try {
                resolveInfo.loadLabel(packageManager).toString()
            } catch (_: Exception) {
                continue
            }

            val labelClean = label.trim()
            val labelNormalized = labelClean.filter { it.isLetterOrDigit() }.lowercase()
            val pkgNormalized = pkg.filter { it.isLetterOrDigit() }.lowercase()

            var score = 0

            when {
                // Exact match on label
                labelClean.equals(cleanTarget, ignoreCase = true) -> score = 100
                // Normalized alphanumeric exact match
                labelNormalized == targetNormalized -> score = 95
                // Label starts with target (e.g. "WhatsApp Messenger" vs "WhatsApp")
                labelClean.startsWith(cleanTarget, ignoreCase = true) -> score = 85
                // Target starts with label
                cleanTarget.startsWith(labelClean, ignoreCase = true) -> score = 80
                // Normalized label contains normalized target
                labelNormalized.contains(targetNormalized) -> score = 75
                // Normalized target contains normalized label
                targetNormalized.contains(labelNormalized) -> score = 70
                // Package name contains target (e.g., "com.google.android.youtube", "com.spotify.music")
                pkgNormalized.contains(targetNormalized) -> score = 65
            }

            // Levenshtein fuzzy fallback for STT mishearing (e.g. "crome" -> "chrome", "you tube" -> "youtube")
            if (score == 0) {
                val distFull = levenshtein(targetNormalized, labelNormalized)
                val maxLenFull = maxOf(targetNormalized.length, labelNormalized.length)
                if (maxLenFull > 0) {
                    val firstMatch = targetNormalized.isNotEmpty() && labelNormalized.isNotEmpty() && targetNormalized[0] == labelNormalized[0]
                    score = when {
                        maxLenFull == 4 && distFull == 1 && firstMatch -> 62
                        maxLenFull in 5..6 && distFull == 1 -> 68
                        maxLenFull in 5..6 && distFull == 2 -> 62
                        maxLenFull >= 7 && distFull == 1 -> 68
                        maxLenFull >= 7 && distFull == 2 -> 64
                        maxLenFull >= 7 && distFull == 3 -> 60
                        else -> 0
                    }
                }
                // Also try package name fuzzy (for "spotify" vs "com.spotify.music")
                if (score == 0) {
                    // Check if target fuzzy matches any token of package (split by dot)
                    val pkgTokens = pkg.split(".", "_")
                    var bestPkgScore = 0
                    for (tok in pkgTokens) {
                        val tokNorm = tok.filter { it.isLetterOrDigit() }.lowercase()
                        if (tokNorm.isEmpty() || tokNorm.length < 3) continue
                        val d = levenshtein(targetNormalized, tokNorm)
                        val ml = maxOf(targetNormalized.length, tokNorm.length)
                        val firstTokMatch = targetNormalized.isNotEmpty() && tokNorm.isNotEmpty() && targetNormalized[0] == tokNorm[0]
                        val s = when {
                            ml == 4 && d == 1 && firstTokMatch -> 60
                            ml in 5..6 && d == 1 -> 64
                            ml in 5..6 && d == 2 -> 60
                            ml >= 7 && d == 1 -> 64
                            ml >= 7 && d == 2 -> 62
                            ml >= 7 && d == 3 -> 60
                            else -> 0
                        }
                        if (s > bestPkgScore) bestPkgScore = s
                    }
                    if (bestPkgScore > score) score = bestPkgScore
                }
                // Word-level: label like "Google Chrome" vs "crome"
                if (score == 0) {
                    val labelWords = labelClean.split(Regex("\\s+"))
                    var bestWordScore = 0
                    for (lw in labelWords) {
                        val lwNorm = lw.filter { it.isLetterOrDigit() }.lowercase()
                        if (lwNorm.isEmpty()) continue
                        val d = levenshtein(targetNormalized, lwNorm)
                        val ml = maxOf(targetNormalized.length, lwNorm.length)
                        val fm = targetNormalized.isNotEmpty() && lwNorm.isNotEmpty() && targetNormalized[0] == lwNorm[0]
                        val s1 = when {
                            ml == 4 && d == 1 && fm -> 60
                            ml in 5..6 && d == 1 -> 64
                            ml in 5..6 && d == 2 -> 60
                            ml >= 7 && d == 1 -> 64
                            ml >= 7 && d == 2 -> 62
                            ml >= 7 && d == 3 -> 60
                            else -> 0
                        }
                        if (s1 > bestWordScore) bestWordScore = s1
                        // Also each word of target vs label word (for "you tube" vs "youtube"? already handled by normalized equality)
                        val targetWords = cleanTarget.split(Regex("\\s+"))
                        for (tw in targetWords) {
                            val twNorm = tw.filter { it.isLetterOrDigit() }.lowercase()
                            if (twNorm.isEmpty()) continue
                            val d2 = levenshtein(twNorm, lwNorm)
                            val ml2 = maxOf(twNorm.length, lwNorm.length)
                            val fm2 = twNorm.isNotEmpty() && lwNorm.isNotEmpty() && twNorm[0] == lwNorm[0]
                            val s2 = when {
                                ml2 == 4 && d2 == 1 && fm2 -> 60
                                ml2 in 5..6 && d2 == 1 -> 64
                                ml2 in 5..6 && d2 == 2 -> 60
                                ml2 >= 7 && d2 == 1 -> 64
                                ml2 >= 7 && d2 == 2 -> 62
                                ml2 >= 7 && d2 == 3 -> 60
                                else -> 0
                            }
                            if (s2 > bestWordScore) bestWordScore = s2
                        }
                    }
                    if (bestWordScore > score) score = bestWordScore
                }
            }

            if (score > bestScore) {
                bestScore = score
                bestPackageName = pkg
                bestAppLabel = labelClean
            }
        }

        if (bestScore < 60 || bestPackageName == null) {
            return Resolution(
                status = "APP_NOT_FOUND",
                errorMessage = "Application matching '$cleanTarget' not found."
            )
        }

        return Resolution(
            status = "OK",
            packageName = bestPackageName,
            appLabel = bestAppLabel
        )
    }

    private fun levenshtein(a: String, b: String): Int {
        if (a == b) return 0
        if (a.isEmpty()) return b.length
        if (b.isEmpty()) return a.length
        val prev = IntArray(b.length + 1) { it }
        val curr = IntArray(b.length + 1)
        for (i in 1..a.length) {
            curr[0] = i
            for (j in 1..b.length) {
                val cost = if (a[i - 1] == b[j - 1]) 0 else 1
                curr[j] = minOf(
                    prev[j] + 1,
                    curr[j - 1] + 1,
                    prev[j - 1] + cost
                )
            }
            for (j in 0..b.length) prev[j] = curr[j]
        }
        return prev[b.length]
    }
}