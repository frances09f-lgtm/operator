package com.operator.app.operator_app

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode

/// Dedicated translucent assistant activity for long-press power (ACTION_ASSIST).
///
/// Running as singleInstance, taskAffinity="com.operator.app.operator_app.assist",
/// and excludeFromRecents="true" ensures MainActivity (the main app) NEVER opens
/// or closes in the background.
///
/// Inherits from [MainActivity] so all MethodChannels, device controls, and
/// permissions work identically.
class AssistActivity : MainActivity() {

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    override fun isAssistIntent(intent: Intent?): Boolean = true

    override fun onCreate(savedInstanceState: Bundle?) {
        overridePendingTransition(0, 0)
        intent.putExtra("background_mode", BackgroundMode.transparent.name)
        pendingAssistLaunch = true
        super.onCreate(savedInstanceState)
    }

    override fun onResume() {
        super.onResume()
        overridePendingTransition(0, 0)
        assistMethodChannel?.invokeMethod("onAssist", null)
    }

    override fun onPause() {
        super.onPause()
        overridePendingTransition(0, 0)
    }

    override fun finish() {
        super.finish()
        overridePendingTransition(0, 0)
    }
}
