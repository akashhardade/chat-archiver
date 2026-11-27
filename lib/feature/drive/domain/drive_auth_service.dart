import 'package:dartz/dartz.dart';
import 'package:http/http.dart' as http;
import 'package:chat_archiver/core/error/failure.dart';

/// The Google account connected for Drive uploads.
class DriveAccount {
  final String email;
  final String? displayName;
  const DriveAccount({required this.email, this.displayName});
}

/// Google Drive authorization (only the `drive.file` scope).
abstract class DriveAuthService {
  /// The connected account (remembered across launches), or null.
  DriveAccount? get currentAccount;

  bool get isConnected => currentAccount != null;

  /// Interactive sign-in + `drive.file` consent. Needs the UI.
  Future<Either<Failure, DriveAccount>> connect();

  /// Silently obtains an authorized HTTP client (no prompt). Returns an
  /// [AuthFailure] when the user has to reconnect. The caller must close the
  /// client. With [forceRefresh] a cached access token is discarded first.
  Future<Either<Failure, http.Client>> authorizedClient({
    bool forceRefresh = false,
  });

  /// Revokes access and forgets the account.
  Future<void> disconnect();
}
