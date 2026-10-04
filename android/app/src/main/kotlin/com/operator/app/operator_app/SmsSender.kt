package com.operator.app.operator_app

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.provider.ContactsContract
import android.telephony.SmsManager

class SmsSender(private val context: Context) {

    data class SmsResult(
        val success: Boolean,
        val status: String,
        val resolvedPhone: String? = null,
        val resolvedName: String? = null,
        val isDirectSend: Boolean = false,
        val errorMessage: String? = null
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "success" to success,
            "status" to status,
            "resolvedPhone" to resolvedPhone,
            "resolvedName" to resolvedName,
            "isDirectSend" to isDirectSend,
            "errorMessage" to errorMessage
        )
    }

    private val FO_PHONE = "+16289985940"

    fun sendSms(recipient: String?, message: String?, explicitPhone: String? = null): SmsResult {
        if (recipient.isNullOrBlank() || message.isNullOrBlank()) {
            return SmsResult(
                success = false,
                status = "INVALID_REQUEST",
                errorMessage = "Recipient and message must not be empty."
            )
        }

        val cleanRecipient = recipient.trim()
        val cleanMessage = message.trim()

        // 1. Resolve phone number
        val resolvedPhone: String
        val resolvedName: String

        if (!explicitPhone.isNullOrBlank()) {
            resolvedPhone = explicitPhone.trim()
            resolvedName = cleanRecipient
        } else if (cleanRecipient.equals("FO", ignoreCase = true) ||
            cleanRecipient.equals("wajo", ignoreCase = true) ||
            cleanRecipient.equals("wajo fo", ignoreCase = true)
        ) {
            resolvedPhone = FO_PHONE
            resolvedName = "FO"
        } else if (isRawPhoneNumber(cleanRecipient)) {
            resolvedPhone = cleanRecipient
            resolvedName = cleanRecipient
        } else {
            val contact = resolveContact(cleanRecipient)
            if (contact == null) {
                return SmsResult(
                    success = false,
                    status = "CONTACT_NOT_FOUND",
                    errorMessage = "Contact \"$cleanRecipient\" not found."
                )
            }
            if (contact.phone.isNullOrBlank()) {
                return SmsResult(
                    success = false,
                    status = "CONTACT_HAS_NO_PHONE",
                    errorMessage = "Contact \"${contact.displayName}\" has no phone number."
                )
            }
            resolvedPhone = contact.phone
            resolvedName = contact.displayName
        }

        // 2. Try sending directly via SmsManager if SEND_SMS permission is granted
        val hasSendSmsPerm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            context.checkSelfPermission(Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }

        if (hasSendSmsPerm) {
            try {
                val smsManager: SmsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    context.getSystemService(SmsManager::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    SmsManager.getDefault()
                }

                val parts = smsManager.divideMessage(cleanMessage)
                if (parts.size > 1) {
                    smsManager.sendMultipartTextMessage(resolvedPhone, null, parts, null, null)
                } else {
                    smsManager.sendTextMessage(resolvedPhone, null, cleanMessage, null, null)
                }

                return SmsResult(
                    success = true,
                    status = "SENT_DIRECT",
                    resolvedPhone = resolvedPhone,
                    resolvedName = resolvedName,
                    isDirectSend = true
                )
            } catch (e: Exception) {
                // If direct SMS fails, fallback to opening the Messages app intent
            }
        }

        // 3. Fallback: Launch default SMS/Messages app via Intent
        return try {
            val uri = Uri.parse("smsto:${Uri.encode(resolvedPhone)}")
            val intent = Intent(Intent.ACTION_SENDTO, uri).apply {
                putExtra("sms_body", cleanMessage)
                putExtra(Intent.EXTRA_TEXT, cleanMessage)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            SmsResult(
                success = true,
                status = "OPENED_APP",
                resolvedPhone = resolvedPhone,
                resolvedName = resolvedName,
                isDirectSend = false
            )
        } catch (e: Exception) {
            SmsResult(
                success = false,
                status = "LAUNCH_FAILED",
                resolvedPhone = resolvedPhone,
                resolvedName = resolvedName,
                errorMessage = e.localizedMessage ?: "Failed to open messages app."
            )
        }
    }

    private fun isRawPhoneNumber(s: String): Boolean {
        val digitsAndPlus = s.replace(Regex("[^0-9+]"), "")
        return digitsAndPlus.length >= 7 && (s.startsWith("+") || s.matches(Regex("^[0-9\\-\\s\\(\\)]+$")))
    }

    data class ContactRecord(val displayName: String, val phone: String?)

    private fun resolveContact(query: String): ContactRecord? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            context.checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED
        ) {
            return null
        }

        val uri = Uri.withAppendedPath(
            ContactsContract.Contacts.CONTENT_FILTER_URI,
            Uri.encode(query)
        )
        val projection = arrayOf(
            ContactsContract.Contacts._ID,
            ContactsContract.Contacts.DISPLAY_NAME,
            ContactsContract.Contacts.HAS_PHONE_NUMBER
        )

        var cursor: Cursor? = null
        try {
            cursor = context.contentResolver.query(uri, projection, null, null, null)
            if (cursor == null || !cursor.moveToFirst()) return null

            val idIdx = cursor.getColumnIndex(ContactsContract.Contacts._ID)
            val nameIdx = cursor.getColumnIndex(ContactsContract.Contacts.DISPLAY_NAME)
            val hasPhoneIdx = cursor.getColumnIndex(ContactsContract.Contacts.HAS_PHONE_NUMBER)

            val id = if (idIdx >= 0) cursor.getString(idIdx) else null ?: return null
            val displayName = if (nameIdx >= 0) cursor.getString(nameIdx) ?: query else query
            val hasPhone = if (hasPhoneIdx >= 0) cursor.getInt(hasPhoneIdx) > 0 else false

            if (!hasPhone) {
                return ContactRecord(displayName, null)
            }

            val phone = fetchPhoneNumber(id)
            return ContactRecord(displayName, phone)
        } catch (_: Exception) {
            return null
        } finally {
            cursor?.close()
        }
    }

    private fun fetchPhoneNumber(contactId: String): String? {
        val phoneUri = ContactsContract.CommonDataKinds.Phone.CONTENT_URI
        val projection = arrayOf(
            ContactsContract.CommonDataKinds.Phone.NUMBER,
            ContactsContract.CommonDataKinds.Phone.IS_PRIMARY
        )
        val selection = "${ContactsContract.CommonDataKinds.Phone.CONTACT_ID} = ?"
        val selectionArgs = arrayOf(contactId)
        val sortOrder = "${ContactsContract.CommonDataKinds.Phone.IS_PRIMARY} DESC"

        var cursor: Cursor? = null
        try {
            cursor = context.contentResolver.query(
                phoneUri,
                projection,
                selection,
                selectionArgs,
                sortOrder
            )
            if (cursor != null && cursor.moveToFirst()) {
                val numIdx = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
                if (numIdx >= 0) {
                    return cursor.getString(numIdx)
                }
            }
        } catch (_: Exception) {
        } finally {
            cursor?.close()
        }
        return null
    }
}
