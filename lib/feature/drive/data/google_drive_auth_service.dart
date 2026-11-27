import 'package:dartz/dartz.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart'
    show
        AuthorizationRequestDetails,
        ClientAuthorizationTokensForScopesParameters,
        GoogleSignInPlatform;
import 'package:http/http.dart' as http;
import 'package:chat_archiver/config/flavor/env.dart';
import 'package:chat_archiver/core/error/failure.dart';
import 'package:chat_archiver/core/storage/storage_keys.dart';
import 'package:chat_archiver/core/storage/key_value_store.dart';
import 'package:chat_archiver/feature/drive/data/drive_id_cache.dart';
import 'package:chat_archiver/feature/drive/domain/drive_auth_service.dart';

/// `google_sign_in` 7.x + the `drive.file` scope (the narrowest scope that
/// lets the app create and edit only the files it created itself).
///
/// Flow:
/// * [connect] (needs the UI, once): `GoogleSignIn.instance.authenticate()`
///   then `authorizationClient.authorizationForScopes` and, if consent is
///   still missing, `authorizeScopes`.
/// * [authorizedClient] (no UI, used by the automatic daily sync): a silent
///   authorization request (`promptIfUnauthorized: false`) for the REMEMBERED
///   account e-mail. This works in a fresh process started by the automation,
///   where nobody called `authenticate()`: on Android the plugin then calls
///   `AuthorizationClient.authorize` with `setAccount(<email>)`, which returns
///   a token without UI while the `drive.file` grant is valid. (The public
///   `GoogleSignIn.instance.authorizationClient` would send no account, which
///   makes Android ask which account to use, i.e. fail silently, on phones
///   with more than one Google account.) If no token can be obtained without
///   UI, an [AuthFailure] asks the user to reconnect. No account picker or
///   bottom sheet is ever shown from here.
class GoogleDriveAuthService implements DriveAuthService {
  static const String driveFileScope =
      'https://www.googleapis.com/auth/drive.file';
  static const List<String> scopes = [driveFileScope];

  final KeyValueStore _storage;
  final DriveIdCache _idCache;

  Future<void>? _init;
  String? _lastToken;
  DriveAccount? _current;

  GoogleDriveAuthService({
    required KeyValueStore storage,
    required DriveIdCache idCache,
  })  : _storage = storage,
        _idCache = idCache {
    final email = _storage.read(StorageKeys.driveAccountEmail);
    if (email != null && email.isNotEmpty) {
      _current = DriveAccount(email: email);
    }
  }

  @override
  DriveAccount? get currentAccount => _current;

  @override
  bool get isConnected => _current != null;

  Future<void> _ensureInitialized() {
    return _init ??= GoogleSignIn.instance
        .initialize(
          serverClientId:
              Env.hasGoogleServerClientId ? Env.googleServerClientId : null,
        )
        .catchError((Object e) {
      _init = null; // allow a retry
      throw e;
    });
  }

  @override
  Future<Either<Failure, DriveAccount>> connect() async {
    if (!Env.hasGoogleServerClientId) {
      return Left(AuthFailure(Env.googleServerClientIdConfigError));
    }
    try {
      await _ensureInitialized();
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: scopes,
      );
      final client = account.authorizationClient;
      final authz = await client.authorizationForScopes(scopes) ??
          await client.authorizeScopes(scopes);
      _lastToken = authz.accessToken;
      final previous = _current?.email;
      _current = DriveAccount(
        email: account.email,
        displayName: account.displayName,
      );
      if (previous != null && previous != account.email) {
        // Cached IDs belong to the previous account.
        await _idCache.clear();
      }
      await _storage.write(StorageKeys.driveAccountEmail, account.email);
      return Right(_current!);
    } on GoogleSignInException catch (e) {
      return Left(_mapSignInException(e));
    } catch (e) {
      return Left(UnknownFailure('Google sign-in failed: $e'));
    }
  }

  /// Access token for [email] if it can be obtained WITHOUT any UI, else null.
  static Future<String?> _silentToken(String email) async {
    final tokens = await GoogleSignInPlatform.instance
        .clientAuthorizationTokensForScopes(
      ClientAuthorizationTokensForScopesParameters(
        request: AuthorizationRequestDetails(
          scopes: scopes,
          userId: null,
          email: email,
          promptIfUnauthorized: false,
        ),
      ),
    );
    return tokens?.accessToken;
  }

  @override
  Future<Either<Failure, http.Client>> authorizedClient({
    bool forceRefresh = false,
  }) async {
    final current = _current;
    if (current == null) {
      return const Left(
        AuthFailure('Google Drive is not connected. Open Chat Archiver and connect it.'),
      );
    }
    try {
      await _ensureInitialized();
      if (forceRefresh && _lastToken != null) {
        // A 401 with a cached token: drop it so the next request returns a
        // fresh one.
        try {
          await GoogleSignIn.instance.authorizationClient
              .clearAuthorizationToken(accessToken: _lastToken!);
        } catch (_) {
          // Best effort: the token may already be gone.
        }
        _lastToken = null;
      }

      final token = await _silentToken(current.email);
      if (token == null) {
        return const Left(
          AuthFailure(
            'Google Drive access has expired. Open Chat Archiver and reconnect Drive.',
          ),
        );
      }
      _lastToken = token;
      return Right(
        GoogleSignInClientAuthorization(accessToken: token)
            .authClient(scopes: scopes),
      );
    } on GoogleSignInException catch (e) {
      return Left(_mapSignInException(e));
    } catch (e) {
      if (kDebugMode) debugPrint('authorizedClient failed: $e');
      return Left(UnknownFailure('Could not authorize Google Drive: $e'));
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _ensureInitialized();
      final email = _current?.email;
      if (email != null) {
        // The Android plugin can only revoke accounts it has authorized in
        // this process; a silent authorization registers the remembered one
        // (e.g. after the app was restarted since connecting).
        try {
          await _silentToken(email);
        } catch (_) {}
      }
      await GoogleSignIn.instance.disconnect();
    } catch (_) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
    _lastToken = null;
    _current = null;
    await _storage.remove(StorageKeys.driveAccountEmail);
    await _idCache.clear();
  }

  Failure _mapSignInException(GoogleSignInException e) {
    switch (e.code) {
      case GoogleSignInExceptionCode.canceled:
      case GoogleSignInExceptionCode.interrupted:
        // Credential Manager often reports SHA-1 / package / serverClientId
        // misconfiguration as "canceled", indistinguishable from a real user
        // dismiss. Point at the setup doc either way.
        return const AuthFailure(
          'Sign-in was cancelled. If you did not cancel, the Android OAuth '
          'client is likely missing this app’s package name + SHA-1, or '
          'GOOGLE_SERVER_CLIENT_ID is wrong. See doc/GOOGLE_DRIVE_SETUP.md.',
        );
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return AuthFailure(
          'Google sign-in is not configured correctly '
          '(${e.description ?? e.code.name}). See doc/GOOGLE_DRIVE_SETUP.md.',
        );
      case GoogleSignInExceptionCode.uiUnavailable:
        return const AuthFailure(
          'Google sign-in needs the app to be open on screen.',
        );
      case GoogleSignInExceptionCode.userMismatch:
        return const AuthFailure('A different Google account is signed in.');
      case GoogleSignInExceptionCode.unknownError:
        return AuthFailure(
          'Google sign-in failed${e.description == null ? '' : ': ${e.description}'}',
        );
    }
  }
}
