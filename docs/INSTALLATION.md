# Installation and updates

## Requirements

| | |
|---|---|
| Android | 7.0 Nougat (API 24) or newer |
| Architecture | arm64-v8a, armeabi-v7a or x86_64 |
| Free space | The APK plus the files you send; ZIP extraction needs temporary space |
| Network | HTTPS access to `discord.com` and `api.github.com` |

---

## Installing the APK

1. Open the [releases page](https://github.com/tukiza7-debug/discord-media-sender/releases)
   and download `DiscordMediaSender.apk` **and** `SHA256SUMS.txt`.
2. Verify the checksum:

   ```bash
   sha256sum -c SHA256SUMS.txt
   ```

   The output must read `DiscordMediaSender.apk: OK`. On Windows:

   ```powershell
   Get-FileHash .\DiscordMediaSender.apk -Algorithm SHA256
   ```

   Compare it with the value in `SHA256SUMS.txt`.
3. Install it:
   - **Over ADB:** `adb install -r DiscordMediaSender.apk`
   - **On the device:** open the downloaded file. Android asks you to allow installs from
     the app you downloaded it with (your browser or file manager). Grant that permission
     once.

> The app itself never installs anything silently. The in-app updater verifies the
> checksum, checks the application id and the version code, and then opens Android's
> own package installer, where you approve the installation.

---

## Upgrading from 1.0

The application id (`com.dmsender.discord_media_sender`) and the signing identity are
unchanged, so the 2.0 APK installs **over** the 1.0 installation:

- The upload history, the session records and the failure records are migrated into the
  new history table.
- The stored webhook URL and bot token are migrated into a named credential profile, so
  you do not have to re-enter them.
- All other local data (the media library, favourites, collections) is preserved.

Install the APK over the existing one — do **not** uninstall first. Uninstalling removes
the app's private data, including the Keystore-encrypted credentials and the database.

---

## Permissions

The app asks for permissions only when the related feature is used.

| Permission | Why it is needed | When it is requested |
|---|---|---|
| `INTERNET`, `ACCESS_NETWORK_STATE` | Talk to Discord and GitHub | Always granted at install |
| `POST_NOTIFICATIONS` | Show upload progress | First time a background upload starts |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC` | Keep uploading in the background | Granted at install, used by the service |
| `FOREGROUND_SERVICE_SPECIAL_USE` | The floating overlay service | Granted at install |
| `SYSTEM_ALERT_WINDOW` | Draw the floating overlay | When you enable the overlay |
| `WAKE_LOCK` | Prevent the CPU from sleeping during a transfer | Granted at install |
| `REQUEST_INSTALL_PACKAGES` | Install an update | When you tap *Install* in the update manager |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Keep long transfers alive | Offered once, on the onboarding screen |
| `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `READ_MEDIA_AUDIO`, `READ_MEDIA_VISUAL_USER_SELECTED` | Read media for the library | When you grant access to photos and media |
| `READ_EXTERNAL_STORAGE` (≤ API 32) | Read media on older Android versions | Same moment |
| `RECEIVE_BOOT_COMPLETED` | Restore the upload service after a reboot | Granted at install |

**Media permissions.** On Android 13+ you can grant access to *all* media or to a
*selected* set of photos. With the "selected" option the app only sees the items you
picked — folders that are not selected cannot be scanned.

---

## Background uploads

Android limits background execution. The app keeps a transfer alive with a **foreground
service** that shows a persistent notification with the current file and progress.

- Allow the notification: on Android 13+ the system asks the first time a background
  upload starts.
- Exempt the app from battery optimisation: *Settings → Apps → Discord Media Sender →
  Battery → Unrestricted*. The app offers this on the onboarding screen.
- The notification has a *Stop* action that stops the service. Queued work is not lost —
  it stays in the database and resumes the next time the app runs.

Folder monitoring is polled when the app runs and when a scan is triggered. Android does
not allow an app to watch a folder continuously in the background, so no such promise is
made anywhere in the app.

---

## The floating overlay

1. Open **More → Screen Widgets**.
2. Enable *Floating overlay*.
3. If the permission is not granted, the app opens the system page
   *Settings → Apps → Special app access → Display over other apps*.
4. Turn the permission on for Discord Media Sender and return to the app.

The panel can be dragged, collapsed and expanded, and it can be stopped at any time from
the same screen. It never shows credentials.

---

## The home-screen widget

1. Long-press the home screen → **Widgets**.
2. Find **Discord Media Sender** and drag it onto the home screen.

The widget shows the real state of the upload engine and offers Start, Pause, Resume and
Open dashboard. It is refreshed by the engine on every state change, and at least every
30 minutes by the system.

---

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| *Upload fails with "Missing permission for this channel"* | The bot cannot post in the target channel. Grant it **View Channel**, **Send Messages** and **Attach Files** there. |
| *Webhook URL is invalid* | The URL must look like `https://discord.com/api/webhooks/<id>/<token>`. The app rejects other hosts on purpose. |
| *Files larger than 100 MB are skipped* | That is Discord's per-file limit. Reduce the file size or split it. |
| *Uploads stop when the screen is off* | The foreground service was killed. Re-enable the battery optimisation exemption and allow notifications. |
| *The update check says "up to date"* | The check runs at most every 6 hours. Use *Check for updates* on the Update Manager screen to force it. |
| *The checksum does not match* | The download is corrupt or was tampered with. Download the release again and verify it before installing. |
| *The install fails with "not a newer version"* | The downloaded build has the same or a lower version code than the installed one. |
| *Credentials disappear after an update* | This should not happen — the credential profile survives an in-place update. If it does, the Keystore key was invalidated (for example by a factory reset of the keystore), in which case the credential has to be entered again. |
