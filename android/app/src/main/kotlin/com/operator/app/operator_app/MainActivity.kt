package com.operator.app.operator_app

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

open class MainActivity : FlutterActivity() {
    private val CHANNEL = "friday/app_launcher"
    private val FLASHLIGHT_CHANNEL = "friday/flashlight"
    private val DEVICE_CONTROL_CHANNEL = "friday/device_control"
    private val MEDIA_CONTROL_CHANNEL = "friday/media_control"
    private val VOLUME_CONTROL_CHANNEL = "friday/volume_control"
    private val BRIGHTNESS_CONTROL_CHANNEL = "friday/brightness_control"
    private val WHATSAPP_CHANNEL = "friday/whatsapp"
    private val PHONE_CALL_CHANNEL = "friday/phone_call"
    private val SMS_CHANNEL = "friday/sms"
    private val AUTOMATION_CHANNEL = "friday/automation"
    private val GALLERY_CHANNEL = "friday/gallery"
    private val YOUTUBE_CHANNEL = "friday/youtube"
    private val ALARM_CHANNEL = "friday/alarm"
    private val ASSIST_CHANNEL = "friday/assist"
    protected var assistMethodChannel: MethodChannel? = null
    protected var pendingAssistLaunch = false
    private val CAMERA_PERMISSION_REQUEST_CODE = 1001
    private val CONTACTS_PERMISSION_REQUEST_CODE = 1002
    private val CALL_PERMISSION_REQUEST_CODE = 1006
    private val GALLERY_PERMISSION_REQUEST_CODE = 1003
    private val NOTIFICATIONS_PERMISSION_REQUEST_CODE = 1004
    private val CALENDAR_PERMISSION_REQUEST_CODE = 1007
    private val BLUETOOTH_PERMISSION_REQUEST_CODE = 1008
    private val BLUETOOTH_ENABLE_REQUEST_CODE = 1009
    private val SMS_PERMISSION_REQUEST_CODE = 1010

