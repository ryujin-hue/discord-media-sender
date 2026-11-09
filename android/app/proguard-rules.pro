# Flutter / Dart
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Play Core (referenced by flutter_foreground_task)
-dontwarn com.google.android.play.core.**

# Keep the plugin entry points that use reflection.
-keep class com.pravera.flutter_foreground_task.** { *; }

# AndroidX
-keep class androidx.core.content.FileProvider { *; }

# The widget and overlay are referenced from the manifest only.
-keep class com.dmsender.discord_media_sender.UploadWidgetProvider { *; }
-keep class com.dmsender.discord_media_sender.FloatingOverlayService { *; }
