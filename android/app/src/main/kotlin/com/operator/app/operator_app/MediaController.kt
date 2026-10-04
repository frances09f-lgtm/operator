package com.operator.app.operator_app

import android.content.Context
import android.media.AudioManager
import android.view.KeyEvent

/**
 * Sends media transport commands (play/pause/resume/next/previous/stop) to
 * whichever media session currently owns media-button handling.
 *
 * Uses [AudioManager.dispatchMediaKeyEvent], the same mechanism as a physical
 * headset media button: it requires no special permissions and targets the
 * currently active media session rather than a hard-coded music app.
 */
class MediaController(private val context: Context) {

    data class ControlResult(
        val success: Boolean,
        val errorMessage: String? = null
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "success" to success,
            "errorMessage" to errorMessage
        )
    }

    /**
     * Re-validates [action] on the native side, then dispatches the matching
     * media key event. Returns a [ControlResult]; never throws, so Flutter
     * always receives a controlled response.
     */
    fun perform(action: String?): ControlResult {
        if (action.isNullOrBlank()) {
            return ControlResult(success = false, errorMessage = "Media action is empty.")
        }

        val keyCode = when (action) {
            "media_play" -> KeyEvent.KEYCODE_MEDIA_PLAY
            "media_pause" -> KeyEvent.KEYCODE_MEDIA_PAUSE
            "media_resume" -> KeyEvent.KEYCODE_MEDIA_PLAY
            "media_next" -> KeyEvent.KEYCODE_MEDIA_NEXT
            "media_previous" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
            "media_stop" -> KeyEvent.KEYCODE_MEDIA_STOP
            else -> null
        }

        if (keyCode == null) {
            return ControlResult(
                success = false,
                errorMessage = "Unsupported media action: $action"
            )
        }

        return try {
            val audioManager =
                context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            dispatch(audioManager, keyCode)
            ControlResult(success = true)
        } catch (e: Exception) {
            ControlResult(
                success = false,
                errorMessage = e.localizedMessage ?: "Failed to control media."
            )
        }
    }

    @Suppress("DEPRECATION")
    private fun dispatch(audioManager: AudioManager, keyCode: Int) {
        audioManager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        audioManager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, keyCode))
    }
}