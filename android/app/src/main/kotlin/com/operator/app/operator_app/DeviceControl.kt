package com.operator.app.operator_app

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings

/**
 * Toggles device radios (Bluetooth, Wi-Fi).
 *
 * Bluetooth: Android 12+ requires BLUETOOTH_CONNECT runtime permission for direct toggle.
 * On permission granted, uses BluetoothManager.adapter.enable/disable().
 * On permission denied, falls back to ACTION_REQUEST_ENABLE (one-tap system dialog)
 * or settings panel.
 *
 * Wi-Fi: Android 10+ blocks direct toggle for normal apps (returns false).
 * Tries direct toggle on all versions, falls back to Internet settings panel on failure.
 */
class DeviceControl(private val context: Context) {

    data class ToggleResult(
        val success: Boolean,
        val panelOpened: Boolean,
        val isOn: Boolean,
        val wasOn: Boolean,
        val errorMessage: String? = null,
        val permissionRequired: Boolean = false
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "success" to success,
            "panelOpened" to panelOpened,
            "isOn" to isOn,
            "wasOn" to wasOn,
            "errorMessage" to errorMessage,
            "permissionRequired" to permissionRequired
        )
    }

    enum class DesiredState { ON, OFF, TOGGLE }

    fun toggleBluetooth(desired: DesiredState = DesiredState.TOGGLE): ToggleResult {
        val adapter = BluetoothAdapter.getDefaultAdapter()
            ?: return ToggleResult(
                success = false,
                panelOpened = false,
                isOn = false,
                wasOn = false,
                errorMessage = "Bluetooth is not supported on this device."
            )

        // Get current state (this is wasOn)
        val wasOn = adapter.isEnabled

        // If desired is TOGGLE, flip; otherwise use desired state
        val wantOn = when (desired) {
            DesiredState.ON -> true
            DesiredState.OFF -> false
            DesiredState.TOGGLE -> !wasOn
        }

        // If already in desired state, return success without action
        if (wantOn == wasOn) {
            return ToggleResult(
                success = true,
                panelOpened = false,
                isOn = wasOn,
                wasOn = wasOn
            )
        }

        // Android 12+ (API 31): requires BLUETOOTH_CONNECT permission
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val hasPermission = context.checkSelfPermission(
                android.Manifest.permission.BLUETOOTH_CONNECT
            ) == PackageManager.PERMISSION_GRANTED

            if (!hasPermission) {
                return ToggleResult(
                    success = false,
                    panelOpened = false,
                    isOn = wasOn,
                    wasOn = wasOn,
                    errorMessage = "Bluetooth permission required.",
                    permissionRequired = true
                )
            }

            // Try direct toggle with permission
            return try {
                val ok = if (wantOn) adapter.enable() else adapter.disable()
                val newState = if (ok) wantOn else wasOn
                ToggleResult(success = ok, panelOpened = false, isOn = newState, wasOn = wasOn)
            } catch (e: Exception) {
                ToggleResult(
                    success = false,
                    panelOpened = false,
                    isOn = adapter.isEnabled,
                    wasOn = wasOn,
                    errorMessage = e.localizedMessage ?: "Failed to toggle Bluetooth."
                )
            }
        } else {
            // Legacy direct toggle (Android < 12)
            return try {
                val ok = if (wantOn) adapter.enable() else adapter.disable()
                val newState = if (ok) wantOn else wasOn
                ToggleResult(success = ok, panelOpened = false, isOn = newState, wasOn = wasOn)
            } catch (e: Exception) {
                ToggleResult(
                    success = false,
                    panelOpened = false,
                    isOn = adapter.isEnabled,
                    wasOn = wasOn,
                    errorMessage = e.localizedMessage ?: "Failed to toggle Bluetooth."
                )
            }
        }
    }

    fun toggleWifi(desired: DesiredState = DesiredState.TOGGLE): ToggleResult {
        val wifiManager =
            context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager

        val wasOn = wifiManager.isWifiEnabled
        val wantOn = when (desired) {
            DesiredState.ON -> true
            DesiredState.OFF -> false
            DesiredState.TOGGLE -> !wasOn
        }

        // If already in desired state, return success without action
        if (wantOn == wasOn) {
            return ToggleResult(
                success = true,
                panelOpened = false,
                isOn = wasOn,
                wasOn = wasOn
            )
        }

        // Try direct toggle on all Android versions (may fail on 10+)
        val directResult = try {
            val ok = wifiManager.setWifiEnabled(wantOn)
            if (ok) {
                ToggleResult(success = true, panelOpened = false, isOn = wantOn, wasOn = wasOn)
            } else {
                // setWifiEnabled returns false on Android 10+ for non-system apps
                null // signal to fall through to panel
            }
        } catch (e: Exception) {
            null // signal to fall through to panel
        }

        if (directResult != null) return directResult

        // Fallback: open Internet/Wi-Fi settings panel
        return try {
            val action = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                Settings.Panel.ACTION_INTERNET_CONNECTIVITY
            } else {
                Settings.Panel.ACTION_WIFI
            }
            val intent = Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            ToggleResult(success = true, panelOpened = true, isOn = wasOn, wasOn = wasOn)
        } catch (e: Exception) {
            ToggleResult(
                success = false,
                panelOpened = false,
                isOn = wasOn,
                wasOn = wasOn,
                errorMessage = "Could not open Wi-Fi settings: " +
                    (e.localizedMessage ?: "unknown error.")
            )
        }
    }
}