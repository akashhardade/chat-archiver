/// User-level settings that live next to the groups (storage-backed).
abstract class ArchiveSettingsRepository {
  static const int defaultMorningHour = 7;

  /// Hour of day (0-23) after which the first unlock triggers the run.
  int get morningHour;
  Future<void> setMorningHour(int hour);

  /// Master switch for the automatic morning run.
  bool get automationEnabled;
  Future<void> setAutomationEnabled(bool enabled);

  /// True once the setup wizard was completed (or skipped to the end).
  bool get setupComplete;
  Future<void> setSetupComplete(bool complete);

  /// True once the user agreed to the accessibility disclosure.
  bool get disclosureAccepted;
  Future<void> setDisclosureAccepted(bool accepted);

  /// Id of the last native run whose per-group errors were applied.
  String? get lastAppliedRunId;
  Future<void> setLastAppliedRunId(String runId);
}
