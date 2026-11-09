# Discord bot and webhook setup

The app supports two kinds of destination, and both are authorised ways of sending
messages to Discord:

- **Webhooks** — a webhook URL that posts to one channel.
- **Bot accounts** — a bot token that posts to any channel the bot can see.

The app never asks for, stores or uses a Discord *user* account token, and it does not
automate a normal user account.

---

## Creating a bot

1. Open the [Discord Developer Portal](https://discord.com/developers/applications) and
   click **New Application**.
2. Give it a name (for example *Discord Media Sender*) and create it.
3. On the **Bot** page click **Reset Token** and copy the token. It is shown **once** —
   store it somewhere safe. The app validates the token with `GET /users/@me` and shows
   the bot's username.
4. Open the **OAuth2 → URL Generator** page:
   - **Scopes:** `bot`
   - **Bot permissions:** `View Channels`, `Send Messages`, `Attach Files`,
     `Embed Links`, `Read Message History`
   - For webhook creation, additionally tick **Manage Webhooks**.
5. Open the generated URL and invite the bot to your server.
6. In the app: **More → Credential Manager → Bot profiles → Add profile**, paste the token
   and give the profile a name. Press **Validate** — the app calls `GET /users/@me` and
   then lists the servers the bot has joined.

### Required permissions

| Permission | Needed for |
|---|---|
| View Channel | Seeing the channel |
| Send Messages | Posting a message |
| Attach Files | Uploading media |
| Manage Webhooks | Creating a webhook through the app |
| Read Message History | Reading back what was sent (optional) |

A bot without **Attach Files** can post text but every media upload fails with
`50013 Missing permission`.

### Why a bot cannot always be invited to a server

If the server owner has disabled the permission to add apps, the bot cannot be invited at
all. The app cannot work around that — it can only report the error from Discord.

---

## Using a webhook instead of a bot

A webhook posts to exactly one channel and needs no bot membership:

1. In Discord, open the channel → **Edit Channel** → **Integrations** → **Webhooks**.
2. Click **New Webhook**, give it a name and choose a channel.
3. Copy the webhook URL. It looks like:
   `https://discord.com/api/webhooks/123456789012345678/aBcDeF-gH_iJkLmNoPq`
4. In the app: **More → Credential Manager → Webhook profiles → Add profile**, paste the
   URL and validate it. The app calls the webhook endpoint and shows the webhook name.

The app only accepts webhook URLs whose host is `discord.com` (or `discordapp.com`,
`ptb.` or `canary.`). Anything else is rejected — this prevents the app from being used
to post to an unrelated third-party endpoint.

---

## Creating a webhook from inside the app

If you have a bot with **Manage Webhooks**:

1. **More → Credential Manager → Bot profiles → Create webhook**.
2. Pick the bot profile, then the server and the channel, and enter a webhook name.
3. The app calls `POST /channels/<channel_id>/webhooks`.

**Discord returns the webhook token only once, in the response to that call.** The app
cannot show it afterwards, so the dialog asks you to paste the token that Discord
displayed. The app then assembles the full URL and stores it like any other webhook.
The app never fabricates a webhook URL.

---

## Configuring a destination

**More → Distribution → Add destination**, then choose:

- **Webhook URL** — a name and the webhook URL.
- **Bot + channel** — a bot profile, the channel id and an optional channel name.

The channel id is the snowflake that Discord shows when you enable *Copy Channel ID* in
the channel settings (right-click the channel → *Copy Channel ID*). It is a 17–20 digit
number.

Each destination can be enabled or disabled independently, has its own priority, its own
queue, its own retry counter, its own error history and its own rate-limit state.

---

## Distribution modes

| Mode | Behaviour |
|---|---|
| Broadcast to all | Every enabled destination receives every file |
| Manual selection | Only the destinations you ticked receive the file |
| Round robin | The destinations take turns, one file each |
| Sequential | The files are sent to the first destination, then the next |
| Rule based | A destination receives a file when its rule matches |

### Rule syntax

A rule is written in the destination's *note* field as a comma separated list:

| Rule | Matches |
|---|---|
| `ext:jpg` | Files with the `.jpg` extension |
| `cat:image` | Everything in the image category |
| `size:25` | Files up to 25 MB |

A file is sent to a destination when **any** of its rules matches.

---

## Rate limits

Discord returns `429 Too Many Requests` when a route is exhausted. The app handles this
exactly as the API prescribes:

1. It reads `retry_after` from the response body (or `x-ratelimit-reset-after` from the
   headers).
2. It waits that long.
3. It repeats the request, up to five times per request.
4. A global cooldown is applied when Discord sets `x-ratelimit-global: true`.

The bucket state is also tracked locally, so the app does not fire requests it already
knows are exhausted. A destination that is currently rate limited is shown with a *Rate
limited* badge, and its `rate_limit_until` timestamp is stored.

### Duplicate protection during retries

Discord cannot guarantee exactly-once delivery for a request that was interrupted after
the server received it. The app therefore keeps a `delivery_records` row for every
successful delivery, keyed by `(sha256, destination_id)`. Before a file is sent, the
engine checks that table; a file already delivered to that destination is not sent to it
again. This is a reconciliation safeguard, not a claim of perfect exactly-once delivery.

---

## File limits

| Limit | Value |
|---|---|
| Max file size accepted by Discord | 100 MB (25 MB on unboosted servers) |
| Max request size accepted by Discord | 500 MB across all files in one request |
| Max files per request | 10 |
| ZIP import limit in the app | 5 GB |

The app's own **maximum file size** setting (Settings → Upload) is applied before a file
is queued, and files above it are skipped with a message.
