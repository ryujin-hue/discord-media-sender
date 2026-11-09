# GitHub Releases and automatic versioning

The repository contains two workflows:

| Workflow | Trigger | Purpose |
|---|---|---|
| `.github/workflows/release.yml` | Push to `main`, a `v*` tag, a pull request, or manually | Validate, test, build a signed APK and publish the release |
| `.github/workflows/version.yml` | Manual (`workflow_dispatch`) | Raise the semantic version, commit it and tag the release |

---

## Repository setup

The workflows expect the repository to be **`tukiza7-debug/discord-media-sender`** — that
is the repository the 1.0 build already checked for updates, and it is hard-coded in
`lib/core/constants.dart`:

```dart
static const String githubOwner = 'tukiza7-debug';
static const String githubRepo = 'discord-media-sender';
static const String latestReleaseApi =
    'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest';
```

If the repository is hosted somewhere else, change these three constants (and the
`githubRepoUrl`) and rebuild.

### Required repository settings

| Setting | Value | Why |
|---|---|---|
| **Settings → Actions → General → Workflow permissions** | *Read and write* | The release workflow creates the release with `GITHUB_TOKEN` |
| **Settings → Actions → Secrets and variables → Actions** | The four `DMS_*` secrets | Signing — see [`SIGNING.md`](SIGNING.md) |
| **Settings → General → Danger zone** | *Allow admins to bypass branch protection* if the release has to bypass it | Not required by default |

The `release.yml` workflow already declares `permissions: contents: write`, so no extra
PAT is needed as long as the default workflow permission is *read and write*.

---

## Publishing a release

### Automatic (recommended)

1. Run the **Version bump** workflow (`Actions → Version bump → Run workflow`).
2. Pick the release type:
   - `patch` → `2.0.0` becomes `2.0.1`
   - `minor` → `2.0.0` becomes `2.1.0`
   - `major` → `2.0.0` becomes `3.0.0`
   - `beta` → `2.1.0-beta.1`
3. The workflow updates `pubspec.yaml`, commits, tags `v<version>` and pushes the tag.
4. The tag triggers `release.yml`, which builds and publishes the release.

### Manual

```bash
# 1. Bump the version (version: MAJOR.MINOR.PATCH+CODE)
$EDITOR pubspec.yaml
git commit -am "chore(release): 2.1.0"
git push

# 2. Tag and push
git tag -a v2.1.0 -m "2.1.0"
git push origin v2.1.0
```

The tag triggers `release.yml`.

### From the Actions tab

`Actions → Build and Release → Run workflow`. The inputs are:

| Input | Values | Meaning |
|---|---|---|
| `channel` | `stable`, `beta` | Passed through to the updater's channel filter |
| `dry_run` | `true`, `false` | `true` builds and uploads the artifact without creating a release |

---

## What the release workflow does

### `validate` job

1. `flutter pub get`
2. `dart format --output=none --set-exit-if-changed lib test` — fails on unformatted code
3. `flutter analyze --fatal-infos` — fails on any warning or info
4. `flutter test --reporter expanded`

### `build` job

1. Sets up JDK 17, Flutter 3.47.9 and the Android SDK.
2. Decodes `DMS_KEYSTORE_BASE64` into `android/keystore/dms-release.jks` and writes
   `android/key.properties` from the secrets.
3. Reads the version from `pubspec.yaml` and builds with the explicit
   `--build-name` / `--build-number` so the artifact always matches the tag.
4. Verifies the APK signature with `apksigner verify --print-certs`.
5. Uploads the APK as a workflow artifact.

### `release` job

1. Downloads the artifact.
2. Copies it to `DiscordMediaSender.apk`.
3. Generates `SHA256SUMS.txt` with `sha256sum`.
4. Publishes both files to the GitHub Release with generated release notes.

### Published assets

| File | Purpose |
|---|---|
| `DiscordMediaSender.apk` | The installable release build |
| `SHA256SUMS.txt` | The SHA-256 manifest the updater and the user verify against |

---

## Automatic versioning rules

- The version follows **SemVer**: `MAJOR.MINOR.PATCH`.
- The Android `versionCode` is `MAJOR×10000 + MINOR×100 + PATCH`.
- The `versionCode` **always increases** and is never reused.
- A pre-release is tagged `MAJOR.MINOR.PATCH-beta.N`.
- The updater treats a pre-release as *older* than the matching release, so a beta build
  never replaces a stable installation unless the beta channel is selected explicitly.

---

## Release channels

The updater supports two channels:

| Channel | Source |
|---|---|
| `stable` | The latest non-prerelease GitHub release |
| `beta` | The latest release, including pre-releases |

The channel is stored in `SharedPreferences` under `set_release_channel` and can be
changed on the **Update Manager** screen. The check itself is throttled to at most once
every 6 hours — the behaviour the 1.0 build had — and *Check for updates* forces a run.

---

## Setting up the updater in a fork

1. Fork the repository.
2. Change `githubOwner`, `githubRepo` and `latestReleaseApi` in
   `lib/core/constants.dart`.
3. Change `applicationId` in `android/app/build.gradle.kts` **only if** you do not want to
   replace the official installation. Note that changing it breaks the upgrade path for
   existing users.
4. Create a release in your fork and publish the APK with the same asset names.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| *Release job fails with "Resource not accessible by integration"* | Set the workflow permission to *Read and write* in the repository settings. |
| *The APK is signed with the debug key* | The `DMS_*` secrets are missing or the base64 is invalid. Check the build log for the warning line. |
| *The updater says "up to date" right after a release* | The check is throttled to 6 hours. Use *Check for updates*. |
| *Checksum mismatch* | The `SHA256SUMS.txt` in the release does not match the uploaded APK. Re-run the release; the workflow regenerates both files from the same artifact. |
