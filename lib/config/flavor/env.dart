/// Build-time configuration passed with `--dart-define` or
/// `--dart-define-from-file=dart_defines.json`.
///
/// Example:
/// `flutter run -t lib/main_dev.dart --flavor dev
///   --dart-define-from-file=dart_defines.json`
///
/// See `doc/GOOGLE_DRIVE_SETUP.md`.
class Env {
  Env._();

  /// OAuth *Web application* client ID of the Google Cloud project. Required
  /// by `google_sign_in` 7.x on Android (there is no `google-services.json`
  /// in this app). Empty when not supplied.
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  /// True when [googleServerClientId] looks like a real Web OAuth client ID.
  /// Rejects empty values and common placeholders that otherwise surface as
  /// a misleading "Sign-in was cancelled" from Credential Manager.
  static bool get hasGoogleServerClientId {
    final id = googleServerClientId.trim();
    if (id.isEmpty) return false;
    if (!_looksLikeGoogleClientId(id)) return false;
    if (_isPlaceholder(id)) return false;
    return true;
  }

  /// Human-readable reason when [hasGoogleServerClientId] is false.
  static String get googleServerClientIdConfigError {
    final id = googleServerClientId.trim();
    if (id.isEmpty) {
      return 'GOOGLE_SERVER_CLIENT_ID is missing. Pass a Web OAuth client ID '
          'with --dart-define or --dart-define-from-file=dart_defines.json. '
          'See doc/GOOGLE_DRIVE_SETUP.md.';
    }
    if (_isPlaceholder(id) || !_looksLikeGoogleClientId(id)) {
      return 'GOOGLE_SERVER_CLIENT_ID is not a real Web OAuth client ID '
          '(got "$id"). Replace the placeholder in dart_defines.json or '
          'launch.json. See doc/GOOGLE_DRIVE_SETUP.md.';
    }
    return 'GOOGLE_SERVER_CLIENT_ID is not configured correctly. '
        'See doc/GOOGLE_DRIVE_SETUP.md.';
  }

  static bool _looksLikeGoogleClientId(String id) =>
      id.endsWith('.apps.googleusercontent.com') &&
      !id.startsWith('.') &&
      id.contains('-');

  static bool _isPlaceholder(String id) {
    final lower = id.toLowerCase();
    return lower.contains('placeholder') ||
        lower.contains('your-web-client') ||
        lower.contains('your_web_client') ||
        lower.contains('replace_with') ||
        lower.contains('<') ||
        lower.contains('example') ||
        lower.startsWith('1234-abc.') ||
        lower.startsWith('123456789-abc.');
  }
}
