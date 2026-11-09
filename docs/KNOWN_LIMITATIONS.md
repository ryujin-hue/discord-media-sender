# Known limitations

This document describes the limits that come from Android and from Discord, and the
places where the app deliberately does less than the marketing wording might suggest.

---

## Android background execution

- **There is no unlimited background operation.** Uploads are kept alive by a foreground
  service with a persistent notification. If the user revokes the notification permission,
  swipes the service away or the system kills it for lack of resources, the transfer
  stops. The queue is not lost — it is persisted and resumes when the service starts
  again.
- **Folder monitoring is polled, not event driven.** Android has no API that lets an app
  watch a folder for new files continuously. The app scans the watched folders when it
  runs, when the user triggers a scan and on a periodic pass while the app is open. The
  app states this in the Auto Upload screen rather than promising continuous watching.
- **Storage Access Framework URIs.** When the user picks a file through the system
  picker, Android may not expose a real path. In that case the app copies the content
  into its own cache first. For a multi-gigabyte file this needs temporary free space and
  takes time — the copy happens before the upload starts.
- **Media permissions are granular on Android 13+.** With the "selected photos" option the
  app only sees the items the user picked, so a watched folder outside that selection
  cannot be scanned.
- **The overlay needs a special permission.** `SYSTEM_ALERT_WINDOW` is granted per app in
  *Settings → Special app access*. The overlay is never started without it, and the user
  can stop it at any time.
- **Background widgets.** The home-screen widget is refreshed by the engine on every
  state change and by the system at least every 30 minutes. It is not a live stream, so
  a value can lag by a few seconds.

## Discord

- **100 MB per file.** Discord's limit for a normal server is 25 MB; boosted servers
  allow 100 MB. The app uses 100 MB as its hard check and reports Discord's own error
  when the server is more restrictive.
- **500 MB per request** across all files in a single multipart request, and **10 files**
  per request.
- **Webhooks cannot be edited.** The app can create a webhook and it can send through it,
  but Discord offers no API to change an existing webhook's name, avatar or channel — the
  user has to do that in the Discord client.
- **The webhook token is shown once.** `POST /channels/<id>/webhooks` returns the token
  exactly once. The app asks the user to paste it and never invents a webhook URL.
- **Rate limits are per route and per bucket.** The app honours `retry_after` and the
  `x-ratelimit-*` headers, but a very large upload to a busy route can still be delayed
  by Discord.
- **Attachment URLs are not permanent.** Discord CDN links for uploaded files can expire.
  The app stores the message id and the URL as a reference and does not treat them as a
  durable archive.
- **No user accounts.** The app only supports webhooks and bot tokens. It cannot send as
  a normal user and does not automate user accounts.

## Delivery guarantees

- **Exactly-once delivery cannot be guaranteed.** If the connection drops after Discord
  received a request but before the app saw the response, the app cannot know whether the
  message was created. Instead of claiming perfect semantics, the app reconciles through
  the `delivery_records` table: a file that is already recorded as delivered to a
  destination is not sent to that destination again. A duplicate is therefore possible
  in that narrow window, and it is surfaced in the history rather than hidden.

## Storage

- **The media gallery is local.** There is no cloud backend. Archived media stays on the
  device. The architecture leaves room for a remote provider, but the app does not
  describe local storage as cloud storage.
- **Archiving is logical by default.** Archiving marks the entry and writes a record; the
  file stays where it is. Moving the file into the app's archive folder is opt-in, and
  permanent deletion always requires an explicit confirmation.
- **Compression is image-only.** JPEG and PNG files are re-encoded with the `image`
  package. Video compression is not implemented — re-encoding a video would require a
  native codec, and the app does not pretend otherwise.
- **Thumbnails are generated for videos** through the platform media store. Images and
  documents use a category icon.

## Analytics

- **The statistics cover what this app recorded.** They are computed from
  `upload_history`, `analytics_events`, `delivery_records`, `duplicate_records` and
  `archive_records`. Activity that happened outside the app is not counted.
- **Exports never contain credentials.** Bot tokens, webhook URLs and API keys are
  excluded from the CSV, JSON and PDF exports by construction — the exporters only read
  destination *names*.

## Updates

- **A 2.0 build cannot be installed over the supplied 1.0 build**, because that build is
  unsigned and Android requires the same signing identity for an in-place update. The
  first 2.0 installation has to be a fresh install; every release after that installs in
  place as long as the same keystore is used.
- **The update check is throttled** to one check per 6 hours, with a manual override.
- **The updater needs the GitHub API to be reachable.** Without network access it reports
  the failure and the installed version stays untouched.

## Credentials

- **Uninstalling the app or clearing its data removes the stored credentials.** The
  Keystore key is destroyed together with the application data.
- **A lost keystore breaks the upgrade path** for every existing installation — see
  [`SIGNING.md`](SIGNING.md).
- **Token validation only proves the token is valid**, not that it has every permission.
  The app verifies the identity with `GET /users/@me` and lists the servers the bot can
  see; a missing permission only shows up when a file is actually sent.
