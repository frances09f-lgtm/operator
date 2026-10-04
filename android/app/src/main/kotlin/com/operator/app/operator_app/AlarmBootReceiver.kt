package com.operator.app.operator_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Reschedules future alarms/reminders after a reboot (AlarmManager does not
 * persist across reboots, so FRIDAY re-arms everything it stored).
 */
class AlarmBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != "android.intent.action.QUICKBOOT_POWERON" &&
            action != Intent.ACTION_LOCKED_BOOT_COMPLETED
        ) {
            return
        }
        try {
            AlarmScheduler(context.applicationContext).rescheduleAll()
        } catch (_: Exception) {}
    }
}
