package com.operator.app.operator_app

import android.app.Service
import android.content.Intent
import android.graphics.PixelFormat
import android.os.IBinder
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.os.Build

class RecordingOverlayService : Service() {

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var initialX = 0
    private var initialY = 0
    private var initialTouchX = 0f
    private var initialTouchY = 0f

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        createOverlay()
    }

    private fun createOverlay() {
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setBackgroundColor(0xCC121212.toInt())
            setPadding(24, 16, 24, 16)
        }

        val label = TextView(this).apply {
            text = "● REC"
            setTextColor(0xFFFF3B30.toInt())
            textSize = 14f
            setPadding(0, 0, 16, 0)
        }

        val stopBtn = Button(this).apply {
            text = "Stop"
            setBackgroundColor(0xFF2962FF.toInt())
            setTextColor(0xFFFFFFFF.toInt())
            setOnClickListener {
                // Notify via broadcast or via holder?
                val intent = Intent("friday_recording_stop")
                sendBroadcast(intent)
                stopSelf()
            }
        }

        val cancelBtn = Button(this).apply {
            text = "Cancel"
            setBackgroundColor(0xFF424242.toInt())
            setTextColor(0xFFFFFFFF.toInt())
            setPadding(16, 0, 16, 0)
            setOnClickListener {
                val intent = Intent("friday_recording_cancel")
                sendBroadcast(intent)
                stopSelf()
            }
        }

        layout.addView(label)
        layout.addView(stopBtn)
        layout.addView(cancelBtn)

        // Make draggable
        layout.setOnTouchListener { v, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    params.x = initialX + (event.rawX - initialTouchX).toInt()
                    params.y = initialY + (event.rawY - initialTouchY).toInt()
                    windowManager?.updateViewLayout(overlayView, params)
                    true
                }
                else -> false
            }
        }

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE
        }

        params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 20
            y = 120
        }

        overlayView = layout
        try {
            windowManager?.addView(overlayView, params)
        } catch (_: Exception) {
        }
    }

    private lateinit var params: WindowManager.LayoutParams

    override fun onDestroy() {
        overlayView?.let {
            try { windowManager?.removeView(it) } catch (_: Exception) {}
        }
        overlayView = null
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_NOT_STICKY
    }
}
