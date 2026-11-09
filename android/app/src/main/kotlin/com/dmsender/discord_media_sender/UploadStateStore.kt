package com.dmsender.discord_media_sender

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit

/**
 * Shared state between the Dart upload engine and the Android widgets.
 *
 * The Dart side publishes the engine snapshot here; the home screen widget and
 * the floating overlay read it. Widget actions are written back into
 * [PREF_CONTROL_COMMAND] and picked up by the upload engine.
 *
 * There is exactly one upload engine (in Dart). This store only mirrors its
 * state — it never performs uploads itself.
 */
object UploadStateStore {

    const val PREF_FILE = "dms_widget_state"
    const val PREF_CONTROL_COMMAND = "dms_control_command"
    const val PREF_PENDING_START = "dms_pending_start"

    const val KEY_STATUS = "status"
    const val KEY_TOTAL_FILES = "totalFiles"
    const val KEY_COMPLETED_FILES = "completedFiles"
    const val KEY_FAILED_FILES = "failedFiles"
    const val KEY_PENDING_FILES = "pendingFiles"
    const val KEY_PROGRESS = "progress"
    const val KEY_BYTES_SENT = "bytesSent"
    const val KEY_BYTES_TOTAL = "bytesTotal"
    const val KEY_SPEED = "speed"
    const val KEY_ETA_SECONDS = "etaSeconds"
    const val KEY_CURRENT_FILE = "currentFileName"
    const val KEY_DESTINATION = "activeDestinationName"
    const val KEY_IS_PAUSED = "isPaused"
    const val KEY_UPDATED_AT = "updatedAt"

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(PREF_FILE, Context.MODE_PRIVATE)

    /** Publishes the engine snapshot to the platform. */
    fun publish(context: Context, state: Map<String, Any?>) {
        prefs(context).edit {
            putString(KEY_STATUS, state[KEY_STATUS] as? String ?: "idle")
            putInt(KEY_TOTAL_FILES, (state[KEY_TOTAL_FILES] as? Number)?.toInt() ?: 0)
            putInt(KEY_COMPLETED_FILES, (state[KEY_COMPLETED_FILES] as? Number)?.toInt() ?: 0)
            putInt(KEY_FAILED_FILES, (state[KEY_FAILED_FILES] as? Number)?.toInt() ?: 0)
            putInt(KEY_PENDING_FILES, (state[KEY_PENDING_FILES] as? Number)?.toInt() ?: 0)
            putFloat(KEY_PROGRESS, (state[KEY_PROGRESS] as? Number)?.toFloat() ?: 0f)
            putLong(KEY_BYTES_SENT, (state[KEY_BYTES_SENT] as? Number)?.toLong() ?: 0L)
            putLong(KEY_BYTES_TOTAL, (state[KEY_BYTES_TOTAL] as? Number)?.toLong() ?: 0L)
            putFloat(KEY_SPEED, (state[KEY_SPEED] as? Number)?.toFloat() ?: 0f)
            putInt(KEY_ETA_SECONDS, (state[KEY_ETA_SECONDS] as? Number)?.toInt() ?: 0)
            putString(KEY_CURRENT_FILE, state[KEY_CURRENT_FILE] as? String ?: "")
            putString(KEY_DESTINATION, state[KEY_DESTINATION] as? String ?: "")
            putBoolean(KEY_IS_PAUSED, state[KEY_IS_PAUSED] as? Boolean ?: false)
            putLong(KEY_UPDATED_AT, (state[KEY_UPDATED_AT] as? Number)?.toLong() ?: 0L)
        }
    }

    /** Returns the current snapshot as a map. */
    fun snapshot(context: Context): Map<String, Any?> {
        val p = prefs(context)
        return mapOf(
            KEY_STATUS to (p.getString(KEY_STATUS, "idle") ?: "idle"),
            KEY_TOTAL_FILES to p.getInt(KEY_TOTAL_FILES, 0),
            KEY_COMPLETED_FILES to p.getInt(KEY_COMPLETED_FILES, 0),
            KEY_FAILED_FILES to p.getInt(KEY_FAILED_FILES, 0),
            KEY_PENDING_FILES to p.getInt(KEY_PENDING_FILES, 0),
            KEY_PROGRESS to p.getFloat(KEY_PROGRESS, 0f).toDouble(),
            KEY_BYTES_SENT to p.getLong(KEY_BYTES_SENT, 0L),
            KEY_BYTES_TOTAL to p.getLong(KEY_BYTES_TOTAL, 0L),
            KEY_SPEED to p.getFloat(KEY_SPEED, 0f).toDouble(),
            KEY_ETA_SECONDS to p.getInt(KEY_ETA_SECONDS, 0),
            KEY_CURRENT_FILE to (p.getString(KEY_CURRENT_FILE, "") ?: ""),
            KEY_DESTINATION to (p.getString(KEY_DESTINATION, "") ?: ""),
            KEY_IS_PAUSED to p.getBoolean(KEY_IS_PAUSED, false),
            KEY_UPDATED_AT to p.getLong(KEY_UPDATED_AT, 0L)
        )
    }

    /**
     * Queues a control command for the upload engine.
     *
     * The timestamp makes the command idempotent across the two Dart isolates
     * (the UI isolate and the foreground service isolate).
     */
    fun sendControlCommand(context: Context, command: String) {
        prefs(context).edit {
            putString(PREF_CONTROL_COMMAND, "${System.currentTimeMillis()}:$command")
        }
    }

    /** Reads and clears the pending control command. */
    fun consumeControlCommand(context: Context): Pair<Long, String>? {
        val p = prefs(context)
        val raw = p.getString(PREF_CONTROL_COMMAND, null) ?: return null
        val parts = raw.split(":", limit = 2)
        val timestamp = parts[0].toLongOrNull() ?: return null
        val command = if (parts.size > 1) parts[1] else ""
        p.edit { remove(PREF_CONTROL_COMMAND) }
        return Pair(timestamp, command)
    }

    /** Marks that the user asked to start an upload from a widget. */
    fun setPendingStart(context: Context, pending: Boolean) {
        prefs(context).edit { putBoolean(PREF_PENDING_START, pending) }
    }

    /** Reads and clears the pending start flag. */
    fun consumePendingStart(context: Context): Boolean {
        val p = prefs(context)
        val pending = p.getBoolean(PREF_PENDING_START, false)
        if (pending) p.edit { putBoolean(PREF_PENDING_START, false) }
        return pending
    }
}
