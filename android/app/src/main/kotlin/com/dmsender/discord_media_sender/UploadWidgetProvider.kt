package com.dmsender.discord_media_sender

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews

/**
 * The Android home screen widget.
 *
 * The widget renders the state published by the Dart upload engine. Its
 * action buttons write a control command that the upload engine picks up; the
 * widget never performs an upload itself.
 *
 * The widget offers three actions only: Pause, Resume and Open.
 */
class UploadWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            UploadWidgetProvider.render(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_PAUSE -> {
                UploadStateStore.sendControlCommand(context, "pause")
                refreshAll(context)
            }

            ACTION_RESUME -> {
                UploadStateStore.sendControlCommand(context, "resume")
                refreshAll(context)
            }

            ACTION_OPEN -> {
                context.startActivity(
                    Intent(context, MainActivity::class.java).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    }
                )
            }
        }
    }

    companion object {
        private fun pendingIntent(context: Context, action: String): PendingIntent {
            val intent = Intent(context, UploadWidgetProvider::class.java).apply {
                this.action = action
            }
            return PendingIntent.getBroadcast(
                context,
                action.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        const val ACTION_PAUSE = "com.dmsender.discord_media_sender.widget.PAUSE"
        const val ACTION_RESUME = "com.dmsender.discord_media_sender.widget.RESUME"
        const val ACTION_OPEN = "com.dmsender.discord_media_sender.widget.OPEN"

        /** Refreshes every widget instance of the app. */
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                android.content.ComponentName(context, UploadWidgetProvider::class.java)
            )
            for (id in ids) {
                render(context, manager, id)
            }
        }

        /** Rebuilds a single widget instance. */
        fun render(context: Context, manager: AppWidgetManager, appWidgetId: Int) {
            val state = UploadStateStore.snapshot(context)
            val status = state[UploadStateStore.KEY_STATUS] as? String ?: "idle"
            val isPaused = state[UploadStateStore.KEY_IS_PAUSED] as? Boolean ?: false
            val density = state[UploadStateStore.KEY_DENSITY] as? String ?: "normal"
            val progress = (state[UploadStateStore.KEY_PROGRESS] as? Double ?: 0.0)
                .toInt().coerceIn(0, 100)
            val total = state[UploadStateStore.KEY_TOTAL_FILES] as? Int ?: 0
            val completed = state[UploadStateStore.KEY_COMPLETED_FILES] as? Int ?: 0
            val failed = state[UploadStateStore.KEY_FAILED_FILES] as? Int ?: 0
            val destination = state[UploadStateStore.KEY_DESTINATION] as? String ?: ""

            val views = RemoteViews(context.packageName, R.layout.upload_widget)

            val statusText = when {
                isPaused -> "Paused"
                status == "uploading" -> "Uploading"
                total > 0 && completed + failed >= total -> "Finished"
                else -> "Idle"
            }
            views.setTextViewText(R.id.widget_status, statusText)
            views.setTextViewText(R.id.widget_progress_text, "$completed/$total files")
            views.setTextViewText(R.id.widget_failed, "Failed: $failed")
            views.setTextViewText(
                R.id.widget_destination,
                if (destination.isEmpty()) "No active destination" else destination
            )
            views.setProgressBar(R.id.widget_progress, 100, progress, false)

            // The compact density drops the destination line and keeps two
            // lines of content.
            views.setViewVisibility(
                R.id.widget_destination,
                if (density == "compact") View.GONE else View.VISIBLE
            )

            views.setOnClickPendingIntent(R.id.widget_pause, pendingIntent(context, ACTION_PAUSE))
            views.setOnClickPendingIntent(R.id.widget_resume, pendingIntent(context, ACTION_RESUME))
            views.setOnClickPendingIntent(
                R.id.widget_open,
                PendingIntent.getActivity(
                    context,
                    100,
                    Intent(context, MainActivity::class.java).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    },
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )

            manager.updateAppWidget(appWidgetId, views)
        }
    }
}
