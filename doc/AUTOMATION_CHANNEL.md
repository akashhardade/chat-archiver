# Automation channel contract (Kotlin ⇄ Dart)

This file is the single source of truth for the platform channel between the
native Android automation (Kotlin, `android/`) and the Flutter app (`lib/`).
Change it only together with both sides.

Package / applicationId: `com.vervali.chatarchiver` (flavors may add a suffix).

## MethodChannel `chat_archiver/automation` (Dart → Kotlin)

| Method | Arguments | Returns |
|---|---|---|
| `isAccessibilityEnabled` | – | `bool` – our `ExportAccessibilityService` is enabled and connected |
| `openAccessibilitySettings` | – | `null` – opens Android Settings › Accessibility (deep-link to our service where the OS allows) |
| `saveConfig` | `{ "enabled": bool, "morningHour": int 0–23, "groups": [ { "id": String, "name": String, "enabled": bool } ] }` | `null` – persisted natively (SharedPreferences) so the unlock trigger works with the Flutter UI closed |
| `getConfig` | – | same map as `saveConfig`, or `null` if never saved |
| `runNow` | `{ "groupIds": [String] }` (optional; empty/absent = all enabled groups) | `{ "started": bool, "reason": String? }` – `reason` is one of `accessibility_disabled`, `already_running`, `no_groups`, `whatsapp_not_installed` |
| `cancelRun` | – | `null` |
| `isRunning` | – | `bool` |
| `listPendingExports` | – | `[ PendingExport ]` (see below), oldest first |
| `ackExport` | `{ "jobId": String }` | `null` – deletes the stored file and its record. Dart calls this ONLY after Drive confirmed every upload for that export |
| `getLastRunReport` | – | `RunReport` or `null` |
| `dumpScreen` | `{ "delaySeconds": int }` | `String` – path of a text file with the active window's node tree (class, id, text, content-desc, clickable, bounds), captured after the delay. Diagnostic for tuning WhatsApp selectors on a client phone |
| `isIgnoringBatteryOptimizations` | – | `bool` – Android does not apply battery optimisation to the app (always `true` below API 23) |
| `requestIgnoreBatteryOptimizations` | – | `String` – opens the system "allow to run in background" dialog (`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`), falling back to the battery-optimisation list, then to App info. Returns what was opened: `dialog`, `list`, `app_settings` or `none` |
| `openAppSettings` | – | `null` – opens Android App info for this app (Android 13+ "Allow restricted settings", battery, OEM autostart) |

### PendingExport
```json
{
  "jobId": "uuid",
  "groupId": "id from config, or null for a manual share outside a run",
  "groupName": "exact group title (from config, or parsed from the share subject/file name for manual shares)",
  "filePath": "absolute path in app-private storage",
  "fileName": "original display name, e.g. WhatsApp Chat with Project Alpha.txt / .zip",
  "mimeType": "text/plain | application/zip | ...",
  "receivedAt": 1767225600000,
  "runId": "uuid or null",
  "trigger": "unlock | manual | share"
}
```

### RunReport
```json
{
  "runId": "uuid",
  "trigger": "unlock | manual",
  "startedAt": 1767225600000,
  "finishedAt": 1767225660000,
  "results": [
    { "groupId": "…", "groupName": "…", "status": "exported | failed | skipped", "error": "code or null", "step": "last step name or null" }
  ]
}
```
Error codes: `whatsapp_not_installed`, `search_not_found`, `group_not_found`, `wrong_chat`, `menu_not_found`, `export_not_found`, `share_target_not_found`, `share_not_received`, `timeout`, `cancelled`, `screen_locked`, `unexpected_screen`.

## EventChannel `chat_archiver/automation/events` (Kotlin → Dart)
Each event is a map with `type`:
- `{ "type": "runStarted", "runId", "trigger", "groupIds" }`
- `{ "type": "groupStarted", "runId", "groupId" }`
- `{ "type": "groupExported", "runId", "groupId", "jobId" }`
- `{ "type": "groupFailed", "runId", "groupId", "error", "step" }`
- `{ "type": "runFinished", "runId", "report": RunReport }`
- `{ "type": "exportReceived", "jobId" }` (also fires for manual shares)

