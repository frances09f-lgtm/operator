package com.operator.app.operator_app

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.provider.ContactsContract

class WhatsApp(private val context: Context) {

    data class WhatsAppResult(
        val success: Boolean,
        val status: String,
        val resolvedPhone: String? = null,
        val resolvedName: String? = null,
        val errorMessage: String? = null
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "success" to success,
            "status" to status,
            "resolvedPhone" to resolvedPhone,
            "resolvedName" to resolvedName,
            "errorMessage" to errorMessage
        )
    }

    /**
     * Resolves [contactName] to a phone number via ContactsContract,
     * then launches WhatsApp with pre-filled [message].
     *
     * User must still tap send in WhatsApp — Android/WhatsApp security
     * does not allow silent background sends without AccessibilityService.
     */
    fun sendWhatsApp(contactName: String?, message: String?): WhatsAppResult {
        // 1. Strict validation
        if (contactName.isNullOrBlank() || message.isNullOrBlank()) {
            return WhatsAppResult(
                success = false,
                status = "INVALID_REQUEST",
                errorMessage = "Contact name and message must not be empty."
            )
        }

        val cleanName = contactName.trim()
        val cleanMessage = message.trim()

        if (cleanName.length > 100 || cleanMessage.length > 1000) {
            return WhatsAppResult(
                success = false,
                status = "INVALID_REQUEST",
                errorMessage = "Contact name or message too long."
            )
        }

        // 2. Check WhatsApp installed (optimization: fail early)
        if (!isWhatsAppInstalled()) {
            return WhatsAppResult(
                success = false,
                status = "WHATSAPP_NOT_INSTALLED",
                errorMessage = "WhatsApp is not installed on this device."
            )
        }

        // 3. Resolve contact name -> phone number
        val contact = resolveContact(cleanName)
            ?: return WhatsAppResult(
                success = false,
                status = "CONTACT_NOT_FOUND",
                errorMessage = "Contact \"$cleanName\" not found."
            )

        if (contact.phone == null || contact.phone.isBlank()) {
            return WhatsAppResult(
                success = false,
                status = "CONTACT_HAS_NO_PHONE",
                errorMessage = "Contact \"${contact.displayName}\" has no phone number."
            )
        }

        val sanitizedPhone = sanitizePhone(contact.phone)
        if (sanitizedPhone.isBlank()) {
            return WhatsAppResult(
                success = false,
                status = "CONTACT_HAS_NO_PHONE",
                errorMessage = "Contact \"${contact.displayName}\" has an invalid phone number."
            )
        }

        // 4. Launch WhatsApp via wa.me (official universal link)
        // Using Intent.ACTION_VIEW with https://wa.me/<phone>?text=...
        // Alternative is whatsapp://send but wa.me is more reliable.
        return try {
            val encodedMessage = Uri.encode(cleanMessage)
            val uri = Uri.parse("https://wa.me/$sanitizedPhone?text=$encodedMessage")
            val intent = Intent(Intent.ACTION_VIEW, uri).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                // Try to restrict to WhatsApp if possible, but don't setPackage strictly
                // because wa.me may be handled by browser fallback. Check both.
            }

            // Prefer WhatsApp package if it can handle the intent
            val whatsappIntent = Intent(Intent.ACTION_VIEW, uri).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                `package` = "com.whatsapp"
            }
            val canHandleWhatsApp = context.packageManager.resolveActivity(
                whatsappIntent, PackageManager.MATCH_DEFAULT_ONLY
            ) != null

            val finalIntent = if (canHandleWhatsApp) {
                whatsappIntent
            } else {
                // Try WhatsApp Business
                val businessIntent = Intent(Intent.ACTION_VIEW, uri).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    `package` = "com.whatsapp.w4b"
                }
                val canHandleBusiness = context.packageManager.resolveActivity(
                    businessIntent, PackageManager.MATCH_DEFAULT_ONLY
                ) != null
                if (canHandleBusiness) businessIntent else intent
            }

            context.startActivity(finalIntent)

            WhatsAppResult(
                success = true,
                status = "SUCCESS",
                resolvedPhone = sanitizedPhone,
                resolvedName = contact.displayName
            )
        } catch (e: Exception) {
            WhatsAppResult(
                success = false,
                status = "LAUNCH_FAILED",
                errorMessage = e.localizedMessage ?: "Failed to open WhatsApp."
            )
        }
    }

    private fun isWhatsAppInstalled(): Boolean {
        val pm = context.packageManager
        return try {
            pm.getPackageInfo("com.whatsapp", 0)
            true
        } catch (_: Exception) {
            try {
                pm.getPackageInfo("com.whatsapp.w4b", 0)
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    private data class ContactInfo(val displayName: String, val phone: String?)

    private fun resolveContact(target: String): ContactInfo? {
        val normalizedTarget = target.filter { it.isLetterOrDigit() }.lowercase()

        var best: ContactInfo? = null
        var bestScore = -1

        // Query contacts with phone numbers
        // We do a fuzzy in-memory scoring similar to AppLauncher.kt
        val projection = arrayOf(
            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
            ContactsContract.CommonDataKinds.Phone.NUMBER,
            ContactsContract.CommonDataKinds.Phone.CONTACT_ID
        )

        var cursor: Cursor? = null
        try {
            cursor = context.contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                projection,
                null,
                null,
                null
            ) ?: return null

            // Use a map to avoid duplicate contacts: keep best scoring number per contact id
            val seenIds = mutableMapOf<String, ContactInfo>()

            val nameIndex = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
            val numberIndex = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
            val idIndex = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.CONTACT_ID)

            if (nameIndex == -1 || numberIndex == -1) return null

            while (cursor.moveToNext()) {
                val displayName = cursor.getString(nameIndex) ?: continue
                val phone = cursor.getString(numberIndex)
                val contactId = if (idIndex != -1) cursor.getString(idIndex) else displayName

                val nameClean = displayName.trim()
                if (nameClean.isEmpty()) continue

                val nameNormalized = nameClean.filter { it.isLetterOrDigit() }.lowercase()

                var score = 0
                when {
                    nameClean.equals(target, ignoreCase = true) -> score = 100
                    nameNormalized == normalizedTarget -> score = 95
                    nameClean.lowercase().startsWith(target.lowercase()) -> score = 85
                    target.lowercase().startsWith(nameClean.lowercase()) -> score = 80
                    nameNormalized.contains(normalizedTarget) -> score = 75
                    normalizedTarget.contains(nameNormalized) -> score = 70
                    // Word-level match: e.g. "Mom" vs "Mom (Home)"
                    nameClean.split(Regex("\\s+")).any { it.equals(target, ignoreCase = true) } -> score = 60
                }

                // Fix 1: Levenshtein fuzzy fallback for STT mishearing (e.g. Rahul vs Rahool)
                if (score == 0) {
                    // Full normalized edit distance
                    val distFull = levenshtein(normalizedTarget, nameNormalized)
                    val maxLenFull = maxOf(normalizedTarget.length, nameNormalized.length)
                    if (maxLenFull > 0) {
                        val firstCharMatch = normalizedTarget.isNotEmpty() && nameNormalized.isNotEmpty() && normalizedTarget[0] == nameNormalized[0]
                        score = when {
                            // Short names (4 chars like "Mom " edge): only 1 typo allowed and first char must match. 3-char names disallow fuzzy to avoid Tom<->Mom collisions.
                            maxLenFull == 4 && distFull == 1 && firstCharMatch -> 62
                            maxLenFull in 5..6 && distFull == 1 -> 74
                            maxLenFull in 5..6 && distFull == 2 -> 68
                            maxLenFull >= 7 && distFull == 1 -> 74
                            maxLenFull >= 7 && distFull == 2 -> 68
                            maxLenFull >= 7 && distFull == 3 -> 62
                            else -> 0
                        }
                    }
                    // Word-level Levenshtein: handle "Rahool" vs "Rahul Sharma" where
                    // full string dist is larger but one token matches closely
                    if (score == 0) {
                        val nameWords = nameClean.split(Regex("\\s+"))
                        var bestWordScore = 0
                        for (nw in nameWords) {
                            val nwNorm = nw.filter { it.isLetterOrDigit() }.lowercase()
                            if (nwNorm.isEmpty()) continue
                            // Compare target as single token or each word of target
                            // 1) whole normalizedTarget vs this word
                            val distSingle = levenshtein(normalizedTarget, nwNorm)
                            val maxLenSingle = maxOf(normalizedTarget.length, nwNorm.length)
                            val firstMatchSingle = normalizedTarget.isNotEmpty() && nwNorm.isNotEmpty() && normalizedTarget[0] == nwNorm[0]
                            val s1 = when {
                                maxLenSingle == 4 && distSingle == 1 && firstMatchSingle -> 60
                                maxLenSingle in 5..6 && distSingle == 1 -> 68
                                maxLenSingle in 5..6 && distSingle == 2 -> 60
                                maxLenSingle >= 7 && distSingle == 1 -> 68
                                maxLenSingle >= 7 && distSingle == 2 -> 62
                                maxLenSingle >= 7 && distSingle == 3 -> 60
                                else -> 0
                            }
                            if (s1 > bestWordScore) bestWordScore = s1
                            // 2) each word of target vs this word (for multi-word targets like "Amit Sarma" vs "Amit Sharma")
                            val targetWords = target.split(Regex("\\s+"))
                            for (tw in targetWords) {
                                val twNorm = tw.filter { it.isLetterOrDigit() }.lowercase()
                                if (twNorm.isEmpty()) continue
                                val d = levenshtein(twNorm, nwNorm)
                                val ml = maxOf(twNorm.length, nwNorm.length)
                                val firstMatchWord = twNorm.isNotEmpty() && nwNorm.isNotEmpty() && twNorm[0] == nwNorm[0]
                                val s2 = when {
                                    ml == 4 && d == 1 && firstMatchWord -> 60
                                    ml in 5..6 && d == 1 -> 68
                                    ml in 5..6 && d == 2 -> 60
                                    ml >= 7 && d == 1 -> 68
                                    ml >= 7 && d == 2 -> 62
                                    ml >= 7 && d == 3 -> 60
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
                    best = ContactInfo(displayName = nameClean, phone = phone)
                }

                // Also keep distinct ids for tie-breaking debug, not needed otherwise
                if (contactId != null && score > 0) {
                    val existing = seenIds[contactId]
                    if (existing == null || score > (existing.phone?.let { 50 } ?: 0)) {
                        // just track, best already holds global best
                    }
                }
            }
        } catch (e: SecurityException) {
            // Permission not granted
            return null
        } catch (_: Exception) {
            return null
        } finally {
            cursor?.close()
        }

        if (bestScore < 60 || best == null) return null
        return best
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
                    prev[j] + 1,      // deletion
                    curr[j - 1] + 1,  // insertion
                    prev[j - 1] + cost // substitution
                )
            }
            // copy curr into prev for next row
            for (j in 0..b.length) prev[j] = curr[j]
        }
        return prev[b.length]
    }

    private fun sanitizePhone(raw: String): String {
        // Keep only digits and leading +, WhatsApp wa.me expects digits without spaces/dashes.
        // wa.me requires country code, but many contacts already have it.
        // We strip everything except digits, keeping + removed for wa.me format.
        // wa.me example: https://wa.me/15551234567
        val trimmed = raw.trim()
        // If starts with +, keep digits after
        // Remove all non-digits
        val digits = trimmed.filter { it.isDigit() }
        return digits
    }
}
