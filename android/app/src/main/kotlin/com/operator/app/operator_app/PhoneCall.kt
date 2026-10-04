package com.operator.app.operator_app

import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.provider.ContactsContract

class PhoneCall(private val context: Context) {

    data class CallResult(
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
     * Resolves [contactName] (or a raw phone number) and places a direct
     * phone call with ACTION_CALL (requires CALL_PHONE permission, checked
     * by MainActivity before invoking).
     */
    fun makeCall(contactName: String?): CallResult {
        if (contactName.isNullOrBlank()) {
            return CallResult(
                success = false,
                status = "INVALID_REQUEST",
                errorMessage = "Contact name must not be empty."
            )
        }

        val cleanName = contactName.trim()
        if (cleanName.length > 100) {
            return CallResult(
                success = false,
                status = "INVALID_REQUEST",
                errorMessage = "Contact name too long."
            )
        }

        // 1. Direct number: "call 9876543210" skips contact lookup.
        val directPhone = sanitizePhone(cleanName)
        if (isRawPhoneNumber(cleanName) && directPhone.length >= 7) {
            return launchCall(directPhone, cleanName)
        }

        // 2. Resolve contact name -> phone number.
        val contact = resolveContact(cleanName)
            ?: return CallResult(
                success = false,
                status = "CONTACT_NOT_FOUND",
                errorMessage = "Contact \"$cleanName\" not found."
            )

        if (contact.phone.isNullOrBlank()) {
            return CallResult(
                success = false,
                status = "CONTACT_HAS_NO_PHONE",
                errorMessage = "Contact \"${contact.displayName}\" has no phone number."
            )
        }

        val sanitizedPhone = sanitizePhone(contact.phone!!)
        if (sanitizedPhone.length < 7) {
            return CallResult(
                success = false,
                status = "CONTACT_HAS_NO_PHONE",
                errorMessage = "Contact \"${contact.displayName}\" has an invalid phone number."
            )
        }

        return launchCall(sanitizedPhone, contact.displayName)
    }

    private fun launchCall(sanitizedPhone: String, displayName: String): CallResult {
        return try {
            val uri = Uri.parse("tel:$sanitizedPhone")
            val intent = Intent(Intent.ACTION_CALL, uri).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            CallResult(
                success = true,
                status = "SUCCESS",
                resolvedPhone = sanitizedPhone,
                resolvedName = displayName
            )
        } catch (e: SecurityException) {
            CallResult(
                success = false,
                status = "PERMISSION_DENIED",
                errorMessage = e.localizedMessage ?: "Phone permission is required to place calls."
            )
        } catch (e: Exception) {
            CallResult(
                success = false,
                status = "CALL_FAILED",
                errorMessage = e.localizedMessage ?: "Failed to place the call."
            )
        }
    }

    private fun isRawPhoneNumber(raw: String): Boolean {
        val t = raw.trim()
        if (t.length < 7 || t.length > 20) return false
        // Must be mostly digits/+, spaces, dashes, parens.
        if (!Regex("^[+\\d][\\d\\s\\-()]{5,19}$").matches(t)) return false
        return t.filter { it.isDigit() }.length >= 7
    }

    private data class ContactInfo(val displayName: String, val phone: String?)

    private fun resolveContact(target: String): ContactInfo? {
        val normalizedTarget = target.filter { it.isLetterOrDigit() }.lowercase()

        var best: ContactInfo? = null
        var bestScore = -1

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

            val nameIndex = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
            val numberIndex = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)

            if (nameIndex == -1 || numberIndex == -1) return null

            while (cursor.moveToNext()) {
                val displayName = cursor.getString(nameIndex) ?: continue
                val phone = cursor.getString(numberIndex)

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
                    nameClean.split(Regex("\\s+")).any { it.equals(target, ignoreCase = true) } -> score = 60
                }

                if (score == 0) {
                    val distFull = levenshtein(normalizedTarget, nameNormalized)
                    val maxLenFull = maxOf(normalizedTarget.length, nameNormalized.length)
                    if (maxLenFull > 0) {
                        val firstCharMatch = normalizedTarget.isNotEmpty() && nameNormalized.isNotEmpty() && normalizedTarget[0] == nameNormalized[0]
                        score = when {
                            maxLenFull == 4 && distFull == 1 && firstCharMatch -> 62
                            maxLenFull in 5..6 && distFull == 1 -> 74
                            maxLenFull in 5..6 && distFull == 2 -> 68
                            maxLenFull >= 7 && distFull == 1 -> 74
                            maxLenFull >= 7 && distFull == 2 -> 68
                            maxLenFull >= 7 && distFull == 3 -> 62
                            else -> 0
                        }
                    }
                    if (score == 0) {
                        val nameWords = nameClean.split(Regex("\\s+"))
                        var bestWordScore = 0
                        for (nw in nameWords) {
                            val nwNorm = nw.filter { it.isLetterOrDigit() }.lowercase()
                            if (nwNorm.isEmpty()) continue
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
                        }
                        if (bestWordScore > score) score = bestWordScore
                    }
                }

                if (score > bestScore) {
                    bestScore = score
                    best = ContactInfo(displayName = nameClean, phone = phone)
                }
            }
        } catch (e: SecurityException) {
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
                    prev[j] + 1,
                    curr[j - 1] + 1,
                    prev[j - 1] + cost
                )
            }
            for (j in 0..b.length) prev[j] = curr[j]
        }
        return prev[b.length]
    }

    private fun sanitizePhone(raw: String): String {
        val trimmed = raw.trim()
        val digits = trimmed.filter { it.isDigit() }
        // Preserve leading + for tel: URIs when present.
        return if (trimmed.startsWith("+") && digits.isNotEmpty()) "+$digits" else digits
    }
}
