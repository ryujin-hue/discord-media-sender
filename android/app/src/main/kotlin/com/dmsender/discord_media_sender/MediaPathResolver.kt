package com.dmsender.discord_media_sender

import android.content.Context
import android.database.Cursor
import android.net.Uri
import java.io.File
import java.io.FileOutputStream

/**
 * Resolves a Storage Access Framework URI into a file the app can read.
 *
 * Android 10+ restricts access to the raw path of a picked document, so the
 * content is copied into the app cache when no direct path exists. The
 * upload engine, the duplicate detector and the thumbnailer all work on local
 * files, so a resolvable path is required.
 */
object MediaPathResolver {

    /** Returns a readable local path for [uri], or null when it cannot be read. */
    fun resolve(context: Context, uri: Uri, displayName: String?): String? {
        if (uri.scheme == "file") {
            val path = uri.path ?: return null
            return if (File(path).exists()) path else null
        }

        // Some providers expose the real path through the `_data` column.
        queryDataColumn(context, uri)?.let { dataPath ->
            val file = File(dataPath)
            if (file.exists() && file.canRead()) return file.absolutePath
        }

        // Fall back to copying the content into the app cache.
        return copyToCache(context, uri, displayName)
    }

    /**
     * Copies the content behind [uri] into the app cache and returns the path
     * of the copy.
     */
    fun copyToCache(context: Context, uri: Uri, displayName: String?): String? {
        val name = displayName?.takeIf { it.isNotBlank() }
            ?: "media_${System.currentTimeMillis()}"
        val directory = File(context.cacheDir, "picked").apply { mkdirs() }
        val target = File(directory, name)
        if (target.exists()) target.delete()

        return try {
            context.contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(target).use { output ->
                    input.copyTo(output, DEFAULT_BUFFER_SIZE)
                }
            } ?: return null
            target.absolutePath
        } catch (error: Exception) {
            null
        }
    }

    /** Looks up the legacy `_data` column of a content provider. */
    private fun queryDataColumn(context: Context, uri: Uri): String? {
        val projection = arrayOf("_data")
        var cursor: Cursor? = null
        try {
            cursor = context.contentResolver.query(
                uri,
                projection,
                null,
                null,
                null
            )
            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndex("_data")
                if (index >= 0) {
                    val value = cursor.getString(index)
                    if (!value.isNullOrEmpty()) return value
                }
            }
        } catch (error: Exception) {
            // Providers are allowed to reject the projection.
        } finally {
            cursor?.close()
        }
        return null
    }

}