    private lateinit var flashlight: Flashlight
    private lateinit var deviceControl: DeviceControl
    private lateinit var mediaController: MediaController
    private lateinit var volumeController: VolumeController
    private lateinit var brightnessController: BrightnessController
    private lateinit var whatsApp: WhatsApp
    private lateinit var phoneCall: PhoneCall
    private lateinit var smsSender: SmsSender
    private var pendingFlashlightResult: MethodChannel.Result? = null
    private var pendingWhatsAppContactName: String? = null
    private var pendingWhatsAppMessage: String? = null
    private var pendingWhatsAppResult: MethodChannel.Result? = null
    private var pendingCallContactName: String? = null
    private var pendingCallResult: MethodChannel.Result? = null
    private var pendingSmsRecipient: String? = null
    private var pendingSmsMessage: String? = null
    private var pendingSmsPhone: String? = null
    private var pendingSmsResult: MethodChannel.Result? = null
    private var pendingGalleryIndex: Int? = null
    private var pendingGalleryResult: MethodChannel.Result? = null
    private var pendingBluetoothDesired: DeviceControl.DesiredState? = null
    private var pendingBluetoothResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        if (this is AssistActivity) {
            overridePendingTransition(0, 0)
            intent.putExtra("background_mode", BackgroundMode.transparent.name)
        }
        super.onCreate(savedInstanceState)
        // Cold start via long-press power / assist gesture.
        val assist = isAssistIntent(intent)
        if (assist) {
            pendingAssistLaunch = true
        }
        applyWindowForAssist(assist)
    }

    override fun onPause() {
        super.onPause()
        if (this is AssistActivity) {
            overridePendingTransition(0, 0)
        }
    }

    override fun onStop() {
        super.onStop()
        if (this is AssistActivity) {
            overridePendingTransition(0, 0)
        }
    }

    override fun onNewIntent(intent: Intent) {
        overridePendingTransition(0, 0)
        super.onNewIntent(intent)
        setIntent(intent)
        // Warm start: app already alive (singleTop), user long-pressed again.
        // Same warm engine is reused — no reload, stays fast.
        if (isAssistIntent(intent)) {
            pendingAssistLaunch = true
            applyWindowForAssist(true)
            assistMethodChannel?.invokeMethod("onAssist", null)
        } else {
            pendingAssistLaunch = false
            applyWindowForAssist(false)
            assistMethodChannel?.invokeMethod("onLauncherOpen", null)
        }
    }

    /// Assist overlay uses a translucent background with the bar at the
    /// bottom, letting the previous app show through just like Gemini.
    protected fun applyWindowForAssist(assist: Boolean) {
        if (assist || this is AssistActivity) {
            try {
                window.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
                window.clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
            } catch (_: Exception) {}
        }
    }

    /// Transparent Flutter surface for assist overlay. Normal activity uses opaque.
    override fun getBackgroundMode(): BackgroundMode =
        if (this is AssistActivity) BackgroundMode.transparent else BackgroundMode.opaque

    protected open fun isAssistIntent(intent: Intent?): Boolean {
        if (intent == null) return false
        val action = intent.action ?: return false
        return action == Intent.ACTION_ASSIST ||
            action == Intent.ACTION_VOICE_COMMAND
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Created here (not as field initializers) because the activity
        // context is only attached after instantiation.
        flashlight = Flashlight(applicationContext)
        deviceControl = DeviceControl(applicationContext)
        mediaController = MediaController(applicationContext)
        volumeController = VolumeController(applicationContext)
        brightnessController = BrightnessController(applicationContext)
        whatsApp = WhatsApp(applicationContext)
        phoneCall = PhoneCall(applicationContext)
        smsSender = SmsSender(applicationContext)
        val appLauncher = AppLauncher(applicationContext)
        val galleryPlayer = GalleryPlayer(applicationContext)
        val youTubeSearch = YouTubeSearch(applicationContext)
        val alarmScheduler = AlarmScheduler(applicationContext)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "launchApp" -> {
                    val target = call.argument<String>("target")
                    val launchResult = appLauncher.launchApp(target)
                    result.success(launchResult.toMap())
                }
                "resolveApp" -> {
                    val target = call.argument<String>("target")
                    val resolveResult = appLauncher.resolveApp(target)
                    result.success(resolveResult.toMap())
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FLASHLIGHT_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "toggleFlashlight" -> toggleFlashlight(result)
                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CONTROL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "toggle" -> {
                    val target = call.argument<String>("target")
                    val desiredStr = call.argument<String>("desired") ?: "toggle"
                    val desired = when (desiredStr) {
                        "on" -> DeviceControl.DesiredState.ON
                        "off" -> DeviceControl.DesiredState.OFF
                        else -> DeviceControl.DesiredState.TOGGLE
                    }
                    val toggleResult = when (target) {
                        "bluetooth" -> deviceControl.toggleBluetooth(desired)
                        "wifi" -> deviceControl.toggleWifi(desired)
                        else -> null
                    }
                    if (toggleResult != null) {
                        if (toggleResult.permissionRequired) {
                            // Need to request BLUETOOTH_CONNECT permission
                            pendingBluetoothResult = result
                            pendingBluetoothDesired = desired
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                requestPermissions(
                                    arrayOf(android.Manifest.permission.BLUETOOTH_CONNECT),
                                    BLUETOOTH_PERMISSION_REQUEST_CODE
                                )
                            } else {
                                // Should not happen, but fallback
                                result.success(toggleResult.toMap())
                            }
                        } else {
                            result.success(toggleResult.toMap())
                        }
                    } else {
                        result.notImplemented()
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CONTROL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "perform" -> {
                    val action = call.argument<String>("action")
                    result.success(mediaController.perform(action).toMap())
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VOLUME_CONTROL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "adjust" -> {
                    val command = call.argument<String>("command")
                    // Dart ints may arrive as Integer, Long or Double depending
                    // on the codec — accept any Number so "set volume to 15"
                    // never drops its level and becomes a silent no-op.
                    val level = call.argument<Number>("level")?.toInt()
                    result.success(volumeController.adjust(command, level).toMap())
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BRIGHTNESS_CONTROL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "adjust" -> {
                    val command = call.argument<String>("command")
                    val level = call.argument<Number>("level")?.toInt()
                    result.success(brightnessController.adjust(command, level).toMap())
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WHATSAPP_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "sendWhatsApp" -> {
                    val contactName = call.argument<String>("contactName")
                    val message = call.argument<String>("message")
                    handleSendWhatsApp(contactName, message, result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PHONE_CALL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "makeCall" -> {
                    val contactName = call.argument<String>("contactName")
                    handleMakeCall(contactName, result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "sendSms" -> {
                    val recipient = call.argument<String>("recipient")
                    val message = call.argument<String>("message")
                    val phoneNumber = call.argument<String>("phoneNumber")
                    handleSendSms(recipient, message, phoneNumber, result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUTOMATION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAccessibilityEnabled" -> {
                    result.success(AutomationAccessibilityService.isAccessibilityEnabled(this))
                }
                "getScreenSummary" -> {
                    val maxNodes = (call.argument<Int>("maxNodes")
                        ?: call.argument<Double>("maxNodes")?.toInt()) ?: 40
                    val svc = AutomationAccessibilityServiceHolder.instance
                    if (svc == null || !AutomationAccessibilityService.isAccessibilityEnabled(this)) {
                        result.success("EYES_EMPTY: service disabled (enable in Accessibility settings)")
                        return@setMethodCallHandler
                    }
                    try {
                        result.success(svc.getEyesSummary(maxNodes))
                    } catch (e: Exception) {
                        result.success("EYES_ERROR: ${e.localizedMessage ?: "unavailable"}")
                    }
                }
                "armManualTest" -> {
                    val svc = AutomationAccessibilityServiceHolder.instance
                    if (svc == null) {
                        result.success(mapOf("success" to false, "status" to "ACCESSIBILITY_DISABLED"))
                        return@setMethodCallHandler
                    }
                    result.success(mapOf("success" to svc.armManualTest(), "status" to "ARMED"))
                }
                "disarmManualTest" -> {
                    AutomationAccessibilityServiceHolder.instance?.disarmManualTest()
                    result.success(mapOf("success" to true, "status" to "DISARMED"))
                }
                "isManualArmed" -> {
                    result.success(
                        AutomationAccessibilityServiceHolder.instance?.manualTestArmed == true
                    )
                }
                "manualTap" -> {
                    val xPct = (call.argument<Double>("xPct")
                        ?: call.argument<Int>("xPct")?.toDouble()) ?: 0.5
                    val yPct = (call.argument<Double>("yPct")
                        ?: call.argument<Int>("yPct")?.toDouble()) ?: 0.5
                    val svc = AutomationAccessibilityServiceHolder.instance
                    if (svc == null) {
                        result.success(mapOf("success" to false, "status" to "ACCESSIBILITY_DISABLED"))
                        return@setMethodCallHandler
                    }
                    MainScope().launch {
                        try {
                            result.success(svc.manualTap(xPct, yPct))
                        } catch (e: Exception) {
                            result.success(mapOf("success" to false, "status" to "EXECUTION_FAILED", "errorMessage" to (e.localizedMessage ?: "Tap failed")))
                        }
                    }
                }
                "manualEnterText" -> {
                    val text = call.argument<String>("text") ?: ""
                    val svc = AutomationAccessibilityServiceHolder.instance
                    if (svc == null) {
                        result.success(mapOf("success" to false, "status" to "ACCESSIBILITY_DISABLED"))
                        return@setMethodCallHandler
                    }
                    MainScope().launch {
                        try {
                            result.success(svc.manualEnterText(text))
                        } catch (e: Exception) {
                            result.success(mapOf("success" to false, "status" to "EXECUTION_FAILED", "errorMessage" to (e.localizedMessage ?: "Set-text failed")))
                        }
                    }
                }
                "isOverlayGranted" -> {
                    val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        Settings.canDrawOverlays(this)
                    } else true
                    result.success(granted)
                }
                "requestAccessibilitySettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) })
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("FAILED", e.localizedMessage, null)
                    }
                }
                "requestOverlayPermission" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                            startActivity(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("FAILED", e.localizedMessage, null)
                    }
                }
                "executeSteps" -> {
                    val steps = call.argument<List<Map<String, Any?>>>("steps")
                    val targetPackage = call.argument<String>("targetPackage")
                    if (steps == null) {
                        result.success(mapOf("success" to false, "status" to "INVALID_REQUEST", "errorMessage" to "steps missing"))
                        return@setMethodCallHandler
                    }
                    val svc = AutomationAccessibilityServiceHolder.instance
                    if (svc == null || !AutomationAccessibilityService.isAccessibilityEnabled(this)) {
                        result.success(mapOf("success" to false, "status" to "ACCESSIBILITY_DISABLED", "errorMessage" to "Accessibility service is disabled. Please enable it in settings."))
                        return@setMethodCallHandler
                    }
                    // Run in coroutine
                    MainScope().launch {
                        try {
                            val res = svc.executeSteps(steps, targetPackage)
                            result.success(res)
                        } catch (e: Exception) {
                            result.success(mapOf("success" to false, "status" to "EXECUTION_FAILED", "errorMessage" to (e.localizedMessage ?: "Execution failed")))
                        }
                    }
                }
                "startRecording" -> {
                    val svc = AutomationAccessibilityServiceHolder.instance
                    if (svc == null || !AutomationAccessibilityService.isAccessibilityEnabled(this)) {
                        result.error("ACCESSIBILITY_DISABLED", "Accessibility service is disabled", null)
                        return@setMethodCallHandler
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                        result.error("OVERLAY_PERMISSION_REQUIRED", "Overlay permission required", null)
                        return@setMethodCallHandler
                    }
                    val ok = svc.startRecording()
                    if (ok) {
                        try {
                            startService(Intent(this, RecordingOverlayService::class.java))
                        } catch (_: Exception) {}
                        result.success(true)
                    } else {
                        result.error("FAILED", "Failed to start recording", null)
                    }
                }
                "stopRecording" -> {
                    val svc = AutomationAccessibilityServiceHolder.instance
                    if (svc == null) {
                        try { stopService(Intent(this, RecordingOverlayService::class.java)) } catch (_:Exception){}
                        result.success(emptyList<Map<String,Any?>>())
                        return@setMethodCallHandler
                    }
                    try { stopService(Intent(this, RecordingOverlayService::class.java)) } catch (_:Exception){}
                    val steps = svc.stopRecording()
                    result.success(steps)
                }
                "cancelRecording" -> {
                    val svc = AutomationAccessibilityServiceHolder.instance
                    svc?.cancelRecording()
                    try { stopService(Intent(this, RecordingOverlayService::class.java)) } catch (_:Exception){}
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GALLERY_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "playVideoAt" -> {
                    val index = (call.argument<Int>("index") ?: call.argument<Double>("index")?.toInt()) ?: 1
                    handlePlayGalleryVideo(index, galleryPlayer, result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, YOUTUBE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "searchAndPlay" -> {
                    val query = call.argument<String>("query")
                    val index = (call.argument<Int>("index") ?: call.argument<Double>("index")?.toInt()) ?: 1
                    MainScope().launch {
                        try {
                            val res = youTubeSearch.searchAndPlay(query, index)
                            result.success(res)
                        } catch (e: Exception) {
                            result.success(mapOf("success" to false, "status" to "EXECUTION_FAILED", "errorMessage" to (e.localizedMessage ?: "YouTube search failed")))
                        }
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ALARM_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setAlarm" -> {
                    requestNotificationsPermissionIfNeeded()
                    val triggerAt = (call.argument<Number>("triggerAtMillis"))?.toLong()
                    val label = call.argument<String>("label") ?: ""
                    result.success(alarmScheduler.setAlarm(triggerAt, label, "alarm").toMap())
                }
                "setReminder" -> {
                    requestNotificationsPermissionIfNeeded()
                    requestCalendarPermissionIfNeeded()
                    val triggerAt = (call.argument<Number>("triggerAtMillis"))?.toLong()
                    val label = call.argument<String>("label") ?: ""
                    result.success(alarmScheduler.setAlarm(triggerAt, label, "reminder").toMap())
                }
                "listAlarms" -> {
                    result.success(alarmScheduler.listAlarms())
                }
                "cancelAlarm" -> {
                    val query = call.argument<String>("query") ?: ""
                    result.success(alarmScheduler.cancelAlarm(query))
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        assistMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ASSIST_CHANNEL)
        assistMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isAssistLaunch" -> {
                    result.success(pendingAssistLaunch)
                }
                "consumeAssistLaunch" -> {
                    val v = pendingAssistLaunch
                    pendingAssistLaunch = false
                    result.success(v)
                }
                "clearAssistLaunch" -> {
                    pendingAssistLaunch = false
                    result.success(null)
                }
                "setAssistWindow" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    pendingAssistLaunch = enabled
                    applyWindowForAssist(enabled)
                    result.success(null)
                }
                "closeAssist" -> {
                    pendingAssistLaunch = false
                    result.success(null)
                    moveTaskToBack(true)
                    overridePendingTransition(0, 0)
                }
                "dismissAssist" -> {
                    // Background the task instead of destroying it: the warm
                    // engine + loaded model stay alive, so subsequent long-press
                    // assist invocations open instantly.
                    pendingAssistLaunch = false
                    applyWindowForAssist(false)
                    result.success(null)
                    moveTaskToBack(true)
                    overridePendingTransition(0, 0)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun handleSendWhatsApp(
        contactName: String?,
        message: String?,
        result: MethodChannel.Result
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingWhatsAppContactName = contactName
            pendingWhatsAppMessage = message
            pendingWhatsAppResult = result
            requestPermissions(arrayOf(Manifest.permission.READ_CONTACTS), CONTACTS_PERMISSION_REQUEST_CODE)
            return
        }
        result.success(whatsApp.sendWhatsApp(contactName, message).toMap())
    }

    private fun handleMakeCall(
        contactName: String?,
        result: MethodChannel.Result
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val needsContacts = checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED
            val needsCall = checkSelfPermission(Manifest.permission.CALL_PHONE) != PackageManager.PERMISSION_GRANTED
            if (needsContacts || needsCall) {
                pendingCallContactName = contactName
                pendingCallResult = result
                val perms = mutableListOf<String>()
                if (needsContacts) perms.add(Manifest.permission.READ_CONTACTS)
                if (needsCall) perms.add(Manifest.permission.CALL_PHONE)
                requestPermissions(perms.toTypedArray(), CALL_PERMISSION_REQUEST_CODE)
                return
            }
        }
        result.success(phoneCall.makeCall(contactName).toMap())
    }

    private fun handleSendSms(
        recipient: String?,
        message: String?,
        phoneNumber: String?,
        result: MethodChannel.Result
    ) {
        val cleanRecipient = recipient?.trim() ?: ""
        val isFo = cleanRecipient.equals("FO", ignoreCase = true) ||
            cleanRecipient.equals("wajo", ignoreCase = true) ||
            cleanRecipient.equals("wajo fo", ignoreCase = true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val needsContacts = !isFo && phoneNumber.isNullOrBlank() &&
                checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED
            val needsSms = checkSelfPermission(Manifest.permission.SEND_SMS) != PackageManager.PERMISSION_GRANTED

            if (needsContacts || needsSms) {
                pendingSmsRecipient = recipient
                pendingSmsMessage = message
                pendingSmsPhone = phoneNumber
                pendingSmsResult = result
                val perms = mutableListOf<String>()
                if (needsContacts) perms.add(Manifest.permission.READ_CONTACTS)
                if (needsSms) perms.add(Manifest.permission.SEND_SMS)
                requestPermissions(perms.toTypedArray(), SMS_PERMISSION_REQUEST_CODE)
                return
            }
        }
        result.success(smsSender.sendSms(recipient, message, phoneNumber).toMap())
    }

    private fun toggleFlashlight(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingFlashlightResult = result
            requestPermissions(arrayOf(Manifest.permission.CAMERA), CAMERA_PERMISSION_REQUEST_CODE)
            return
        }

        result.success(flashlight.toggle().toMap())
    }

    private fun requestNotificationsPermissionIfNeeded() {
        // Alarms still schedule without this (notification may be silent
        // until granted), so never block — request in parallel to stay fast.
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            try {
                requestPermissions(
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    NOTIFICATIONS_PERMISSION_REQUEST_CODE
                )
            } catch (_: Exception) {}
        }
    }

    private fun requestCalendarPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val perms = mutableListOf<String>()
            if (checkSelfPermission(Manifest.permission.READ_CALENDAR) != PackageManager.PERMISSION_GRANTED) {
                perms.add(Manifest.permission.READ_CALENDAR)
            }
            if (checkSelfPermission(Manifest.permission.WRITE_CALENDAR) != PackageManager.PERMISSION_GRANTED) {
                perms.add(Manifest.permission.WRITE_CALENDAR)
            }
            if (perms.isNotEmpty()) {
                try {
                    requestPermissions(
                        perms.toTypedArray(),
                        CALENDAR_PERMISSION_REQUEST_CODE
                    )
                } catch (_: Exception) {}
            }
        }
    }

    private fun galleryPermission(): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_VIDEO
        } else {
            @Suppress("DEPRECATION")
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
    }

    private fun handlePlayGalleryVideo(
        index: Int,
        galleryPlayer: GalleryPlayer,
        result: MethodChannel.Result
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(galleryPermission()) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingGalleryIndex = index
            pendingGalleryResult = result
            requestPermissions(arrayOf(galleryPermission()), GALLERY_PERMISSION_REQUEST_CODE)
            return
        }
        result.success(galleryPlayer.playVideoAt(index))
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        when (requestCode) {
            CAMERA_PERMISSION_REQUEST_CODE -> {
                val pending = pendingFlashlightResult
                pendingFlashlightResult = null
                if (pending == null) return
                val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
                if (granted) {
                    pending.success(flashlight.toggle().toMap())
                } else {
                    pending.success(
                        Flashlight.ToggleResult(
                            success = false,
                            torchOn = false,
                            errorMessage = "Camera permission is required to use the flashlight."
                        ).toMap()
                    )
                }
            }
            CONTACTS_PERMISSION_REQUEST_CODE -> {
                val pending = pendingWhatsAppResult
                val contactName = pendingWhatsAppContactName
                val message = pendingWhatsAppMessage
                pendingWhatsAppResult = null
                pendingWhatsAppContactName = null
                pendingWhatsAppMessage = null
                if (pending == null) return
                val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
                if (granted) {
                    pending.success(whatsApp.sendWhatsApp(contactName, message).toMap())
                } else {
                    pending.success(
                        WhatsApp.WhatsAppResult(
                            success = false,
                            status = "PERMISSION_DENIED",
                            errorMessage = "Contacts permission is required to find \"$contactName\". Please grant contacts permission in settings."
                        ).toMap()
                    )
                }
            }
            GALLERY_PERMISSION_REQUEST_CODE -> {
                val pending = pendingGalleryResult
                val index = pendingGalleryIndex ?: 1
                pendingGalleryResult = null
                pendingGalleryIndex = null
                if (pending == null) return
                val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
                if (granted) {
                    val player = GalleryPlayer(applicationContext)
                    pending.success(player.playVideoAt(index))
                } else {
                    pending.success(
                        mapOf(
                            "success" to false,
                            "status" to "PERMISSION_DENIED",
                            "errorMessage" to "Gallery permission is required to play videos. Please grant media access in settings."
                        )
                    )
                }
            }
            CALL_PERMISSION_REQUEST_CODE -> {
                val pending = pendingCallResult
                val contactName = pendingCallContactName
                pendingCallResult = null
                pendingCallContactName = null
                if (pending == null) return
                val granted = grantResults.isNotEmpty() &&
                    grantResults.all { it == PackageManager.PERMISSION_GRANTED }
                if (granted) {
                    pending.success(phoneCall.makeCall(contactName).toMap())
                } else {
                    pending.success(
                        PhoneCall.CallResult(
                            success = false,
                            status = "PERMISSION_DENIED",
                            errorMessage = "Phone and contacts permission is required to call \"$contactName\". Please grant phone permission in settings."
                        ).toMap()
                    )
                }
            }
            CALENDAR_PERMISSION_REQUEST_CODE -> {
                // Calendar permissions updated; subsequent reminders will insert into Calendar directly.
            }
            BLUETOOTH_PERMISSION_REQUEST_CODE -> {
                val pending = pendingBluetoothResult
                val desired = pendingBluetoothDesired ?: DeviceControl.DesiredState.TOGGLE
                pendingBluetoothResult = null
                pendingBluetoothDesired = null
                if (pending == null) return
                val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
                if (granted) {
                    // Retry the toggle now that permission is granted
                    val toggleResult = deviceControl.toggleBluetooth(desired)
                    pending.success(toggleResult.toMap())
                } else {
                    pending.success(
                        DeviceControl.ToggleResult(
                            success = false,
                            panelOpened = false,
                            isOn = false,
                            wasOn = false,
                            errorMessage = "Bluetooth permission is required to toggle Bluetooth. Please grant permission in settings.",
                            permissionRequired = true
                        ).toMap()
                    )
                }
            }
            SMS_PERMISSION_REQUEST_CODE -> {
                val pending = pendingSmsResult
                val recipient = pendingSmsRecipient
                val message = pendingSmsMessage
                val phone = pendingSmsPhone
                pendingSmsResult = null
                pendingSmsRecipient = null
                pendingSmsMessage = null
                pendingSmsPhone = null
                if (pending == null) return
                val granted = grantResults.isNotEmpty() &&
                    grantResults.all { it == PackageManager.PERMISSION_GRANTED }
                if (granted) {
                    pending.success(smsSender.sendSms(recipient, message, phone).toMap())
                } else {
                    // Even if direct SMS permission is denied, smsSender falls back to launching the Messages app
                    pending.success(smsSender.sendSms(recipient, message, phone).toMap())
                }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == BLUETOOTH_ENABLE_REQUEST_CODE) {
            val pending = pendingBluetoothResult
            val desired = pendingBluetoothDesired ?: DeviceControl.DesiredState.TOGGLE
            pendingBluetoothResult = null
            pendingBluetoothDesired = null
            if (pending == null) return
            val adapter = android.bluetooth.BluetoothAdapter.getDefaultAdapter()
            val isOn = adapter?.isEnabled ?: false
            if (resultCode == RESULT_OK && desired == DeviceControl.DesiredState.ON) {
                pending.success(
                    DeviceControl.ToggleResult(
                        success = true,
                        panelOpened = false,
                        isOn = true,
                        wasOn = false
                    ).toMap()
                )
            } else {
                pending.success(
                    DeviceControl.ToggleResult(
                        success = false,
                        panelOpened = false,
                        isOn = isOn,
                        wasOn = isOn,
                        errorMessage = "Bluetooth enable was cancelled or failed."
                    ).toMap()
                )
            }
        }
    }
}