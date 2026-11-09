package com.dmsender.discord_media_sender

import android.content.ContentUris
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import java.io.File
import java.io.FileOutputStream

/**
 * A file discovered inside a Storage Access Framework tree.
 *
 * [path] is a real file path when Android exposes one, otherwise the path of a
 * copy inside the app cache.
 */
data class TreeFile(
    val path: String,
    val name: String,
    val size: Long,
    val mimeType: String,
    val modifiedAt: Long,
    val isDirectory: Boolean
)

/**
 * Walks a Storage Access Framework tree and resolves every document to a file
 * the app can read.
 *
 * Android 10+ hides the real path of most documents, so the content is copied
 * into the app cache when no path is available. Documents on the primary
 * volume (the usual case for a media folder) keep their real path, which
 * means folder monitoring stays live for them.
 */
object TreeResolver {

    /** Returns every file below the tree [uri]. */
    fun listTree(context: Context, treeUri: Uri, maxFiles: Int = 2000): List<TreeFile> {
        val results = mutableListOf<TreeFile>()
        try {
            val documentId = DocumentsContract.getTreeDocumentId(treeUri)
            val childrenUri =
                DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, documentId)
            val projection = arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_SIZE,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED,
                DocumentsContract.Document.COLUMN_FLAGS
            )

            context.contentResolver.query(childrenUri, projection, null, null, null)
                ?.use { cursor ->
                    while (cursor.moveToNext() && results.size < maxFiles) {
                        val childId = cursor.getString(0) ?: continue
                        val name = cursor.getString(1) ?: continue
                        val size = if (cursor.isNull(2)) 0L else cursor.getLong(2)
                        val mime = cursor.getString(3) ?: "application/octet-stream"
                        val modified = if (cursor.isNull(4)) 0L else cursor.getLong(4)
                        val flags = if (cursor.isNull(5)) 0 else cursor.getInt(5)
                        val isDirectory =
                            mime == DocumentsContract.Document.MIME_TYPE_DIR

                        val childUri = DocumentsContract.buildDocumentUriUsingTree(
                            treeUri,
                            childId
                        )

                        if (isDirectory) {
                            // Recurse into sub folders.
                            results.addAll(
                                listTree(context, childUri, maxFiles - results.size)
                            )
                            continue
                        }

                        val resolved = resolveDocument(
                            context = context,
                            documentUri = childUri,
                            treeUri = treeUri,
                            documentId = childId,
                            name = name,
                            size = size
                        ) ?: continue

                        results.add(
                            TreeFile(
                                path = resolved,
                                name = name,
                                size = size,
                                mimeType = mime,
                                modifiedAt = modified,
                                isDirectory = false
                            )
                        )
                    }
                }
        } catch (error: Exception) {
            return results
        }
        return results
    }

    /**
     * Resolves a single document to a readable local path.
     *
     * Primary-volume documents keep their real path; everything else is copied
     * into the app cache.
     */
    private fun resolveDocument(
        context: Context,
        documentUri: Uri,
        treeUri: Uri,
        documentId: String,
        name: String,
        size: Long
    ): String? {
        // Primary volume documents expose a stable real path.
        if (documentId.startsWith("primary:")) {
            val relative = documentId.removePrefix("primary:")
            val base = Environment.getExternalStorageDirectory()
            val real = File(base, relative)
            if (real.exists() && real.canRead()) return real.absolutePath
        }

        // MediaStore backed items expose the `_data` column.
        queryDataColumn(context, documentUri)?.let { dataPath ->
            val file = File(dataPath)
            if (file.exists() && file.canRead()) return file.absolutePath
        }

        // Fall back to a copy in the app cache.
        return copyToCache(context, documentUri, name)
    }

    /** Copies the content behind [uri] into the app cache. */
    fun copyToCache(context: Context, uri: Uri, displayName: String?): String? {
        val name = displayName?.takeIf { it.isNotBlank() }
            ?: "media_${System.currentTimeMillis()}"
        val directory = File(context.cacheDir, "picked").apply { mkdirs() }
        val target = File(directory, name)
        if (target.exists() && target.length() == 0L) target.delete()

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
        var cursor: Cursor? = null
        try {
            cursor = context.contentResolver.query(uri, arrayOf("_data"), null, null, null)
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

    /** Returns the display name of a content URI. */
    fun displayName(context: Context, uri: Uri): String? {
        var cursor: Cursor? = null
        try {
            cursor = context.contentResolver.query(
                uri,
                arrayOf(android.provider.MediaStore.MediaColumns.DISPLAY_NAME),
                null,
                null,
                null
            )
            if (cursor != null && cursor.moveToFirst()) {
                val index =
                    cursor.getColumnIndex(android.provider.MediaStore.MediaColumns.DISPLAY_NAME)
                if (index >= 0) return cursor.getString(index)
            }
        } catch (error: Exception) {
            // ignore
        } finally {
            cursor?.close()
        }
        return null
    }

    /** Builds a content URI for a media id. */
    fun contentUriFor(id: Long): Uri = ContentUris.withAppendedId(
        android.provider.MediaStore.Files.getContentUri(
            android.provider.MediaStore.VOLUME_EXTERNAL
        ),
        id
    )

    /** The Android version this code was written for. */
    val sdkInt: Int = Build.VERSION.SDK_INT
}
