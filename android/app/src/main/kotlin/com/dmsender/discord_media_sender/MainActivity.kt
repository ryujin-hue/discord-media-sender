package com.dmsender.discord_media_sender

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import android.widget.Toast
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * The Flutter host activity.
 *
 * It hosts two platform channels:
 *  * `bridge` — mirrors the upload engine state to the Android widgets and
 *    forwards widget commands, overlay control and APK installation.
 *  * `media`  — resolves Storage Access Framework URIs into real files that
 *    the upload engine can read.
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL_BRIDGE = "com.dmsender.discord_media_sender/bridge"
        const val CHANNEL_MEDIA = "com.dmsender.discord_media_sender/media"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_BRIDGE)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                handleBridgeCall(call, result)
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_MEDIA)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                handleMediaCall(call, result)
            }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        // A widget "start upload" action launches the app; the flag is consumed
        // by the Flutter side once the engine is up.
        if (UploadStateStore.consumePendingStart(this)) {
            UploadStateStore.sendControlCommand(this, "start")
        }
    }

    // -------------------------------------------------------------------------
    // Bridge channel
    // -------------------------------------------------------------------------

    private fun handleBridgeCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "publishState" -> {
                val state = call.arguments as? Map<String, Any?> ?: emptyMap()
                UploadStateStore.publish(this, state)
                UploadWidgetProvider.refreshAll(this)
                FloatingOverlayService.refresh(this)
                result.success(null)
            }

            "getState" -> result.success(UploadStateStore.snapshot(this))

            "setOverlay" -> {
                val enabled = (call.argument<Any?>("enabled") as? Boolean) ?: false
                val ok = if (enabled) {
                    FloatingOverlayService.start(this)
                } else {
                    FloatingOverlayService.stop(this)
                }
                result.success(ok)
            }

            "refreshOverlay" -> {
                FloatingOverlayService.refresh(this)
                result.success(null)
            }

            "refreshWidget" -> {
                UploadWidgetProvider.refreshAll(this)
                result.success(null)
            }

            "hasOverlayPermission" -> {
                result.success(Settings.canDrawOverlays(this))
            }

            "openOverlaySettings" -> {
                try {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:$packageName")
                    )
                    startActivity(intent)
                    result.success(null)
                } catch (error: Exception) {
                    result.error("overlay_settings", error.message, null)
                }
            }

            "installApk" -> {
                val path = call.argument<Any?>("path") as? String
                if (path.isNullOrEmpty()) {
                    result.error("invalid_path", "No APK path was supplied.", null)
                    return
                }
                try {
                    val ok = installApk(path)
                    result.success(ok)
                } catch (error: Exception) {
                    result.error("install_failed", error.message, null)
                }
            }

            "openUrl" -> {
                val url = call.argument<Any?>("url") as? String
                if (url.isNullOrEmpty()) {
                    result.error("invalid_url", "No URL was supplied.", null)
                    return
                }
                try {
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(intent)
                    result.success(true)
                } catch (error: Exception) {
                    result.error("open_url_failed", error.message, null)
                }
            }

            else -> result.notImplemented()
        }
    }

    /**
     * Validates and launches the Android package installer for [apkPath].
     *
     * The APK must use the same application id as the installed app and must
     * declare a higher version code. The system always shows its own approval
     * dialog; nothing is installed silently.
     */
    private fun installApk(apkPath: String): Boolean {
        val file = File(apkPath)
        if (!file.exists()) {
            Toast.makeText(this, "The downloaded file could not be found.", Toast.LENGTH_LONG).show()
            return false
        }

        val packageManager = packageManager
        val archive = packageManager.getPackageArchiveInfo(apkPath, 0)
        if (archive == null) {
            Toast.makeText(this, "The downloaded file is not a valid APK.", Toast.LENGTH_LONG).show()
            return false
        }

        val archivePackageName = archive.packageName
        if (archivePackageName != packageName) {
            Toast.makeText(
                this,
                "This APK belongs to a different app ($archivePackageName) and was not installed.",
                Toast.LENGTH_LONG
            ).show()
            return false
        }

        val installed = try {
            packageManager.getPackageInfo(packageName, 0)
        } catch (error: Exception) {
            null
        }

        val newVersionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            archive.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            archive.versionCode.toLong()
        }
        val installedVersionCode = installed?.let {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                it.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                it.versionCode.toLong()
            }
        } ?: 0L

        if (newVersionCode <= installedVersionCode) {
            Toast.makeText(this, "This build is not newer than the installed version.", Toast.LENGTH_LONG).show()
            return false
        }

        val authority = "$packageName.fileprovider"
        val contentUri = FileProvider.getUriForFile(this, authority, file)

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(contentUri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        try {
            startActivity(intent)
            return true
        } catch (error: Exception) {
            Toast.makeText(this, "No package installer is available on this device.", Toast.LENGTH_LONG).show()
            return false
        }
    }

    // -------------------------------------------------------------------------
    // Media channel
    // -------------------------------------------------------------------------

    private fun handleMediaCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "resolvePath" -> {
                val uriString = call.argument<Any?>("uri") as? String
                val name = call.argument<Any?>("name") as? String
                if (uriString.isNullOrEmpty()) {
                    result.error("invalid_uri", "No URI was supplied.", null)
                    return
                }
                try {
                    val path = MediaPathResolver.resolve(this, Uri.parse(uriString), name)
                    if (path == null) {
                        result.error("unresolved", "The selected file could not be read.", null)
                    } else {
                        result.success(path)
                    }
                } catch (error: Exception) {
                    result.error("resolve_failed", error.message, null)
                }
            }

            "listTreeFiles" -> {
                val uriString = call.argument<Any?>("uri") as? String
                if (uriString.isNullOrEmpty()) {
                    result.error("invalid_uri", "No URI was supplied.", null)
                    return
                }
                try {
                    val files = TreeResolver.listTree(this, Uri.parse(uriString))
                    val payload = files.map { file ->
                        mapOf(
                            "path" to file.path,
                            "name" to file.name,
                            "size" to file.size,
                            "mimeType" to file.mimeType,
                            "modifiedAt" to file.modifiedAt
                        )
                    }
                    result.success(payload)
                } catch (error: Exception) {
                    result.error("tree_failed", error.message, null)
                }
            }

            "readBytes" -> {
                val uriString = call.argument<Any?>("uri") as? String
                if (uriString.isNullOrEmpty()) {
                    result.error("invalid_uri", "No URI was supplied.", null)
                    return
                }
                try {
                    val bytes = contentResolver.openInputStream(Uri.parse(uriString))?.use {
                        it.readBytes()
                    }
                    if (bytes == null) {
                        result.error("unreadable", "The selected file could not be read.", null)
                    } else {
                        result.success(bytes)
                    }
                } catch (error: Exception) {
                    result.error("read_failed", error.message, null)
                }
            }

            else -> result.notImplemented()
        }
    }
}
