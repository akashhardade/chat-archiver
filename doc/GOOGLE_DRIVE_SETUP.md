# Google Drive setup

Chat Archiver uploads to the **user's own Google Drive** with the narrowest
Drive scope, `https://www.googleapis.com/auth/drive.file` (the app can only see
and edit files it created itself). There is no backend; Google sign-in runs
on the phone.

The app uses `google_sign_in` 7.x on Android (Credential Manager +
`AuthorizationClient`). It needs:

1. A Google Cloud project with the **Google Drive API** enabled.
2. The **OAuth consent screen** configured.
3. One **Android** OAuth client **per applicationId + signing key** (this is
   how Google recognises the installed app).
4. One **Web application** OAuth client. Its client ID is the
   `serverClientId` that `google_sign_in` 7.x requires on Android when there
   is no `google-services.json` (this app deliberately does not use Firebase).
   You pass this ID to the build with `--dart-define`.

## 1. Project and API

1. Open <https://console.cloud.google.com/> and create a project (for example
   `chat-archiver`).
2. **APIs & Services -> Library -> Google Drive API -> Enable.**

## 2. OAuth consent screen

**APIs & Services -> OAuth consent screen** (in newer consoles:
*Google Auth Platform -> Branding / Audience / Data Access*).

* User type: **External** (or Internal if every client uses your Google
  Workspace).
* App name `Chat Archiver`, support e-mail, developer contact e-mail.
* **Scopes / Data access -> Add or remove scopes:** add only
  `https://www.googleapis.com/auth/drive.file` (listed as "See, edit, create,
  and delete only the specific Google Drive files you use with this app").
  `drive.file` is a *non-sensitive* scope, so no Google verification is needed
  for it; basic branding verification may still be requested before
  publishing.
* **Publishing status: Testing.** While the app is in *Testing*:
  * only accounts listed under **Test users** can sign in (add every client's
    Google account, up to 100);
  * Google may expire authorizations after **7 days** for external apps in testing. The
    daily silent re-authorization then fails and the app asks the user to
    reconnect Drive. **For a real pilot, move the app to "In production"**
    (allowed without verification when only non-sensitive scopes are used).

## 3. Android OAuth clients (one per applicationId + SHA-1)

This step is required on a real phone. Without a matching Android OAuth
client, Credential Manager closes after the account picker and the app shows
“Sign-in was cancelled.”

Create the clients in the **same** Google Cloud project as the Web client
(currently `cursor-otp`, number `133279653968`).

Application IDs (from the Gradle flavors):

| Flavor | applicationId |
|---|---|
| dev | `com.vervali.chatarchiver.dev` |
| stage | `com.vervali.chatarchiver.stage` |
| prod | `com.vervali.chatarchiver` |

For each flavor you use, get the SHA-1 of the key that signs that build:

```bash
cd android
./gradlew signingReport        # Windows: gradlew.bat signingReport
```

Look at the variant (`devDebug`, `stageRelease`, `prodRelease`, ...) and copy
its `SHA1`. Debug builds use the debug keystore
(`~/.android/debug.keystore`, SHA-1 differs per developer machine); release
builds use the keystore from `android/key.properties`. If the app is
distributed through Google Play with *Play App Signing*, also register the
**app signing key SHA-1** shown in the Play Console (App integrity), because
Google re-signs the app.

Then **APIs & Services -> Credentials -> Create credentials -> OAuth client ID
-> Application type: Android**:

* Package name: the applicationId of the flavor.
* SHA-1 certificate fingerprint: the value from `signingReport`.

Create one client per (applicationId, SHA-1) pair. Android clients have no
secret and their IDs are not used in the code: Google matches them by package
name and signature at run time.

## 4. Web client ID (`serverClientId`)

**Credentials -> Create credentials -> OAuth client ID -> Application type:
Web application** (name it e.g. `Chat Archiver server client`; no redirect URI
is needed). Copy its **Client ID**
(`123456789-abc...apps.googleusercontent.com`). The same web client can be
used for all flavors.

Pass it at build/run time. Preferred: copy `dart_defines.json.example` to
`dart_defines.json` (gitignored), put the Web client ID in it, then:

```bash
flutter run -t lib/main_dev.dart --flavor dev \
  --dart-define-from-file=dart_defines.json
```

Or pass it inline:

```bash
flutter run -t lib/main_dev.dart --flavor dev \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=123456789-abc.apps.googleusercontent.com
```

The value is read in `lib/config/flavor/env.dart`
(`String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID')`) and given to
`GoogleSignIn.instance.initialize(serverClientId: ...)`. Placeholder values
(e.g. `placeholder.apps.googleusercontent.com`) are rejected up front — do
not ship them; Credential Manager otherwise fails with a misleading
"Sign-in was cancelled". For release builds use the same
`--dart-define-from-file` (or `--dart-define`) on `flutter build apk` /
`appbundle`.

## 5. What the user sees

* First time: Connect Google Drive -> account chooser (Credential Manager) ->
  consent for "See, edit, create, and delete only the specific Google Drive
  files you use with this app".
* Afterwards uploads are silent: the app asks Google for a `drive.file`
  token for the remembered account e-mail with prompting disabled
  (`AuthorizationClient.authorize` with that account), which returns an access
  token while the consent is still valid. This is what runs when the
  automation launches the app in the morning. If Google wants the user again
  (consent revoked, Testing-mode expiry, password change), nothing is shown
  automatically: the export stays on the phone and the app shows
  **Reconnect** on the home screen and in Settings > Google Drive.
* Files are created under **My Drive / WhatsApp Archive / <group title> /**
  (`archive.txt`, `snapshots/`, `updates/`). Because of `drive.file`, a folder
  or file the user creates by hand with the same name is **not visible** to the
  app; it always creates and finds its own.

## 6. Troubleshooting

| Symptom | Likely cause |
|---|---|
| Clear config error about `GOOGLE_SERVER_CLIENT_ID` (before the account picker) | `--dart-define` / `dart_defines.json` missing, empty, or still a placeholder. Use a real *Web* client ID. |
| Account chooser closes immediately / `canceled` right after selecting an account | Wrong package name or SHA-1 in the Android OAuth client, or a bad `serverClientId` (Credential Manager reports these as "canceled"). Check the flavor's applicationId and the SHA-1 of the key that really signed the APK (`cd android && ./gradlew signingReport`). |
| "Access blocked: app has not completed verification" / error 403 `access_denied` | Account is not in **Test users** while the consent screen is in *Testing*. |
| Drive error 403 `accessNotConfigured` | Drive API not enabled in the project. |
| Asked to reconnect every week | Consent screen still in *Testing* (7-day expiry). Publish to production. |
| Folder "WhatsApp Archive" appears twice | The app was reinstalled under a different OAuth project / package; `drive.file` only sees files created by the same app identity. |
