package com.dmsender.discord_media_sender

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.core.app.NotificationCompat

/**
 * The optional floating overlay panel.
 *
 * The overlay shows the same state as the home screen widget and can control
 * the upload. It is only ever started after the user granted the "display over
 * other apps" permission.
 */
class FloatingOverlayService : android.app.Service() {

    private var windowManager: WindowManager? = null
    private var rootView: View? = null
    private var expanded = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
        if (Settings.canDrawOverlays(this)) {
            showOverlay()
        } else {
            stopSelf()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (!Settings.canDrawOverlays(this)) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (rootView == null) showOverlay()
        refresh()
        return START_STICKY
    }

    override fun onDestroy() {
        rootView?.let { view ->
            try {
                windowManager?.removeView(view)
            } catch (error: Exception) {
                // ignore
            }
        }
        rootView = null
        super.onDestroy()
    }

    private fun showOverlay() {
        if (rootView != null) return
        val inflater = LayoutInflater.from(this)
        val view = inflater.inflate(R.layout.floating_widget, null)

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            android.graphics.PixelFormat.TRANSLUCENT
        )
        params.gravity = Gravity.TOP or Gravity.START
        params.x = 24
        params.y = 160

        view.findViewById<ImageButton>(R.id.float_close)?.setOnClickListener {
            stop(this)
        }
        view.findViewById<ImageButton>(R.id.float_expand)?.setOnClickListener {
            expanded = !expanded
            view.findViewById<LinearLayout>(R.id.float_details)?.visibility =
                if (expanded) android.view.View.VISIBLE else android.view.View.GONE
        }
        view.findViewById<ImageButton>(R.id.float_pause)?.setOnClickListener {
            UploadStateStore.sendControlCommand(this, "pause")
            refresh()
        }
        view.findViewById<ImageButton>(R.id.float_resume)?.setOnClickListener {
            UploadStateStore.sendControlCommand(this, "resume")
            refresh()
        }

        view.setOnTouchListener(object : View.OnTouchListener {
            private var initialX = 0
            private var initialY = 0
            private var initialTouchX = 0f
            private var initialTouchY = 0f

            override fun onTouch(v: View?, event: MotionEvent?): Boolean {
                if (event == null) return false
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = params.x
                        initialY = params.y
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        return true
                    }

                    MotionEvent.ACTION_MOVE -> {
                        params.x = initialX + (event.rawX - initialTouchX).toInt()
                        params.y = initialY + (event.rawY - initialTouchY).toInt()
                        try {
                            windowManager?.updateViewLayout(view, params)
                        } catch (error: Exception) {
                            // ignore
                        }
                        return true
                    }
                }
                return false
            }
        })

        val background = view.findViewById<LinearLayout>(R.id.float_root)?.background
        if (background is GradientDrawable) {
            background.setColor(Color.argb(225, 28, 32, 48))
        }

        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        try {
            windowManager?.addView(view, params)
            rootView = view
        } catch (error: Exception) {
            rootView = null
            stopSelf()
        }
    }

    /** Updates the overlay with the latest published state. */
    fun refresh() {
        val view = rootView ?: return
        val state = UploadStateStore.snapshot(this)
        val status = state[UploadStateStore.KEY_STATUS] as? String ?: "idle"
        val isPaused = state[UploadStateStore.KEY_IS_PAUSED] as? Boolean ?: false
        val progress = ((state[UploadStateStore.KEY_PROGRESS] as? Double ?: 0.0) * 100)
            .toInt().coerceIn(0, 100)
        val currentFile = state[UploadStateStore.KEY_CURRENT_FILE] as? String ?: ""
        val destination = state[UploadStateStore.KEY_DESTINATION] as? String ?: ""
        val speed = state[UploadStateStore.KEY_SPEED] as? Double ?: 0.0
        val eta = state[UploadStateStore.KEY_ETA_SECONDS] as? Int ?: 0
        val completed = state[UploadStateStore.KEY_COMPLETED_FILES] as? Int ?: 0
        val total = state[UploadStateStore.KEY_TOTAL_FILES] as? Int ?: 0

        view.findViewById<TextView>(R.id.float_status)?.text = when {
            isPaused -> "Paused"
            status == "uploading" -> "Uploading"
            else -> "Idle"
        }
        view.findViewById<TextView>(R.id.float_file)?.text =
            if (currentFile.isEmpty()) "Waiting for the next file" else currentFile
        view.findViewById<TextView>(R.id.float_counts)?.text = "$completed/$total files"
        view.findViewById<TextView>(R.id.float_percent)?.text = "$progress%"
        view.findViewById<TextView>(R.id.float_speed)?.text =
            if (speed > 0) String.format("%.0f KB/s", speed / 1024) else "—"
        view.findViewById<TextView>(R.id.float_eta)?.text =
            if (eta > 0) String.format("%ds left", eta) else "—"
        view.findViewById<TextView>(R.id.float_destination)?.text =
            if (destination.isEmpty()) "No active destination" else destination
        view.findViewById<ProgressBar>(R.id.float_progress)?.progress = progress
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.overlay_channel_name),
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val stop = PendingIntent.getService(
            this,
            1,
            Intent(this, FloatingOverlayService::class.java).apply { action = ACTION_STOP },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(getString(R.string.overlay_notification_text))
            .setSmallIcon(android.R.drawable.stat_sys_upload_done)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(open)
            .addAction(0, getString(R.string.overlay_stop), stop)
            .build()
    }

    companion object {
        const val CHANNEL_ID = "dms_overlay"
        const val NOTIFICATION_ID = 4201
        const val ACTION_STOP = "com.dmsender.discord_media_sender.overlay.STOP"

        /** Starts the overlay service when the permission is available. */
        fun start(context: Context): Boolean {
            if (!Settings.canDrawOverlays(context)) return false
            val intent = Intent(context, FloatingOverlayService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                return true
            } catch (error: Exception) {
                return false
            }
        }

        /** Stops the overlay service. */
        fun stop(context: Context) {
            try {
                context.stopService(Intent(context, FloatingOverlayService::class.java))
            } catch (error: Exception) {
                // ignore
            }
        }

        /** Refreshes the overlay if it is running. */
        fun refresh(context: Context) {
            // The overlay polls the shared store, so nothing to do here beyond
            // waking the service so it can redraw immediately.
            try {
                context.startService(
                    Intent(context, FloatingOverlayService::class.java)
                )
            } catch (error: Exception) {
                // ignore
            }
        }
    }
}
