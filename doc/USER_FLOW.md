# Chat Archiver: setup and user flow

For the business owner who sets Chat Archiver up and hands it to clients.

**What the app does.** A client installs Chat Archiver on their own Android
phone, connects their own Google Drive and types the exact titles of the
WhatsApp groups to keep. Every morning, the first time they unlock the phone
after a chosen hour, the app opens WhatsApp by itself. For each group it uses
WhatsApp's own **Export chat > Without media** and hands the file to itself
("Save to Chat Archiver"). It then adds only the new messages to that group's
archive and uploads it to the client's Google Drive, into
**My Drive / WhatsApp Archive / *group title* /**:

| File | What it is |
|---|---|
| `archive.txt` | The full, de-duplicated history of the group. Replaced on every sync. |
| `snapshots/<date_time>.txt` | The raw export WhatsApp produced that day. |
| `updates/<date_time>_new.txt` | Only the messages that were new that day. Written only when there were new messages. |

Nothing goes to any server of ours. The app can only see Drive files it
created itself (Google's `drive.file` permission).

**How far it has been checked (be honest with clients about this).**

* Checked by automated tests and builds: the merging of messages (no loss, no
  duplicates, retries, crashes), the Drive upload logic against a simulated
  Drive, the app ⇄ Android contract, and the debug and release builds.
* **Not yet checked on any phone.** The part that taps through WhatsApp was
  written from knowledge of WhatsApp's English Android screens, without a
  device. It has to be tried, and probably adjusted, on a real phone before
  you give it to a client (Table D). Google sign-in, the morning trigger and
  the battery prompts have not run on a phone yet either.

---

## Table A: What the owner must add or set up before a client can use it

| # | Item | Exactly what to do | Needed for | Done in code? |
|---|---|---|---|---|
| 1 | Google Cloud project | <https://console.cloud.google.com/> > project picker > **New project** (e.g. `chat-archiver`). Use a Google account the business owns long term. | pilot | no |
| 2 | Google Drive API | In that project: **APIs & Services > Library > "Google Drive API" > Enable**. Without it every upload fails with "Drive API not enabled". | pilot | no |
| 3 | OAuth consent screen | **Google Auth Platform** (or "OAuth consent screen"): User type **External**. App name `Chat Archiver`, support e-mail, developer e-mail. **Data access > Add scopes**: add only `https://www.googleapis.com/auth/drive.file` ("See, edit, create and delete only the specific Google Drive files you use with this app"). Leave **Publishing status: Testing** for the pilot. | pilot | no |
| 4 | Add each client as a test user | While the consent screen is in *Testing*: **Audience > Test users > Add users** and enter the client's Google (Gmail) address. Max 100. A client who is not listed sees "Access blocked" / error 403 `access_denied`. In Testing, Google can expire the permission after 7 days, so the client may have to tap **Reconnect** weekly. | pilot | no |
| 5 | Publish the consent screen | Before selling: **Audience > Publish app** (to "In production"). `drive.file` is a non-sensitive scope, so no security review is needed, but Google may ask for branding verification: a home page, a **privacy policy URL** and a verified domain. Removes the 7-day expiry and the test-user limit. | selling | no |
| 6 | Release signing key | Create once and **back it up** (losing it means clients cannot update): `keytool -genkey -v -keystore android\chat-archiver-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias chatarchiver`. Create `android\key.properties` with 4 lines: `storeFile=chat-archiver-release.jks`, `storePassword=...`, `keyAlias=chatarchiver`, `keyPassword=...` (the path is relative to the `android` folder). **If this file or the keystore is missing, a release build is silently signed with the debug key of the PC that built it.** Never share or commit these two files. | pilot (recommended), selling (required) | partly: the build reads `key.properties` if it exists |
| 7 | SHA-1 of the signing key | Release key: `keytool -list -v -keystore android\chat-archiver-release.jks -alias chatarchiver` and copy the `SHA1:` line. Debug key of your PC (only if you hand out debug builds): `cd android` then `gradlew.bat signingReport` and copy `SHA1` of `devDebug`. If you ever publish on Google Play with Play App Signing, also use the **app signing key SHA-1** from Play Console > App integrity. | pilot | no |
| 8 | Android OAuth client (one per app id + key) | **Clients > Create client > Android**. Package name = the app id of the build you hand out: prod `com.vervali.chatarchiver`, stage `com.vervali.chatarchiver.stage`, dev `com.vervali.chatarchiver.dev`. SHA-1 = from row 7. One client per (package name, SHA-1) pair. No ID needs to be copied: Google recognises the installed app by package name and signature. A wrong pair shows up as "Sign-in was cancelled" right after choosing the account. | pilot | no |
| 9 | Web OAuth client (server client ID) | **Clients > Create client > Web application** (name e.g. `Chat Archiver server client`, no redirect URI). Copy its **Client ID** (`1234...-abc.apps.googleusercontent.com`). It is passed to every build in row 10. Without it, "Connect Google Drive" fails with a configuration error. | pilot | yes: read from `GOOGLE_SERVER_CLIENT_ID` |
| 10 | Build command | From the project folder: `flutter build apk --release --flavor prod -t lib/main_prod.dart --dart-define=GOOGLE_SERVER_CLIENT_ID=<web client id from row 9>`. Output: `build\app\outputs\flutter-apk\app-prod-release.apk`. (For an internal test build: `--flavor dev -t lib/main_dev.dart`, app id `...chatarchiver.dev`, it installs next to prod and its share entry is "Save to Chat Archiver Dev".) Increase `version:` in `pubspec.yaml` (e.g. `1.0.1+2`) for every new APK, or clients cannot install the update. | pilot | yes |
| 11 | App name | Already "Chat Archiver" (prod), "Chat Archiver Dev", "Chat Archiver Staging": `resValue("string", "app_name", ...)` in `android\app\build.gradle.kts`. If you rename, change `share_label` there too ("Save to ..."); the automation looks for exactly that text in the share menu, and both come from the same file, so they stay consistent. | selling | yes |
| 12 | App icon | The current icon is the **Flutter logo placeholder** (`assets\icons\icon.png`). Replace it with your 1024x1024 PNG, then run `dart run flutter_launcher_icons` and rebuild. | selling | no |
| 13 | APK distribution | Upload the APK somewhere the client can download it on the phone (e.g. a Google Drive link set to "Anyone with the link", or your website). Send the link with Table B. The client must allow "Install unknown apps" for the browser/Files app, and Google Play Protect may warn about an unknown developer ("Install anyway"). | pilot | no |
| 14 | Support channel for diagnostics | Decide where clients send problem reports. The app can capture what WhatsApp's screen looks like (Settings > Diagnostics > "Capture WhatsApp screen in 10 s" > "Share capture file"). The file contains the text visible on that WhatsApp screen (chat names, message previews), so ask for it only when needed and treat it as confidential. | pilot | yes (capture + share) |
| 15 | First device test | Run Table D on at least one real phone before any client gets the app, and adjust the WhatsApp screen rules if needed. | pilot | no |
| 16 | WhatsApp terms check | WhatsApp's Terms of Service restrict automated access to WhatsApp. Exporting your own chats is a WhatsApp feature, but having an app press the buttons may still breach the terms and could put the client's WhatsApp account at risk. Get legal advice before selling, and tell pilot clients. | selling | no |
| 17 | Google Play policy check | Not needed for APK distribution. If you ever publish on Google Play: the AccessibilityService needs the Play **Accessibility API declaration**, and automating another app is generally not an accepted use, so expect rejection. The app also asks for `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, which Play restricts; for Play, remove that permission from `android\app\src\main\AndroidManifest.xml` (the app then opens the battery list instead). A privacy policy is required either way. | selling (Play only) | partly: prominent disclosure screen exists |
| 18 | CI pipeline (optional) | `.gitlab-ci.yml` comes from a template: it builds with Firebase App Distribution and an iOS job (iOS is not supported). If you use it, set the CI variable `GOOGLE_SERVER_CLIENT_ID` (now passed to the Android builds) and a release keystore; otherwise ignore it and build locally (row 10). | optional | partly |
| 19 | Phone requirements to tell clients | Android 7.0 or newer; WhatsApp (not WhatsApp Business) installed and signed in; **WhatsApp shown in English** (it follows the phone language: Settings > System > Languages); a Google account with free Drive space. | pilot | n/a |

---

## Table B: Client's one-time setup on their phone

Steps are in the order the app asks for them. The app's own setup screen
shows "Step 1 of 5" to "Step 5 of 5".

| Step | What the client does | What they see / what the app does | Approx time | Verified on device? |
|---|---|---|---|---|
| 1. Check the phone | Make sure WhatsApp is installed and signed in, and the phone language is English (WhatsApp uses the same language). Know which Google account to use. | Nothing yet. | 2 min | no |
| 2. Download and install | Open the link you sent, download the APK, tap it. If Android says installing is blocked: tap **Settings**, switch on **Allow from this source**, go back, tap **Install**. If Play Protect warns: **More details > Install anyway**. Tap **Open**. | Short splash, then "Set up Chat Archiver", Step 1 of 5. | 3 min | no |
| 3. Connect Google Drive (Step 1) | Tap **Connect Google Drive**, choose the Google account, then on Google's permission page tap **Continue / Allow**. (While the app is in Testing, Google first shows "Google hasn't verified this app": tap **Continue**.) | Google's account sheet, then the permission "See, edit, create and delete only the specific Google Drive files you use with this app". Back in the app: "Connected" and the e-mail. **Continue** becomes active. | 1 min | no |
| 4. Add groups (Step 2) | Tap **Add group**, type the group title **exactly** as WhatsApp shows it at the top of the chat (same capitals, spaces, emoji; copying it is safest), tap **Save**. Repeat for each group. Tap **Continue**. | The list of groups, each with an on/off switch. The app refuses duplicates. | 2 min | no |
| 5. Switch on the automation (Step 3) | Read the explanation, tap **I agree, open Settings**. In Android Settings > Accessibility open **Installed apps** (or "Downloaded apps"), tap **Chat Archiver**, switch it on, confirm with **Allow**. Go back to Chat Archiver. | The app's disclosure of exactly what the service does; Android's Accessibility settings; Android's warning that the app can see and control the screen. Back in the app: "Accessibility service is on". | 2 min | no |
| 5a. Only if Android says "Restricted setting" (Android 13+) | Go back to Chat Archiver, tap **Open App info**, tap the **three dots** (top right) > **Allow restricted settings**, confirm with PIN/fingerprint, go back, tap **Open Accessibility settings** and repeat step 5. | The switch is greyed out or a "Restricted setting" pop-up appears until this is done. The app shows these instructions under the button. | 2 min | no |
| 6. Let it run in the background (still Step 3) | In the card "Let Chat Archiver run in the background" tap **Allow background use**, then **Allow** in Android's pop-up. On Xiaomi/Redmi/POCO, Oppo, Realme, Vivo, OnePlus: tap **Open App info** and switch on **Autostart**, set **Battery** to "No restrictions". On Samsung: App info > Battery > **Unrestricted**, and check Chat Archiver is not under "Sleeping apps". Tap **Continue**. | Card turns green: "Background use is allowed". Without this, some phones stop the service overnight and the morning sync does not happen. | 2 min | no |
| 7. Pick the morning time (Step 4) | Choose the hour in **Start after** (default 7:00 AM). Tap **Continue**. | Text: "Runs the first time you unlock your phone after this time" and the note to keep the phone unlocked and untouched while it runs. | 30 s | no |
| 8. First sync (Step 5) | Tap **Start first sync**. Then **do not touch the phone** and keep it unlocked until Chat Archiver comes back by itself (about 1 minute per group; the screen stays on by itself). | WhatsApp opens by itself, searches each group, opens it, opens the menu > More > Export chat > Without media, and picks "Save to Chat Archiver" in the share menu. Then the home screen appears briefly and Chat Archiver reopens, shows "Uploading to Google Drive..." and a tick or a cross per group, then "First sync finished". | 1-2 min per group | no |
| 9. Finish | Tap **Finish setup**. Automatic morning syncs are switched on only now. | Home screen: the last sync, each group with "Up to date" and the number of messages archived. | 10 s | no |
| 10. Check Drive (optional, recommended) | Open Google Drive > **WhatsApp Archive** > a group folder. | `archive.txt`, a `snapshots` folder and an `updates` folder. | 1 min | no |

---

## Table C: Daily use

### What happens automatically

| When | What the app does | What the client sees | What the client must do |
|---|---|---|---|
| First unlock after the morning hour | About 1.5 s after unlocking, if some group has not been exported today, the app opens WhatsApp and exports only the groups not yet done today. | WhatsApp opening and moving by itself for about 1 minute per group, then the home screen, then Chat Archiver opening and uploading. | Keep the phone unlocked and do not touch it until Chat Archiver is back on screen. |
| Later unlocks the same day | Nothing if every group was exported today. If one failed, it tries again on an unlock at least 20 minutes later, at most 3 automatic attempts per day. | Usually nothing. | Nothing. |
| Upload after each export | Adds only new messages to `archive.txt`, uploads the day's snapshot and (if there were new messages) an update file. The export is deleted from the phone only after Drive confirmed everything. | "Uploading to Google Drive...", then each group "Up to date" with "Last upload: just now". | Nothing. |
| Phone offline or Drive unreachable at that moment | The export stays on the phone; it is uploaded the next time the app is opened or brought to the front, or after the next sync. | Banner "Some exports are waiting". | Open the app when back online, or tap **Retry upload**. |
| Any time | The client can tap **Sync now** on the home screen to run all enabled groups immediately. | Same as the morning run. | Keep the phone unlocked and untouched. |
| Manual share | In WhatsApp: open a group > ⋮ > More > Export chat > Without media > **Save to Chat Archiver**. | Chat Archiver opens and uploads it (if the title matches a group in the list). | Nothing else. |

### When something needs the client (each message the app shows, and the action)

| What the app shows | What it means | What the client does |
|---|---|---|
| Banner "The accessibility service is off, so automatic syncs cannot run." | Android switched the service off (update, phone cleaner, OEM battery manager). | Tap **Fix** > **Turn on** and repeat Table B step 5 (5a on Android 13+). Then check step 6. |
| "Turn on the Chat Archiver accessibility service first..." after tapping Sync now, while the switch looks on | The service is listed as on but is not running. | In Android Settings > Accessibility > Chat Archiver switch it off and on again. |
| Banner "Google Drive is not connected, so nothing can be uploaded." | Drive was disconnected. Automatic syncs are paused. | Tap **Fix** > **Connect Google Drive**. |
| Banner "Google Drive needs you to sign in again..." with **Reconnect** | Google withdrew the permission (7-day Testing limit, password change, access removed). Exports wait on the phone. | Tap **Reconnect**, choose the same account, **Allow**. Waiting exports upload right away. |
| Group "Failed": "Your Google Drive storage is full." | Drive is full. | Free up Drive space or buy storage, then **Retry upload**. |
| Group "Failed": "No connection to Google Drive..." / "temporarily unavailable" / "rate limiting" | Network or Google problem. | Nothing; retried later. Or **Retry upload** when online. |
| Group "Needs attention": "No chat with exactly this title was found..." | The title in the app does not match WhatsApp (or the group was renamed). | Settings > Groups > edit the title so it matches exactly, then **Sync now**. |
| Group "Needs attention": "WhatsApp opened a different chat, or two chats have this exact title..." | Safety stop: the app saw a different title, or several chats with the same title. Nothing was exported. | Give the group a unique title in WhatsApp (and the same in the app), then **Sync now**. |
| Group "Needs attention": "Could not use the WhatsApp search box..." | WhatsApp's layout differs from what the app expects. | **Sync now** once. If it repeats: Settings > Diagnostics, capture the WhatsApp screen and send it to support. |
| Group "Failed": "Could not find the chat menu..." / "Could not find "Export chat"..." / "Could not find "Save to Chat Archiver" in the share menu" | Same as above (layout), or exporting is turned off for that group. | **Sync now** once; if it repeats, send a Diagnostics capture to support. |
| Group "Failed": "WhatsApp showed a screen the automation did not expect..." | A WhatsApp pop-up (update notice, backup prompt, new feature) was in the way. | Open WhatsApp, close the pop-up, then **Sync now**. |
| Group "Failed": "The phone was locked during the sync..." | The power button was pressed or the phone locked. | **Sync now** and leave the phone alone until it finishes. |
| Group "Failed": "WhatsApp did not deliver the export in time..." / "took too long" | Slow phone or very large chat. | Nothing; retried on a later unlock, or **Sync now**. |
| Group "Failed": "The sync was stopped before it finished." | The run was cancelled (for example the service was switched off). | **Sync now**. |
| "WhatsApp is not installed on this phone..." | WhatsApp (not Business) is missing. | Install WhatsApp and sign in. |
| Group "Needs your decision" with **Accept snapshot as new baseline** | Today's export did not line up with the saved history (for example many old messages were deleted or edited, or the phone's date/time format changed). The export was saved to `snapshots`, `archive.txt` was not changed. | If the history in Drive looks right, tap **Accept snapshot as new baseline**: the whole export is appended (some messages may then appear twice). Otherwise contact support. |
| Banner "Some exports are waiting": "No group called "X" is set up..." | A shared export's title matches no group in the list. | Add a group with exactly that title (it is then processed), or tap **Discard**. |
| Banner "Some exports are waiting": "This shared file does not say which WhatsApp group it is from..." | Something other than a chat export was shared to the app. | Tap **Discard**. |

---

## Table D: First device test checklist for the owner

Use a test phone with your own WhatsApp and a test group (create a small
group with one other person). Install the dev build so it does not clash
with clients' prod builds. Connect the phone to the PC and watch the
automation's log with `adb logcat -s ChatArchiver` (from
`C:\src\android-sdk\platform-tools`). If a step fails, open the WhatsApp
screen where it stopped, use Settings > Diagnostics > "Capture WhatsApp
screen in 10 s", share the file to yourself, and adjust
`android\app\src\main\kotlin\com\vervali\chatarchiver\WhatsAppSelectors.kt`.

| # | Test | Pass criterion |
|---|---|---|
| 1 | Install the APK (Table B step 2) | App installs and opens to "Step 1 of 5". |
| 2 | Connect Google Drive | Account sheet and Google permission page appear; app shows "Connected" + e-mail. No "cancelled" error (that means the SHA-1 / package name in Table A row 8 is wrong). |
| 3 | Add the test group with its exact title, plus one group with a misspelled title | Both appear in the list; adding the same title twice is refused. |
| 4 | Enable the accessibility service (on Android 13+ via "Allow restricted settings" if prompted) | Returning to the app shows "Accessibility service is on" without restarting the app. |
| 5 | Battery card: **Allow background use** | Android's pop-up appears; after allowing, the card says "Background use is allowed". **Open App info** opens the app's App info page. |
| 6 | First sync | Log shows each step (`-> step OPEN_SEARCH`, `TYPE_QUERY`, `PICK_RESULT`, `safety gate passed`, `TAP_MORE`, `TAP_EXPORT`, `TAP_WITHOUT_MEDIA`, `FIND_SHARE_TARGET`, `group exported`). The real group is exported; the misspelled one ends "Needs attention" (group not found). The screen does not turn off during the run. App reopens by itself and uploads. |
| 7 | Nothing wrong is tapped | During the whole run: no message sent, no call started, no other chat opened or exported, no voice note. Repeat once with WhatsApp left open inside a different chat before starting. |
| 8 | Check Drive | `My Drive/WhatsApp Archive/<group>/archive.txt` contains the chat; `snapshots/` has one file; `updates/` has one file. Text with emoji and Hindi/other scripts is readable. |
| 9 | Sync again with no new messages | A second snapshot appears; **no** new update file; `archive.txt` unchanged; group "Up to date". |
| 10 | Send 2 messages (one multi-line) in the group, sync again | A new update file with exactly those 2 messages; `archive.txt` ends with them; nothing duplicated. |
| 11 | Morning trigger | Set the morning hour to the current hour (Settings). Lock and unlock the phone: a run starts about 1.5 s after unlocking. Unlock again within 20 minutes: no run. After a successful run, unlocking again the same day: no run. |
| 12 | Daily cap | With the misspelled group enabled alone, unlock three times at least 20 minutes apart (runs fail), then a fourth time: no run that day. |
| 13 | Screen lock during a run | Start **Sync now**, press the power button mid-run: the group shows "The phone was locked during the sync", remaining groups are skipped, nothing breaks. |
| 14 | App closed / phone restarted | Swipe Chat Archiver away from Recent apps; next morning-style unlock (as in 11) still starts the run and the app opens and uploads by itself. Repeat after rebooting the phone (the first unlock after a reboot may be missed; the next one must work). Uploads must happen **without** any Google sign-in screen (checks silent Drive access). |
| 15 | Manual share | In WhatsApp: group > ⋮ > More > Export chat > Without media > "Save to Chat Archiver Dev". Chat Archiver opens and uploads it to the matching group. Share a photo to the app: it shows up as an unknown export that can be discarded. |
| 16 | Offline | Turn on airplane mode after the export step (or run with Wi-Fi/data off after WhatsApp is done): "Some exports are waiting". Turn data on, tap **Retry upload**: uploaded, banner gone, no duplicate files in Drive. |
| 17 | Reconnect | In your Google account (myaccount.google.com > Security > Third-party connections) remove Chat Archiver's access, then **Sync now**: home shows "Google Drive needs you to sign in again" with **Reconnect**; reconnecting uploads the waiting export. |
| 18 | Disconnect | Settings > Google Drive > **Disconnect**: banner "Google Drive is not connected"; unlocking after the morning hour does **not** open WhatsApp; Drive files remain. |
| 19 | Two Google accounts on the phone | Connect with the second account; after a phone restart, morning uploads still go to that account without prompts. |
| 20 | Diagnostics | Settings > Diagnostics > "Capture WhatsApp screen in 10 s", switch to WhatsApp; after 10 s "Capture saved"; **Share capture file** opens the share menu. |
| 21 | Other phone makes | Repeat 6, 11 and 14 on at least one Samsung and one Xiaomi/Oppo/Vivo phone, and on Android 13 or newer. |

---

## Notes for the owner

* **Release builds without a keystore** are signed with the building PC's
  debug key. Google sign-in then only works if that SHA-1 is registered, and
  clients cannot update to a build signed with a different key without
  uninstalling (which deletes the app's local copy; Drive keeps everything and
  the app restores `archive.txt` from Drive on the next sync).
* **Renaming a group** that already has an archive starts a new archive and a
  new Drive folder; the old one is kept.
* **Removing a group** or **disconnecting Drive** never deletes Drive files.
* WhatsApp only exports the most recent part of very long chats (without
  media). History older than what WhatsApp exports on the first sync cannot
  be recovered by the app.
