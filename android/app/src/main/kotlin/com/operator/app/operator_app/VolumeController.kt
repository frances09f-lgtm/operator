package com.operator.app.operator_app

import android.content.Context
import android.media.AudioManager
import kotlin.math.roundToInt

/**
 * Adjusts the device media volume through [AudioManager].
 *
 * Levels are exchanged with Flutter as percentages (0-100) so the assistant
 * can speak "Volume is at 40%". Mute remembers the last non-zero level so an
 * unmute can restore it.
 */
class VolumeController(private val context: Context) {

    data class VolumeResult(
        val success: Boolean,
        val level: Int,
        val errorMessage: String? = null
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "success" to success,
            "level" to level,
            "errorMessage" to errorMessage
        )
    }

    @Volatile
    private var lastNonZeroPercent = -1

    private val audioManager: AudioManager
        get() = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    /** Applies [command] ('set'/'up'/'down'/'mute'/'unmute'/'query'). */
    fun adjust(command: String?, level: Int?): VolumeResult {
        return try {
            when (command) {
                "set" -> {
                    // Dart always sends a 0-100 level for set; if it is missing
                    // fall back to a query instead of silently re-setting the
                    // current level (which looks like "didn't work").
                    val target = level ?: return VolumeResult(success = true, level = currentPercent())
                    setPercent(target)
                }
                "up" -> setPercent(currentPercent() + stepPercent(), reportCurrent = true)
                "down" -> setPercent(currentPercent() - stepPercent(), reportCurrent = true)
                "mute" -> {
                    val current = currentPercent()
                    if (current > 0) lastNonZeroPercent = current
                    setPercent(0)
                }
                "unmute" -> {
                    val restore = if (lastNonZeroPercent >= 0) lastNonZeroPercent else 50
                    lastNonZeroPercent = -1
                    setPercent(restore)
                }
                else -> VolumeResult(success = true, level = currentPercent())
            }
        } catch (e: Exception) {
            VolumeResult(
                success = false,
                level = currentPercent(),
                errorMessage = e.localizedMessage ?: "Failed to adjust the volume."
            )
        }
    }

    private fun setPercent(percent: Int, reportCurrent: Boolean = false): VolumeResult {
        val clamped = percent.coerceIn(0, 100)
        val value = ((clamped / 100.0) * maxLevel).roundToInt()
        audioManager.setStreamVolume(
            AudioManager.STREAM_MUSIC,
            value,
            AudioManager.FLAG_SHOW_UI
        )
        // For absolute sets report the requested level (matches the Dart
        // fake and avoids quantization read-back like 15 -> 13 looking like
        // a failure). For relative steps report the live level.
        val reported = if (reportCurrent) currentPercent() else clamped
        return VolumeResult(success = true, level = reported)
    }

    private fun currentPercent(): Int {
        val max = maxLevel
        if (max <= 0) return 0
        return ((audioManager.getStreamVolume(AudioManager.STREAM_MUSIC) * 100.0) / max).roundToInt()
            .coerceIn(0, 100)
    }

    private val maxLevel: Int
        get() = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)

    /** Percent change for a single native volume step (one press of the rocker). */
    private fun stepPercent(): Int {
        val max = maxLevel
        if (max <= 0) return 1
        return (100.0 / max).roundToInt().coerceAtLeast(1)
    }
}