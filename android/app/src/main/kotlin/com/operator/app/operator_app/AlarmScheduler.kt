package com.operator.app.operator_app

import android.Manifest
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.AlarmClock
import android.provider.CalendarContract
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.TimeZone

/**
 * Schedules exact one-shot alarms & reminders via [AlarmManager].
 *
 * All items persist in SharedPreferences so they survive process death and
 * are rescheduled after reboot ([AlarmBootReceiver]). Times are exchanged
 * with Flutter as epoch millis; parsing happens in Dart (offline regex),
 * so this layer stays thin and fast.
 */
class AlarmScheduler(private val context: Context) {

    companion object {
        const val ACTION_FIRE = "com.operator.app.operator_app.ALARM_FIRE"
        const val PREFS = "friday_alarms"
        const val KEY_ITEMS = "items"
        const val CHANNEL_ID = "friday_alarms"

        fun triggerIntent(
            context: Context,
            id: Int,
            kind: String,
            label: String
        ): PendingIntent {
            val intent = Intent(context, AlarmReceiver::class.java).apply {
                action = ACTION_FIRE
                putExtra("id", id)
                putExtra("kind", kind)
                putExtra("label", label)
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_IMMUTABLE
                } else 0)
            return PendingIntent.getBroadcast(context, id, intent, flags)
        }
    }

    data class AlarmResult(
        val success: Boolean,
        val id: Int = 0,
        val kind: String = "alarm",
        val triggerAtMillis: Long = 0L,
        val label: String = "",
        val errorMessage: String? = null
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "success" to success,
            "id" to id,
            "kind" to kind,
            "triggerAtMillis" to triggerAtMillis,
            "label" to label,
            "errorMessage" to errorMessage
        )
    }

    fun setAlarm(
        triggerAtMillis: Long?,
        label: String?,
        kind: String?
    ): AlarmResult {
        val now = System.currentTimeMillis()
        if (triggerAtMillis == null || triggerAtMillis <= now) {
            return AlarmResult(
                success = false,
                errorMessage = "That time has already passed."
            )
        }
        // Cap: max 1 year ahead (AlarmManager long-delay guard).
        if (triggerAtMillis - now > 366L * 24 * 60 * 60 * 1000) {
            return AlarmResult(
                success = false,
                errorMessage = "That time is too far in the future."
            )
        }
        val cleanKind = if (kind == "reminder") "reminder" else "alarm"
        val cleanLabel = (label ?: "").trim().take(200)
        val id = ((triggerAtMillis % Int.MAX_VALUE).toInt() xor
            (now % Int.MAX_VALUE).toInt() xor
            (Math.random() * Int.MAX_VALUE).toInt())
            .let { if (it == 0) 1 else Math.abs(it) }

        val item = JSONObject().apply {
            put("id", id)
            put("kind", cleanKind)
            put("triggerAtMillis", triggerAtMillis)
            put("label", cleanLabel)
        }

        if (cleanKind == "alarm") {
            val systemSuccess = setSystemAlarm(triggerAtMillis, cleanLabel)
            if (systemSuccess) {
                item.put("systemAlarm", true)
            } else {
                // Fallback to exact in-app notification if system clock intent is unavailable
                scheduleExact(id, triggerAtMillis, cleanKind, cleanLabel)
            }
        } else {
            // Option C: Real Reminders via Android System Calendar (Google/Samsung Calendar)
            val calEventId = insertCalendarEvent(triggerAtMillis, cleanLabel)
            if (calEventId != null && calEventId > 0) {
                item.put("systemCalendar", true)
                item.put("calendarEventId", calEventId)
            } else {
                // Fallback to exact in-app notification if calendar sync is unavailable/unpermitted
                scheduleExact(id, triggerAtMillis, cleanKind, cleanLabel)
            }
        }

        saveItem(item)
        return AlarmResult(
            success = true,
            id = id,
            kind = cleanKind,
            triggerAtMillis = triggerAtMillis,
            label = cleanLabel
        )
    }

    fun listAlarms(): List<Map<String, Any?>> {
        prunePast()
        return loadItems().map { o ->
            mapOf(
                "id" to o.optInt("id"),
                "kind" to o.optString("kind", "alarm"),
                "triggerAtMillis" to o.optLong("triggerAtMillis"),
                "label" to o.optString("label", "")
            )
        }.sortedBy { (it["triggerAtMillis"] as? Long) ?: 0L }
    }

    /**
     * Cancels matching items. Empty [query] cancels everything.
     * Otherwise matches label substring or clock-time text ("7am", "7:30").
     */
    fun cancelAlarm(query: String?): Map<String, Any?> {
        val items = loadItems()
        if (items.isEmpty()) {
            return mapOf("success" to true, "cancelled" to 0)
        }
        val q = (query ?: "").trim().lowercase()
        val toCancel = if (q.isEmpty()) {
            items
        } else {
            items.filter { matchesQuery(it, q) }
        }
        val manager =
            context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (o in toCancel) {
            // Cancel in-app PendingIntent if one was armed
            try {
                val pi = triggerIntent(
                    context,
                    o.optInt("id"),
                    o.optString("kind", "alarm"),
                    o.optString("label", "")
                )
                manager.cancel(pi)
                pi.cancel()
            } catch (_: Exception) {}

            // Delete from system Calendar if created there
            val calEventId = o.optLong("calendarEventId", 0L)
            if (calEventId > 0) {
                deleteCalendarEvent(calEventId)
            }

            // Dismiss from system Clock app if set there
            if (o.optBoolean("systemAlarm", false)) {
                dismissSystemAlarm(o)
            }
        }

        // If query is empty and on Android 6.0+, also attempt system Clock dismiss all
        if (q.isEmpty() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val dismissAllIntent = Intent(AlarmClock.ACTION_DISMISS_ALARM).apply {
                    putExtra(AlarmClock.EXTRA_ALARM_SEARCH_MODE, AlarmClock.ALARM_SEARCH_MODE_ALL)
                    putExtra(AlarmClock.EXTRA_SKIP_UI, true)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                if (dismissAllIntent.resolveActivity(context.packageManager) != null) {
                    context.startActivity(dismissAllIntent)
                }
            } catch (_: Exception) {}
        }

        val remaining = items.filter { !toCancel.contains(it) }
        persist(remaining)
        return mapOf("success" to true, "cancelled" to toCancel.size)
    }

    /** Re-schedules all future items (called after reboot). */
    fun rescheduleAll() {
        prunePast()
        for (o in loadItems()) {
            // Real system alarms & calendar events persist natively across reboots
            if (o.optBoolean("systemAlarm", false) || o.optBoolean("systemCalendar", false)) {
                continue
            }
            try {
                scheduleExact(
                    o.optInt("id"),
                    o.optLong("triggerAtMillis"),
                    o.optString("kind", "alarm"),
                    o.optString("label", "")
                )
            } catch (_: Exception) {}
        }
    }

    /** Removes the item with [id] after it fires (one-shot). */
    fun removeById(id: Int) {
        persist(loadItems().filter { it.optInt("id") != id })
    }

    // -- System Clock & Calendar integrations -------------------------------

    /**
     * Option B: Sets a real alarm in the user's default system Clock app
     * (Google Clock, Samsung Clock, etc.) using [AlarmClock.ACTION_SET_ALARM].
     */
    private fun setSystemAlarm(
        triggerAtMillis: Long,
        label: String
    ): Boolean {
        val cal = Calendar.getInstance().apply { timeInMillis = triggerAtMillis }
        val hour = cal.get(Calendar.HOUR_OF_DAY)
        val minute = cal.get(Calendar.MINUTE)

        val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
            putExtra(AlarmClock.EXTRA_HOUR, hour)
            putExtra(AlarmClock.EXTRA_MINUTES, minute)
            putExtra(AlarmClock.EXTRA_MESSAGE, label.ifBlank { "Alarm" })
            putExtra(AlarmClock.EXTRA_SKIP_UI, true)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        val now = System.currentTimeMillis()
        if (triggerAtMillis - now > 24 * 60 * 60 * 1000L) {
            val dayOfWeek = cal.get(Calendar.DAY_OF_WEEK)
            intent.putExtra(AlarmClock.EXTRA_DAYS, arrayListOf(dayOfWeek))
        }

        return try {
            if (intent.resolveActivity(context.packageManager) != null) {
                context.startActivity(intent)
                true
            } else {
                false
            }
        } catch (_: Exception) {
            // Some OEM ROMs enforce showing the Clock UI
            try {
                intent.putExtra(AlarmClock.EXTRA_SKIP_UI, false)
                if (intent.resolveActivity(context.packageManager) != null) {
                    context.startActivity(intent)
                    true
                } else {
                    false
                }
            } catch (_: Exception) {
                false
            }
        }
    }

    /**
     * Dismisses a matching alarm in the stock Clock app.
     */
    private fun dismissSystemAlarm(item: JSONObject) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val trigger = item.optLong("triggerAtMillis")
        val cal = Calendar.getInstance().apply { timeInMillis = trigger }
        val hour = cal.get(Calendar.HOUR_OF_DAY)
        val minute = cal.get(Calendar.MINUTE)

        val intent = Intent(AlarmClock.ACTION_DISMISS_ALARM).apply {
            putExtra(AlarmClock.EXTRA_ALARM_SEARCH_MODE, AlarmClock.ALARM_SEARCH_MODE_TIME)
            putExtra(AlarmClock.EXTRA_HOUR, hour)
            putExtra(AlarmClock.EXTRA_MINUTES, minute)
            putExtra(AlarmClock.EXTRA_SKIP_UI, true)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            if (intent.resolveActivity(context.packageManager) != null) {
                context.startActivity(intent)
            }
        } catch (_: Exception) {}
    }

    /**
     * Finds a writable calendar ID (prefers primary calendar).
     */
    private fun getWritableCalendarId(): Long? {
        val uri = CalendarContract.Calendars.CONTENT_URI
        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.VISIBLE,
            CalendarContract.Calendars.IS_PRIMARY
        )
        try {
            context.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                val idIdx = cursor.getColumnIndex(CalendarContract.Calendars._ID)
                val primaryIdx = cursor.getColumnIndex(CalendarContract.Calendars.IS_PRIMARY)
                val visibleIdx = cursor.getColumnIndex(CalendarContract.Calendars.VISIBLE)

                var fallbackId: Long? = null
                while (cursor.moveToNext()) {
                    val id = cursor.getLong(idIdx)
                    if (fallbackId == null) fallbackId = id
                    val isPrimary = if (primaryIdx >= 0) cursor.getInt(primaryIdx) == 1 else false
                    val isVisible = if (visibleIdx >= 0) cursor.getInt(visibleIdx) == 1 else false
                    if (isPrimary) {
                        return id
                    }
                    if (isVisible && fallbackId == null) {
                        fallbackId = id
                    }
                }
                return fallbackId
            }
        } catch (_: Exception) {}
        return null
    }

    /**
     * Option C: Inserts a reminder into the device's system Calendar
     * (Google Calendar / Samsung Calendar) with an exact-time alert notification.
     */
    private fun insertCalendarEvent(
        triggerAtMillis: Long,
        title: String
    ): Long? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (context.checkSelfPermission(Manifest.permission.WRITE_CALENDAR) != PackageManager.PERMISSION_GRANTED) {
                return null
            }
        }
        val calId = getWritableCalendarId() ?: return null

        val startMillis = triggerAtMillis
        val endMillis = triggerAtMillis + (15 * 60 * 1000)
        val timeZone = TimeZone.getDefault().id

        val eventValues = ContentValues().apply {
            put(CalendarContract.Events.CALENDAR_ID, calId)
            put(CalendarContract.Events.TITLE, title.ifBlank { "Reminder" })
            put(CalendarContract.Events.DESCRIPTION, "Reminder set by FRIDAY")
            put(CalendarContract.Events.DTSTART, startMillis)
            put(CalendarContract.Events.DTEND, endMillis)
            put(CalendarContract.Events.EVENT_TIMEZONE, timeZone)
            put(CalendarContract.Events.HAS_ALARM, 1)
        }

        val eventUri = try {
            context.contentResolver.insert(CalendarContract.Events.CONTENT_URI, eventValues)
        } catch (_: Exception) {
            null
        } ?: return null

        val eventId = eventUri.lastPathSegment?.toLongOrNull() ?: return null

        // Add 0-minute reminder (exact time alert)
        try {
            val reminderValues = ContentValues().apply {
                put(CalendarContract.Reminders.EVENT_ID, eventId)
                put(CalendarContract.Reminders.MINUTES, 0)
                put(CalendarContract.Reminders.METHOD, CalendarContract.Reminders.METHOD_ALERT)
            }
            context.contentResolver.insert(CalendarContract.Reminders.CONTENT_URI, reminderValues)
        } catch (_: Exception) {}

        return eventId
    }

    /**
     * Deletes a reminder event from the system Calendar.
     */
    private fun deleteCalendarEvent(eventId: Long): Boolean {
        if (eventId <= 0) return false
        return try {
            val uri = ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, eventId)
            context.contentResolver.delete(uri, null, null) > 0
        } catch (_: Exception) {
            false
        }
    }

    // -- internals ----------------------------------------------------------

    private fun scheduleExact(
        id: Int,
        triggerAtMillis: Long,
        kind: String,
        label: String
    ) {
        val manager =
            context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = triggerIntent(context, id, kind, label)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                manager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMillis,
                    pi
                )
            } else {
                @Suppress("DEPRECATION")
                manager.setExact(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMillis,
                    pi
                )
            }
        } catch (_: SecurityException) {
            // Exact-alarm permission denied (Android 12+): fall back to
            // inexact — still fires, just not at the exact second.
            manager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAtMillis,
                pi
            )
        }
    }

    private fun matchesQuery(item: JSONObject, q: String): Boolean {
        val label = item.optString("label", "").lowercase()
        if (label.isNotEmpty() && (label.contains(q) || q.contains(label))) {
            return true
        }
        val kind = item.optString("kind", "alarm").lowercase()
        if (q == kind || q == "${kind}s") return true

        // Time-text matching: "7am", "7:30 pm", "19:30", "7".
        val trigger = item.optLong("triggerAtMillis")
        val cal = Calendar.getInstance().apply { timeInMillis = trigger }
        val hour24 = cal.get(Calendar.HOUR_OF_DAY)
        val minute = cal.get(Calendar.MINUTE)
        val hour12 = if (hour24 % 12 == 0) 12 else hour24 % 12
        val isPm = hour24 >= 12

        val timeMatch = Regex(
            """\b(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?\b"""
        ).find(q) ?: return false
        val qHour = timeMatch.groupValues[1].toIntOrNull() ?: return false
        val qMin = timeMatch.groupValues[2].takeIf { it.isNotEmpty() }?.toIntOrNull()
        val qMer = timeMatch.groupValues[3].lowercase()
            .replace(".", "").replace(" ", "")

        if (qMer == "am" || qMer == "pm") {
            val wantPm = qMer == "pm"
            if (wantPm != isPm) return false
            if (qHour != hour12) return false
        } else {
            // No meridiem: match 12h or 24h hour.
            if (qHour != hour12 && qHour != hour24) return false
        }
        if (qMin != null && qMin != minute) return false
        return true
    }

    private fun loadItems(): MutableList<JSONObject> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_ITEMS, "[]") ?: "[]"
        val out = mutableListOf<JSONObject>()
        try {
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                if (o.optLong("triggerAtMillis", 0L) > 0) out.add(o)
            }
        } catch (_: Exception) {}
        return out
    }

    private fun persist(items: List<JSONObject>) {
        val arr = JSONArray()
        for (o in items) arr.put(o)
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_ITEMS, arr.toString())
            .apply()
    }

    private fun saveItem(item: JSONObject) {
        val items = loadItems()
        items.add(item)
        // Cap stored items so prefs never grow unbounded.
        val capped = items.sortedBy { it.optLong("triggerAtMillis") }.takeLast(50)
        persist(capped)
    }

    private fun prunePast() {
        val now = System.currentTimeMillis()
        // Keep a 2-minute grace so just-fired items still list correctly.
        persist(loadItems().filter { it.optLong("triggerAtMillis") > now - 2 * 60 * 1000 })
    }
}
