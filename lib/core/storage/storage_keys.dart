class StorageKeys {
  StorageKeys._();

  static const String localizationsKey = 'localizations_key';
  static const String languageCountKey = 'language_count_key';
  static const String isDarkMode = 'is_dark_mode';

  // Archive state
  static const String archiveGroups = 'archive_groups_v1';
  static const String morningHour = 'archive_morning_hour';
  static const String automationEnabled = 'archive_automation_enabled';
  static const String lastSuccessfulRunDate = 'archive_last_successful_run_date';
  static const String lastAppliedRunId = 'archive_last_applied_run_id';
  static const String setupComplete = 'setup_complete';
  static const String disclosureAccepted = 'automation_disclosure_accepted';

  // Google Drive
  static const String driveAccountEmail = 'drive_account_email';
  static const String driveIdCache = 'drive_id_cache_v1';
}
