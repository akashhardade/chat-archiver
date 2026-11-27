# Chat Archiver

Android app that keeps an incremental, per-group archive of selected WhatsApp
groups in the user's own Google Drive.

The client installs it on their own phone, types the exact titles of the
WhatsApp groups to archive and connects Google Drive. Each morning (on the
first unlock after a chosen hour) or when they tap **Sync now**, an Android
accessibility service drives WhatsApp's own **Export chat -> Without media**
flow and hands the exported transcript to the app. The Dart code merges only
the **new** messages into a per-group archive and uploads it to Drive. Nothing
is sent to any server of ours.

## What ends up in Drive

```
My Drive/WhatsApp Archive/
  <group title>/
    archive.txt                      full, de-duplicated transcript (overwritten each time)
    snapshots/<yyyy-MM-dd_HHmmss>.txt   the raw export received that day
    updates/<yyyy-MM-dd_HHmmss>_new.txt only the messages added by that export
```

## Architecture

```
 WhatsApp  <--UI automation--  Kotlin AccessibilityService (android/)
                                   |  exported .txt/.zip in app-private storage
                                   v
              MethodChannel `chat_archiver/automation`   (Dart -> Kotlin)
              MethodChannel call `onProcessPending`       (Kotlin -> Dart)
              EventChannel  `chat_archiver/automation/events`
                                   |
                                   v
            AutomationBridge (lib/feature/automation)
                                   |
                                   v
            SyncOrchestrator (lib/feature/archive/domain/usecases)
              match group -> read export -> ProcessExportUseCase
              (parse, merge, serialize) -> upload -> save local -> ack
                          |                              |
                          v                              v
              local archive per group         DriveGateway (lib/feature/drive)
              <documents>/archives/<id>/      google_sign_in 7 + googleapis Drive v3
                                              scope: drive.file only
```

The channel contract is `doc/AUTOMATION_CHANNEL.md` (binding for both sides).

Code layout (Clean Architecture + MVVM, GetX):

| Path | Content |
|---|---|
| `lib/feature/archive/domain` | Pure Dart: parser, merger, writer, Drive layout, run policy, `ProcessExportUseCase`, `ArchiveConfigService`, `SyncOrchestrator` |
| `lib/feature/archive/data` | `ArchiveStateRepositoryImpl` (storage), `LocalArchiveStore` (atomic files) |
| `lib/feature/archive/presentation` | `SyncCoordinator` (app-wide state and triggers), `GroupsController`, shared widgets |
| `lib/feature/automation` | `AutomationBridge` interface, typed models (`PendingExport`, `RunReport`, events), `MethodChannelAutomationBridge` |
| `lib/feature/drive` | `DriveAuthService`, `DriveGateway`, Google implementations, ID cache |
| `lib/feature/setup`, `home`, `settings`, `splash` | Screens and controllers |
| `lib/config`, `lib/core` | Flavors, theme, routes, DI, localization (GetX, English), `StorageService` (flutter_secure_storage), errors |

### How it avoids losing or duplicating messages

* A native export is acknowledged (and thereby deleted) **only after** every
  Drive upload succeeded, the local archive was written atomically (temp file +
  rename) and the group state saved. Any failure leaves the export pending and
  the group marked `failed`; other groups continue.
* Upload order: snapshot, update (if there are new messages), `archive.txt`
  (if changed). File names derive from the export time and an existing file of
  the same name is overwritten, `archive.txt` is a full overwrite, so a retry
  creates no duplicates; re-merging a snapshot that was already merged yields
  `noChange`.
* Exports of one group are processed oldest first; if one fails, newer ones
  of the same group wait.
* If the local archive is missing (app data cleared), `archive.txt` is fetched
  from Drive first, so history is never overwritten by a fresh snapshot.
* If an export cannot be aligned with the archive (`gap`), the safe default is
  used: only the snapshot is uploaded, the archive is left unchanged, the
  group shows **Needs your decision** and the user can choose **Accept
  snapshot as new baseline** (the held snapshot is then appended in full).
* One in-flight lock: start, resume, `onProcessPending` and "run finished"
  triggers are coalesced.

## Run and build

Prerequisites: Flutter 3.38 (Dart 3.10), Android SDK, JDK 17, and a Google
Cloud OAuth setup (see `doc/GOOGLE_DRIVE_SETUP.md`).