Events are best effort (the UI may be closed). Dart must always reconcile using `listPendingExports` / `getLastRunReport`.

## Processing hand-off
- At the end of a run the service launches `MainActivity` with intent extra `process_pending = true`. MainActivity then invokes Dart method `onProcessPending` (no args) on the same `chat_archiver/automation` channel (Kotlin → Dart call). If the engine is not ready yet it delivers it once Dart registers its handler (Dart calls `isRunning` at start-up; Kotlin flushes the queued `onProcessPending` after the first Dart call).
- Dart also processes pending exports on app start and on resume.

## Unlock trigger (native only)
On `ACTION_USER_PRESENT` (registered dynamically by the accessibility service): run when config `enabled`, at least one enabled group, local hour ≥ `morningHour`, and some enabled group has not exported successfully today (per-group `lastExportDate` kept natively). Only groups not yet exported today are run. At most one automatic attempt per 20 minutes, and at most 3 automatic attempts per local day (so a group that keeps failing does not take over the phone on every unlock).

## Native notes
Clarifications from the Kotlin implementation (no change to the semantics above).

- `isAccessibilityEnabled`: true when the service instance is connected, or (fallback) when our component is listed in `Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES`. `runNow` still returns `accessibility_disabled` if no live instance exists (e.g. right after the OS restarted the process).
- `saveConfig`/`getConfig`: `morningHour` is clamped to 0-23; unknown keys are dropped; groups without `id` or `name` are ignored. Per-group `lastExportDate` is stored natively, keyed by group `id`, is not part of this map, and survives `saveConfig`. It is set when a group's share was received (not when Drive upload finishes).
- `runNow`: explicit `groupIds` run those ids that exist in the saved config (even if the group's `enabled` is false); unknown ids are ignored. Empty/absent runs all enabled groups, regardless of `lastExportDate` and of the global `enabled` flag. Reason precedence: `accessibility_disabled`, `already_running`, `no_groups`, `whatsapp_not_installed`. If the phone is locked when the run starts, it starts and then immediately ends with `screen_locked`.
- RunReport on abort: the group in progress is `failed` with the abort code (`cancelled` / `screen_locked`), and every remaining group is `skipped` with `error` = the same code. `step` is the lower-case native step name: `launch`, `to_chats_list`, `open_search`, `type_query`, `pick_result`, `verify_chat`, `open_overflow`, `tap_more`, `tap_export`, `tap_without_media`, `find_share_target`, `wait_receipt`, `return`.
- Error nuance: `wrong_chat` is reported both when several rows match the group name exactly and when the conversation toolbar title differs from the group name. If the conversation never opens (title cannot be read within the step timeout) the code is `unexpected_screen`.
- Events: `exportReceived` fires once per stored file (a run's share also produces `groupExported` carrying the same `jobId`). `groupFailed.step` uses the step names above. At the end of an aborted run with `screen_locked`, `MainActivity` is NOT launched (the phone is locked); Dart picks pending exports up on next start/resume.
- `onProcessPending`: if Dart has not registered its handler, Kotlin retries up to 5 times at 500 ms intervals (the first flush is 300 ms after Dart's first call). Dart should register `setMethodCallHandler` before its first call to `isRunning`.
- `ackExport` deletes the file only if it lives inside the app's `filesDir/pending` folder, then removes the record. Unknown job ids are a no-op.
- `listPendingExports` drops records whose file vanished. A manual share (`trigger: "share"`) has `groupId: null`; `groupName` is parsed from `EXTRA_SUBJECT` or the file name ("WhatsApp Chat with X" / "WhatsApp Chat - X"), so Dart should match it to a configured group by normalised name, and may get `null` when it cannot be parsed. A `.zip` export keeps `fileName` ending `.zip` and `mimeType` `application/zip`.
- `dumpScreen`: `delaySeconds` is capped at 120; completes with the file path, or a PlatformException (`accessibility_disabled`, `dump_failed`). Files go to `filesDir/diagnostics/screen-<yyyyMMdd-HHmmss>.txt`.
- Flavors: applicationId is `com.vervali.chatarchiver` (+ `.dev` / `.stage`); the share target label is `Save to Chat Archiver` / `... Dev` / `... Staging`. Use the `...Staging` text in docs/tests for the stage flavor.
- Screen: while a run is in progress the runner holds a screen wake lock (released at the end of the run, at most 10 minutes), because accessibility clicks are not user activity and a 30-second screen timeout would otherwise lock the phone mid-run. Pressing the power button still aborts the run with `screen_locked`.
- Menu safety: "More", "Export chat" and "Without media" are only tapped in a window that does not contain the conversation (popup menus and dialogs are separate windows), never on message text. A chat without media that skips the "Include media?" question and goes straight to the share sheet is handled (the run continues with `find_share_target`).
- Manual share (outside a run): after storing the file, `ShareReceiverActivity` launches `MainActivity` with `process_pending = true` so the upload starts immediately (not while a run is in progress).
- Daily cap bookkeeping: native keeps the date and count of automatic attempts (`auto_attempts_date`, `auto_attempts_count`); manual `runNow` runs are not counted and not capped.

## Dart notes
How the Dart side (`lib/feature/automation`, `lib/feature/archive`) uses this contract. Nothing above changes.

* **Bridge**: `MethodChannelAutomationBridge` registers the Dart handler for `onProcessPending` in its constructor (before `runApp`), and the app calls `isRunning` right after start-up (`SyncCoordinator.start`) so native can flush a queued `onProcessPending`. Missing plugin / platform errors surface as `AutomationBridgeException`.
* **Unknown values are tolerated**: unknown event types are ignored, an unknown `trigger` becomes `unknown`, a missing `finishedAt` / `results` is accepted.
* **When Dart processes pending exports**: app start, app resume, `onProcessPending`, and the `runFinished` event. Overlapping triggers are coalesced into one pass.
* **Matching**: an export is matched to a configured group by `groupId`; if that is null or not configured, by exact group title after normalisation (invisible marks and odd spaces removed, whitespace collapsed, trimmed, case-sensitive). Exports that match nothing stay pending (`ackExport` is not called) and are shown to the user as "unmatched".
* **`ackExport(jobId)` is called only after** every Drive upload for the export succeeded, the local archive was written and the group state saved. It is also called (to clear a dangling record) if the export file no longer exists, and when the user explicitly discards an export. A failed `ackExport` is harmless: the next pass re-merges the same snapshot to `noChange`.
* **Ordering**: exports of one group are processed oldest first (`receivedAt`); if one fails, newer ones of that group are left pending.
* **File names on Drive** derive from the export's `receivedAt` (local time), so a retry overwrites the same snapshot/update file instead of creating a duplicate.
* **`saveConfig`** is called at start-up and whenever the groups, the morning hour, the enabled switch or the Drive connection change. The `enabled` flag sent is `automationEnabled AND setup wizard finished AND Google Drive connected`, so WhatsApp never opens by itself during setup or while nothing could be uploaded. Group `id` is stable; renaming a group that already has an archive creates a new id (new archive, new Drive folder).
* **Drive authorization** for background passes is a silent request for the remembered account e-mail (no UI). If it returns nothing, the export stays pending and the UI shows "Reconnect" (`SyncSummary.needsDriveReconnect`).
* **Battery**: `isIgnoringBatteryOptimizations` is read on every reload; Setup (after the accessibility step) and Settings offer `requestIgnoreBatteryOptimizations` and `openAppSettings`.
* **Run reports**: after processing, the last `RunReport` (once per `runId`) is applied to the groups: `failed` results set the group status to `failed`, or to `needsAttention` for `group_not_found`, `search_not_found`, `wrong_chat`, `whatsapp_not_installed`; `lastError` keeps the raw code and the UI maps it to plain language.
* **`dumpScreen`** is called with `delaySeconds: 10` from Settings > Diagnostics; the returned file path is shared with `share_plus` as `text/plain`.
