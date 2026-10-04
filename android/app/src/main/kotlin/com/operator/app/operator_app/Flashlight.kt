package com.operator.app.operator_app

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager

/**
 * Controls the device flashlight through the Camera2 [CameraManager].
 * Prefers a rear camera with flash; falls back to any camera exposing flash.
 * Torch state is tracked both manually and via [CameraManager.TorchCallback].
 */
class Flashlight(private val context: Context) {

    data class ToggleResult(
        val success: Boolean,
        val torchOn: Boolean,
        val errorMessage: String? = null
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "success" to success,
            "torchOn" to torchOn,
            "errorMessage" to errorMessage
        )
    }

    @Volatile
    private var lastTorchOn = false

    init {
        try {
            cameraManager.registerTorchCallback(
                object : CameraManager.TorchCallback() {
                    override fun onTorchModeChanged(cameraId: String, enabled: Boolean) {
                        lastTorchOn = enabled
                    }
                },
                null
            )
        } catch (_: Exception) {
            // Torch callback unsupported on this device; state is tracked manually.
        }
    }

    /** Toggles the flashlight and returns the resulting torch state. */
    @Synchronized
    fun toggle(): ToggleResult {
        val cameraId = findTorchCameraId()
            ?: return ToggleResult(
                success = false,
                torchOn = false,
                errorMessage = "No camera with a flashlight is available."
            )

        val nextState = !lastTorchOn

        return try {
            cameraManager.setTorchMode(cameraId, nextState)
            lastTorchOn = nextState
            ToggleResult(success = true, torchOn = nextState)
        } catch (e: Exception) {
            ToggleResult(
                success = false,
                torchOn = false,
                errorMessage = e.localizedMessage ?: "Failed to toggle the flashlight."
            )
        }
    }

    /** Returns the current torch state, falling back to the last known value. */
    fun isTorchOn(): Boolean = lastTorchOn

    private val cameraManager: CameraManager
        get() = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager

    private fun findTorchCameraId(): String? {
        var fallbackId: String? = null
        for (cameraId in cameraManager.cameraIdList) {
            val characteristics = cameraManager.getCameraCharacteristics(cameraId)
            val flashAvailable =
                characteristics.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) ?: false
            if (!flashAvailable) continue

            val facing = characteristics.get(CameraCharacteristics.LENS_FACING)
            if (facing == CameraCharacteristics.LENS_FACING_BACK) {
                return cameraId
            }
            if (fallbackId == null) {
                fallbackId = cameraId
            }
        }
        return fallbackId
    }
}