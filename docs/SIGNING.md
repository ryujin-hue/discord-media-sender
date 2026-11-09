# Signing and in-place upgrade compatibility

The application id is `com.dmsender.discord_media_sender` and it **must not change**:
Android refuses to install an update with a different application id, and a different
id would install side by side instead of replacing the previous version.

## The state of the 1.0 release

The `Discord Media Sender 1.0.a9.zip` that was supplied as the project reference contains
a **compiled, unsigned APK**. There is no `META-INF/CERT.RSA` and `apksigner verify`
reports `DOES NOT VERIFY — Missing META-INF/MANIFEST.MF`.

That means the original build was never signed with a release key that could be
recovered, so there is no certificate to reproduce. 2.0 therefore establishes a **new,
persistent release identity**:

| | |
|---|---|
| Application id | `com.dmsender.discord_media_sender` (unchanged) |
| Keystore | `android/keystore/dms-release.jks` |
| Alias | `dms-release` |
| Key algorithm | RSA 4096, SHA384withRSA |
| Validity | 30 years (10 950 days) |
| Certificate SHA-256 | `69:8A:C7:7D:AC:09:F8:73:FB:13:E5:15:B0:8D:BA:8E:33:75:ED:C1:AC:5D:14:50:84:93:30:67:CC:1D:67:D2` |

**Consequence:** a 2.0 APK cannot be installed *over* an unsigned 1.0 APK — Android
requires the same signing identity for an in-place update, and an unsigned package has
none. The first 2.0 installation has to be a fresh install. **From 2.0 onwards every
release must be signed with this same keystore**, and then updates install in place and
keep all user data.

> The keystore file and its passwords are part of the delivery. Store them in a password
> manager or a secure vault. **If the keystore is lost, no future release can be
> installed over an existing installation** — Android offers to uninstall it, which
> deletes the database and the stored credentials.

---

## Local builds

`android/key.properties` (git-ignored) configures the release signing:

```properties
storeFile=keystore/dms-release.jks
storePassword=<store password>
keyAlias=dms-release
keyPassword=<key password>
```

`android/app/build.gradle.kts` reads the file, falls back to the environment variables
`DMS_KEYSTORE_PATH`, `DMS_KEYSTORE_PASSWORD`, `DMS_KEY_ALIAS` and `DMS_KEY_PASSWORD`, and
finally falls back to the debug key so that a build never fails outright. When that
fallback happens the build prints a warning — check the CI log to make sure it did not
happen.

```bash
flutter build apk --release
```

The result is `build/app/outputs/flutter-apk/app-release.apk`.

Verify the signature:

```bash
$ANDROID_HOME/build-tools/35.0.0/apksigner verify --print-certs \
  build/app/outputs/flutter-apk/app-release.apk
```

---

## Creating a new keystore

Only do this if the existing one is genuinely lost — and be aware that it breaks the
upgrade path for every existing installation.

```bash
keytool -genkeypair -v \
  -keystore android/keystore/dms-release.jks \
  -alias dms-release \
  -keyalg RSA -keysize 4096 -validity 10950 \
  -storepass '<store password>' -keypass '<key password>' \
  -dname "CN=Discord Media Sender, OU=Release, O=Discord Media Sender, C=US"
```

---

## GitHub Actions secrets

The release workflow needs four secrets. Add them under
**Settings → Secrets and variables → Actions** in the repository.

| Secret | Value |
|---|---|
| `DMS_KEYSTORE_BASE64` | `base64 -w0 android/keystore/dms-release.jks` (no line breaks) |
| `DMS_KEYSTORE_PASSWORD` | The keystore password |
| `DMS_KEY_ALIAS` | `dms-release` |
| `DMS_KEY_PASSWORD` | The key password |

The workflow decodes the keystore into `android/keystore/dms-release.jks` and writes
`android/key.properties` before the build. Neither the keystore nor the passwords are
ever committed — both paths are listed in `.gitignore`.

To rotate the secrets:

```bash
base64 -w0 android/keystore/dms-release.jks | pbcopy
# paste into DMS_KEYSTORE_BASE64
```

---

## Version codes

The Android `versionCode` must strictly increase for every release — Android refuses to
install an update with an equal or lower code.

The repository derives it from the semantic version:

```
versionCode = MAJOR × 10000 + MINOR × 100 + PATCH
```

| Version | versionCode |
|---|---|
| 1.0.9 (the original build) | 15 |
| 2.0.0 | 20000 |
| 2.0.1 | 20001 |
| 2.1.0 | 20100 |
| 3.0.0 | 30000 |

This scheme guarantees monotonic growth and makes a reused code impossible as long as the
version is bumped. The `Version bump` workflow computes the next version and updates
`pubspec.yaml` automatically.

---

## How the in-app updater protects the installation

The update manager never installs an unverified APK:

1. It fetches the release metadata from
   `https://api.github.com/repos/ryujin-hue/discord-media-sender/releases/latest`.
2. It compares the versions with a full SemVer comparison (a pre-release such as
   `2.1.0-beta.1` is older than `2.1.0`).
3. It downloads `DiscordMediaSender.apk` and computes its SHA-256.
4. It compares the digest with the entry for that file in `SHA256SUMS.txt`. A missing or
   mismatching entry aborts the update.
5. **Natively**, it opens the downloaded APK with `PackageManager.getPackageArchiveInfo`
   and verifies that the package name is `com.dmsender.discord_media_sender` and that its
   `versionCode` is **higher** than the installed one.
6. Only then is Android's package installer opened. Android shows its own approval
   dialog; the app cannot and does not bypass it.

Uninstalling the previous version is never used as an update strategy — that would delete
the database and the stored credentials.
