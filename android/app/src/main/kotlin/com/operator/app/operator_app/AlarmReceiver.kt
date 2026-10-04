package com.operator.app.operator_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

/**
 * Fires when an [AlarmScheduler] alarm/reminder goes off.
 *
 * Shows a high-priority notification with the system alarm sound +
 * vibration, then drops the one-shot item so listings stay accurate.
 */
class AlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != AlarmScheduler.ACTION_FIRE &&
            intent.action != "android.intent.action.BOOT_COMPLETED") {
            // Still handle explicit fires without action (defensive).
        }
        val id = intent.getIntExtra("id", 0)
        val kind = intent.getStringExtra("kind") ?: "alarm"
        val label = intent.getStringExtra("label") ?: ""

        try {
            AlarmScheduler(context).removeById(id)
        } catch (_: Exception) {}

        val title = if (kind == "reminder") "Reminder" else "Alarm"
        val body = when {
            label.isNotBlank() -> label
            kind == "reminder" -> "Time for your reminder."
            else -> "Time to wake up."
        }

        try {
            val manager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            ensureChannel(manager)

            val sound = try {
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            } catch (_: Exception) {
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            }

            val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, AlarmScheduler.CHANNEL_ID)
                    .setContentTitle(title)
                    .setContentText(body)
                    .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                    .setAutoCancel(true)
                    .setCategory(Notification.CATEGORY_ALARM)
                    .setSound(sound)
                    .setVibrate(longArrayOf(0, 500, 250, 500))
                    .build()
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
                    .setContentTitle(title)
                    .setContentText(body)
                    .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                    .setAutoCancel(true)
                    .setCategory(Notification.CATEGORY_ALARM)
                    .setSound(sound)
                    .setVibrate(longArrayOf(0, 500, 250, 500))
                    .build()
            }
            manager.notify(id.takeIf { it != 0 } ?: title.hashCode(), notification)
        } catch (_: Exception) {}

        // Extra vibration kick (some OEMs mute notification vibration).
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vm.defaultVibrator.vibrate(
                    VibrationEffect.createWaveform(longArrayOf(0, 500, 250, 500), -1)
                )
            } else {
                @Suppress("DEPRECATION")
                val v = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    v.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 500, 250, 500), -1))
                } else {
                    @Suppress("DEPRECATION")
                    v.vibrate(longArrayOf(0, 500, 250, 500), -1)
                }
            }
        } catch (_: Exception) {}
    }

    private fun ensureChannel(manager: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (manager.getNotificationChannel(AlarmScheduler.CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            AlarmScheduler.CHANNEL_ID,
            "Alarms & Reminders",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "FRIDAY alarms and reminders"
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 500, 250, 500)
        }
        try {
            manager.createNotificationChannel(channel)
        } catch (_: Exception) {}
    }
}
