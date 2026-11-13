# Background uploads

This document explains exactly what happens when you leave the app while a
transfer is running, what the app needs from you to make that work, and how
the queue behaves when the process dies.

---

## The three things that keep an upload alive

### 1. The foreground service

The transfer runs inside an Android foreground service. It shows a permanent
notification and the system does not kill it while the screen is off or the app
is in the background.

The service is started **together with the queue**: the moment a file is
queued, the engine starts the service and the upload. It is also started on a
cold start that finds pending work.

The service uses the `dataSync` foreground service type, which is the type
Android reserves for exactly this: transferring data.

| Setting | Value | Why |
|---|---|---|
| `allowWakeLock` | on | Keeps the CPU running while the screen is off |
| `allowAutoRestart` | on | A crashed service comes back |
| `autoRunOnBoot` | on | A queue that was interrupted by a reboot resumes |
| `autoRunOnMyPackageReplaced` | on | An app update does not silently drop a queue |
| `stopWithTask` | off | The service outlives the screen that started it |

The service stops itself as soon as the queue is empty, so it never keeps a
notification alive without work.

### 2. The wake lock

The service holds a wake lock while it works. Without it the CPU would sleep
between two chunks of a large file and the transfer would stall until the
screen was touched again.

### 3. The shared queue

The service does not implement a second upload path. It runs the *same*
`UploadEngine` against the *same* SQLite queue. The two Dart isolates — the
one in the app and the one in the service — share the queue through the
database.

---

## How two isolates share one queue safely

Both isolates can see the same pending job. To make sure a file is never
uploaded twice, a job has to be **claimed** before it is sent:

```
UPDATE distribution_jobs
   SET status = 'uploading', started_at = ?, heartbeat_at = ?
 WHERE id = ? AND status = 'pending'
```

The update only succeeds while the job is still pending, so exactly one
isolate wins it. The other one moves on to the next job. A file that is
already being sent is never sent a second time.

### The heartbeat

A claimed job keeps a fresh `heartbeat_at` — it is refreshed on every progress
callback and every 15 seconds by a timer, so a stalled connection still counts
as alive.

The heartbeat is what makes the recovery safe:

- **The app is cold started** (the whole process is new, so no other isolate
  can own a job): every job that is still marked as uploading goes back into
  the queue.
- **The service isolate starts** while the app is alive: only jobs whose
  heartbeat went stale are recovered. A job that the app is uploading right
  now keeps its owner.

---

## What happens in each situation

| You do this | What happens |
|---|---|
| Press Home | The service keeps running. The transfer continues with the screen off. |
| Switch to another app | Same as Home. |
| Lock the screen | Same. The wake lock keeps the CPU running. |
| Swipe the app away from the recents list | The process dies. The queue stays on disk. The next start recovers the interrupted work. |
| Force stop the app | Same as above, plus Android blocks the service from starting again until you open the app once. |
| Reboot the device | The service starts again and recovers the queue. |
| Install an update | The service starts again and recovers the queue. |
| The network drops | The upload fails, the row is marked as failed with the reason, and the job can be retried. |

---

## What the app asks of you

Android gives every app the same background budget, and the aggressive
versions of it are shut off by default. Two settings matter.

### Exempt the app from battery optimisation

*Settings → Apps → Discord Media Sender → Battery → Unrestricted*

Without this, the system is allowed to doze the app and a long transfer can
stall between two chunks. The app asks for this exemption the first time it
starts a background upload.

### Allow the notifications

On Android 13 and newer the foreground service shows a notification. The
service still runs when the permission is denied, but the notification is
hidden and the system is more willing to stop the app. Grant
*Notifications* in the app settings so the running upload is visible.

The app checks both of these and shows the result in the home screen instead
of hiding it.

---

## The widget and the overlay in the background

The home screen widget and the floating overlay read the same mirrored state
that the service publishes. Because the service isolate publishes it too, the
widget keeps showing the real progress while the app is in the background.

The widget offers three actions: **Pause**, **Resume** and **Open**. Pause and
Resume are handed to the engine through the control bus:

```
dms_control_command = {epochMs}:{pause|resume|start|cancel}
```

The timestamp makes the command idempotent, so a command is applied exactly
once even though two isolates are polling it.

Dismissing the floating overlay only hides the panel. It never cancels an
upload and never stops the service.

---

## If the upload still stops

The home screen shows a warning when work is pending and the background
service is not running. The message names the reason, for example:

| Message | What to do |
|---|---|
| The background service could not be started | Open the app once and queue the files again. |
| The background service is not running | Tap **Start** on the warning. |
| The upload was interrupted | The work was recovered and is queued again. |

The activity timeline in the home screen records every one of these events, so
the history of a background transfer is always visible.
