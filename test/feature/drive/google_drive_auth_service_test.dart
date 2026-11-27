import 'package:chat_archiver/core/error/failure.dart';
import 'package:chat_archiver/core/storage/key_value_store.dart';
import 'package:chat_archiver/core/storage/storage_keys.dart';
import 'package:chat_archiver/feature/drive/data/drive_id_cache.dart';
import 'package:chat_archiver/feature/drive/data/google_drive_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

/// Records what the app asks the Google Sign-In platform for.
class _FakeSignInPlatform extends GoogleSignInPlatform {
  final List<AuthorizationRequestDetails> requests = [];
  final List<String> cleared = [];
  String? token = 'token-1';
  int lightweightCalls = 0;
  int disconnects = 0;

  @override
  Future<void> init(InitParameters params) async {}

  @override
  Future<AuthenticationResults?>? attemptLightweightAuthentication(
    AttemptLightweightAuthenticationParameters params,
  ) {
    lightweightCalls++;
    return null;
  }

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<AuthenticationResults> authenticate(AuthenticateParameters params) =>
      throw UnimplementedError();

  @override
  bool authorizationRequiresUserInteraction() => false;

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
    ClientAuthorizationTokensForScopesParameters params,
  ) async {
    requests.add(params.request);
    final t = token;
    return t == null ? null : ClientAuthorizationTokenData(accessToken: t);
  }

  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
    ServerAuthorizationTokensForScopesParameters params,
  ) async =>
      null;

  @override
  Future<void> clearAuthorizationToken(ClearAuthorizationTokenParams params) async =>
      cleared.add(params.accessToken);

  @override
  Future<void> signOut(SignOutParams params) async {}

  @override
  Future<void> disconnect(DisconnectParams params) async => disconnects++;
}

void main() {
  late _FakeSignInPlatform platform;
  late MemoryKeyValueStore storage;

  setUp(() {
    platform = _FakeSignInPlatform();
    GoogleSignInPlatform.instance = platform;
    storage = MemoryKeyValueStore();
  });

  GoogleDriveAuthService service() => GoogleDriveAuthService(
        storage: storage,
        idCache: InMemoryDriveIdCache(),
      );

  test(
      'cold start (app launched by the automation): silent authorization is '
      'requested for the remembered account, without UI', () async {
    await storage.write(StorageKeys.driveAccountEmail, 'client@example.com');
    final auth = service();
    expect(auth.isConnected, isTrue);

    final result = await auth.authorizedClient();

    expect(result.isRight(), isTrue);
    result.fold((_) {}, (c) => c.close());
    final req = platform.requests.single;
    expect(req.email, 'client@example.com');
    expect(req.promptIfUnauthorized, isFalse);
    expect(req.scopes, [GoogleDriveAuthService.driveFileScope]);
    // Never falls back to a flow that can show an account picker.
    expect(platform.lightweightCalls, 0);
  });

  test('no silent token -> AuthFailure asking to reconnect (no UI)', () async {
    await storage.write(StorageKeys.driveAccountEmail, 'client@example.com');
    platform.token = null;

    final result = await service().authorizedClient();

    expect(result.fold((f) => f, (_) => null), isA<AuthFailure>());
    expect(platform.lightweightCalls, 0);
  });

  test('forceRefresh (after a 401) clears the cached token first', () async {
    await storage.write(StorageKeys.driveAccountEmail, 'client@example.com');
    final auth = service();
    (await auth.authorizedClient()).fold((_) {}, (c) => c.close());
    platform.token = 'token-2';

    (await auth.authorizedClient(forceRefresh: true))
        .fold((_) {}, (c) => c.close());

    expect(platform.cleared, ['token-1']);
    expect(platform.requests, hasLength(2));
  });

  test('not connected -> AuthFailure without touching the platform', () async {
    final result = await service().authorizedClient();
    expect(result.fold((f) => f, (_) => null), isA<AuthFailure>());
    expect(platform.requests, isEmpty);
  });

  test(
      'connect without a real GOOGLE_SERVER_CLIENT_ID fails before authenticate',
      () async {
    // Test process has no --dart-define, so Env rejects the empty/placeholder id.
    final result = await service().connect();
    final failure = result.fold((f) => f, (_) => null);
    expect(failure, isA<AuthFailure>());
    expect(failure!.message, contains('GOOGLE_SERVER_CLIENT_ID'));
  });

  test('disconnect after a restart registers the account so it can be revoked',
      () async {
    await storage.write(StorageKeys.driveAccountEmail, 'client@example.com');
    final auth = service();

    await auth.disconnect();

    expect(platform.requests.single.email, 'client@example.com');
    expect(platform.disconnects, 1);
    expect(auth.isConnected, isFalse);
    expect(storage.read(StorageKeys.driveAccountEmail), isNull);
  });
}
