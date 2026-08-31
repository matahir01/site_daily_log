# Site Daily Log

Offline-first construction site tracking app. Multi-project → multi-site → daily logs + expenses + materials/equipment, with on-device PDF/Excel reports and optional zero-cost Google Drive backup. No paid backend, no server costs.

## Getting an installable APK

**Option A — let GitHub build it (no local Flutter install needed).**
1. Create a new GitHub repo and push this folder to it as-is (the `android/`, `lib/`, `pubspec.yaml`, and `.github/workflows/build-apk.yml` all need to be committed together — the workflow restores the hand-configured Android files from git, so they must already be tracked).
2. Push to `main` (or open the repo's **Actions** tab and run **Build APK** manually via "Run workflow").
3. When the run finishes, open it and download the `site-daily-log-apk` artifact — that's your installable `.apk`.
4. This gives you a working test build fast. Before real distribution, see "Before publishing to Play Store" below (unique `applicationId`, real signing key) — the CI build above uses **debug signing**, same as a local `flutter run`, so it installs fine on a device but shouldn't go to the Play Store as-is.

**Option B — build locally.** Follow "First-time setup" below, then run:
```
flutter build apk --release
```
The APK lands at `build/app/outputs/flutter-apk/app-release.apk`.

## First-time setup

This zip contains the app's source code (`lib/`), a partial Android config, and assets — but not the full Flutter scaffolding (that's generated, not hand-written). Do this once:

1. Extract the zip somewhere, e.g. `~/dev/site_daily_log`.
2. Run `flutter create .` **inside that folder**. This generates the full `android/`, and platform boilerplate Flutter needs, without touching your `lib/` folder.
   - ⚠️ It WILL regenerate `android/app/src/main/AndroidManifest.xml` and `android/app/build.gradle.kts` with defaults — after running `flutter create .`, re-copy the two files from this zip back into place (they already have the camera/GPS/storage permissions and FileProvider setup configured). Same for `assets/icon/app_icon.png` and `res/xml/file_paths.xml` if overwritten.
3. Run `flutter pub get` to install dependencies.
4. Generate the app icon into all required resolutions:
   ```
   dart run flutter_launcher_icons
   ```
5. Connect a device or start an emulator, then:
   ```
   flutter run
   ```

## What's included

- **Multi-project → multi-site structure**: unlimited projects, each with unlimited sites.
- **Daily logs**: weather, crew count, work completed, issues, photos (camera, auto-compressed), GPS tag (lat/lng captured automatically).
- **Materials & equipment tracking**: log deliveries and heavy machinery per daily log (item, quantity, unit, category), stored in a dedicated `materials_and_equipment` table.
- **Expenses**: amount, category (materials/labor/equipment/other), note, receipt photo.
- **Edit/delete**: tap any log or expense to edit; delete icon removes it (with confirmation). Deleting a project or site cascades to delete everything under it.
- **Reports — generated entirely on-device**:
  - PDF: per-site and whole-project, via the app bar icon.
  - Excel (`.xlsx`): per-site and whole-project, via the app bar icon — includes Daily Logs, Materials & Equipment, and Expenses sheets.
  - Both share via the native Android share sheet (email, WhatsApp, Drive, etc.) — nothing is uploaded anywhere by the app itself unless you explicitly use Drive backup below.
- **Google Drive backup (zero-cost)**: the cloud-sync icon on the project dashboard backs up / restores the local SQLite database to the signed-in user's **hidden** Drive "App Data" folder (`drive.appdata` scope only — not general Drive access, and invisible in the user's normal Drive UI). No Firebase, AWS, or Supabase involved — it rides entirely on the user's own free Google Drive quota. Daily logs show a **Synced** / **Pending Sync** badge reflecting whether they've been included in the most recent backup.
- **Permissions configured**: camera, fine/coarse location, storage/media access, internet, all declared in `AndroidManifest.xml`.
- **App icon**: simple hard-hat placeholder icon on orange background — swap `assets/icon/app_icon.png` with your own branding anytime and re-run step 4.

## Enabling Google Drive backup (required one-time setup)

`google_sign_in` needs an OAuth client registered against your app's package name and signing certificate before sign-in will work. This is a one-time, free setup in Google Cloud Console:

1. Create (or reuse) a project at [console.cloud.google.com](https://console.cloud.google.com).
2. Enable the **Google Drive API** for that project (APIs & Services → Library).
3. Configure the **OAuth consent screen** (External is fine for testing; add your own Google account as a test user if the app isn't published/verified).
4. Under APIs & Services → Credentials, create an **OAuth 2.0 Client ID** of type **Android**:
   - Package name: `com.sitedailylog.app` (or whatever you renamed `applicationId` to).
   - SHA-1 certificate fingerprint: get it via `cd android && ./gradlew signingReport` (use the `debug` variant's SHA1 for local testing; add another Android OAuth client with your **release** keystore's SHA-1 before publishing).
5. No `google-services.json` or Firebase project is required — `google_sign_in` on Android resolves the OAuth client purely from the package name + SHA-1 registered above.
6. Re-run `flutter run` after registering — sign-in triggers automatically the first time you tap the cloud-sync icon and choose "Back up now."

If backup fails with an auth error, double-check the SHA-1 matches the keystore you're currently building with (debug vs. release use different fingerprints).

## Database migrations

`lib/db/database_helper.dart` is versioned (`_dbVersion`) with an `onUpgrade` path, so existing installs upgrade in place without losing data:
- **v1 → v2**: adds `is_synced` to `daily_logs` (for the sync badges) and creates the new `materials_and_equipment` table. `weather`, `lat`/`lng` already existed on `daily_logs` from v1 and are reused rather than duplicated.

When you add fields again later, bump `_dbVersion` and add another `if (oldVersion < N)` branch — never edit an already-shipped migration step.

## Before publishing to Play Store

- Change `applicationId` in `android/app/build.gradle.kts` from `com.sitedailylog.app` to something unique to you (and register a matching **release** SHA-1 OAuth client, see above).
- Replace the debug signing config in `build.gradle.kts` with a real release keystore.
- Consider replacing the placeholder icon with real branding.