Flavors (entry point + Gradle flavor):

| Flavor | Entry point | applicationId |
|---|---|---|
| dev | `lib/main_dev.dart` | `com.vervali.chatarchiver.dev` |
| stage | `lib/main_stage.dart` | `com.vervali.chatarchiver.stage` |
| prod | `lib/main_prod.dart` | `com.vervali.chatarchiver` |

```bash
flutter pub get

# once: copy dart_defines.json.example → dart_defines.json and put the
# Google OAuth *Web* client ID in it (see doc/GOOGLE_DRIVE_SETUP.md)

# run on a device
flutter run -t lib/main_dev.dart --flavor dev \
  --dart-define-from-file=dart_defines.json

# debug APK
flutter build apk --debug --flavor dev -t lib/main_dev.dart \
  --dart-define-from-file=dart_defines.json

# release (needs android/key.properties)
flutter build apk --release --flavor prod -t lib/main_prod.dart --dart-define-from-file=dart_defines.json
flutter build appbundle --release --flavor prod -t lib/main_prod.dart --dart-define-from-file=dart_defines.json
```

Without a real `GOOGLE_SERVER_CLIENT_ID` the app builds and runs but Google
sign-in fails with a configuration error (placeholders like
`placeholder.apps.googleusercontent.com` are rejected). `.vscode/launch.json`
loads `dart_defines.json` for every flavor/mode.

Tests and analysis:

```bash
flutter analyze
flutter test
```

## Setup docs

* `doc/GOOGLE_DRIVE_SETUP.md`: GCP project, Drive API, consent screen with the
  `drive.file` scope, Android OAuth clients per applicationId + SHA-1 and the
  web client ID passed with `--dart-define`.
* `doc/AUTOMATION_CHANNEL.md`: contract between the Kotlin automation and
  Dart, plus "Dart notes".

First-run flow in the app: connect Google Drive -> add groups (exact titles)
-> read the disclosure and allow the accessibility service -> pick the morning
hour (default 7:00, "runs the first time you unlock after this time") -> run
the first sync. While a sync runs the phone must stay unlocked for about one
minute.

## Pilot limitations

* **WhatsApp UI selectors are unverified on a real device.** The automation
  targets the English WhatsApp UI and needs tuning per WhatsApp version and
  device. Settings > Diagnostics > "Capture WhatsApp screen in 10 s" produces
  a node-tree dump that can be shared to adjust selectors.
* **Other WhatsApp languages and variants** (WhatsApp Business, secondary
  users, work profiles) are not covered.
* **Play Store policy:** apps using the AccessibilityService API need Google
  Play's accessibility declaration and review (prominent in-app disclosure,
  permitted use case). The disclosure screen exists; acceptance by Google is
  not assured. Sideloaded pilots are not affected.
* **WhatsApp terms of service:** automating the WhatsApp UI may conflict with
  WhatsApp's terms. This must be reviewed before any commercial sale.
* **Google OAuth in testing mode:** only listed test users can sign in and
  Google may expire the authorization after 7 days; publish the consent screen
  to production for a real pilot.
* **Silent re-authorization is not verified on a device.** It relies on a
  no-UI authorization request for the remembered account returning a token;
  if Google asks for consent again the app shows **Reconnect** and pending
  exports wait on the phone.
* The phone must be unlocked and untouched for about a minute per group
  during a run; the app keeps the screen on while it runs, but pressing the
  power button or using the phone aborts the run (it is retried on a later
  unlock, at most 3 automatic attempts per day).
* Android 13+ blocks the accessibility switch of side-loaded apps until the
  user allows "restricted settings" in App info; the setup screen explains
  this and has an "Open App info" button. Phones from Xiaomi, Oppo, Vivo,
  Realme, OnePlus and Samsung may stop the service in the background unless
  battery restrictions are lifted / autostart is allowed (setup and Settings
  offer this).
* Owner and client walkthrough: `doc/USER_FLOW.md`.
* Android exports are limited by WhatsApp to the most recent messages (without
  media); very old history that WhatsApp no longer exports cannot be
  recovered. Edited or deleted messages are handled only within the merger's
  documented tolerance, otherwise the group is flagged `gap`.
* `drive.file` only sees files this app created; a manually created "WhatsApp
  Archive" folder is ignored and a second one is created.
