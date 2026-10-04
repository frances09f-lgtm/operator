package com.operator.app.operator_app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import kotlin.math.roundToInt

/**
 * Adjusts the system screen brightness by writing [Settings.System.SCREEN_BRIGHTNESS].
 *
 * Requires the special WRITE_SETTINGS permission ("Modify system settings").
 * When it is missing the controller opens the manage-settings page and reports
 * [BrightnessResult.permissionRequired] so FRIDAY can explain what happened.
 */
class BrightnessController(private val context: Context) {

    data class BrightnessResult(
        val success: Boolean,
        val level: Int,
        val permissionRequired: Boolean = false,
        val errorMessage: String? = null
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "success" to success,
            "level" to level,
            "permissionRequired" to permissionRequired,
            "errorMessage" to errorMessage
        )
    }

    /** Applies [command] ('set'/'up'/'down'/'query'). */
    fun adjust(command: String?, level: Int?): BrightnessResult {
        if (!Settings.System.canWrite(context)) {
            openWriteSettings()
            return BrightnessResult(
                success = false,
                level = currentPercent(),
                permissionRequired = true,
                errorMessage = "Brightness control needs system write permission."
            )
        }
        return try {
            when (command) {
                "set" -> setPercent(level ?: currentPercent())
                "up" -> setPercent(currentPercent() + 5)
                "down" -> setPercent(currentPercent() - 5)
                else -> BrightnessResult(success = true, level = currentPercent())
            }
        } catch (e: Exception) {
            BrightnessResult(
                success = false,
                level = currentPercent(),
                permissionRequired = false,
                errorMessage = e.localizedMessage ?: "Failed to change the brightness."
            )
        }
    }

    private fun setPercent(percent: Int): BrightnessResult {
        val clamped = percent.coerceIn(0, 100)
        val value = ((clamped / 100.0) * 255).roundToInt()
        Settings.System.putInt(
            context.contentResolver,
            Settings.System.SCREEN_BRIGHTNESS,
            value
        )
        return BrightnessResult(success = true, level = currentPercent())
    }

    private fun currentPercent(): Int {
        val value = Settings.System.getInt(
            context.contentResolver,
            Settings.System.SCREEN_BRIGHTNESS,
            128
        )
        return ((value * 100) / 255).coerceIn(0, 100)
    }

    private fun openWriteSettings() {
        try {
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                Intent(
                    Settings.ACTION_MANAGE_WRITE_SETTINGS,
                    Uri.parse("package:${context.packageName}")
                )
            } else {
                Intent(Settings.ACTION_SETTINGS)
            }
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: Exception) {
            // Settings unavailable; the permissionRequired result still informs Flutter.
        }
    }
}