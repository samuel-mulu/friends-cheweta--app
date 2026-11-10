import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/app/router.dart';
import 'package:friends_game_app/core/errors/app_failure.dart';
import 'package:friends_game_app/core/storage/preferences_storage.dart';
import 'package:friends_game_app/core/storage/secure_storage.dart';
import 'package:friends_game_app/features/auth/data/auth_repository.dart';
import 'package:friends_game_app/features/auth/domain/auth_state.dart';
import 'package:friends_game_app/features/auth/domain/user.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/auth/presentation/screens/splash_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keystore in memory; `broken` makes every call fail like an undecryptable store.
class _Keystore extends Fake implements FlutterSecureStorage {
  _Keystore([Map<String, String>? values]) : values = {...?values};
  final Map<String, String> values;
  bool broken = false;
  int wipes = 0;

  @override
  Future<String?> read({required String key, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) async {
    if (broken) throw PlatformException(code: 'BadPaddingException');
    return values[key];
  }

  @override
  Future<void> write({required String key, required String? value, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) async {
    if (value != null) values[key] = value;
  }

  @override
  Future<void> delete({required String key, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) async =>
      values.remove(key);

  @override
  Future<void> deleteAll({IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) async {
    wipes++;
    values.clear();
    broken = false;
  }
}

class _Repo extends Fake implements AuthRepository {
  _Repo(this.onMe);
  Future<User> Function() onMe;
  int calls = 0;
  @override
  Future<User> me() {
    calls++;
    return onMe();
  }
}

const _me = User(id: 'u1', fullName: 'Abebe Kebede', phoneNumber: '0922000001', role: 'PLAYER', status: 'ACTIVE');

Future<({ProviderContainer container, _Keystore keystore, SecureStorage storage})> _start({
  Map<String, String> tokens = const {},
  bool cachedUser = false,
  bool broken = false,
  required _Repo repo,
}) async {
  SharedPreferences.setMockInitialValues(cachedUser ? {'session_user': '{"id":"u1","fullName":"Abebe Kebede","phoneNumber":"0922000001","role":"PLAYER","status":"ACTIVE"}'} : {});
  final preferences = await PreferencesStorage.create();
  final keystore = _Keystore(tokens)..broken = broken;
  final storage = SecureStorage(keystore, preferences);
  final container = ProviderContainer(overrides: [
    preferencesStorageProvider.overrideWithValue(preferences),
    secureStorageProvider.overrideWithValue(storage),
    authRepositoryProvider.overrideWithValue(repo),
  ]);
  addTearDown(container.dispose);
  container.read(authControllerProvider); // starts the restore
  return (container: container, keystore: keystore, storage: storage);
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 20));

const _session = {'access_token': 'a', 'refresh_token': 'r'};

void main() {
  test('an unreadable keystore no longer freezes start-up: it is wiped and the user signs in again', () async {
    final s = await _start(tokens: _session, broken: true, repo: _Repo(() async => _me));
    await _settle();
    expect(s.container.read(authControllerProvider).status, AuthStatus.unauthenticated);
    expect(s.keystore.wipes, 1);
  });

  test('a saved session with a cached profile opens instantly, even if the server is asleep', () async {
    final never = Completer<User>();
    final repo = _Repo(() => never.future);
    final s = await _start(tokens: _session, cachedUser: true, repo: repo);
    await _settle();
    final auth = s.container.read(authControllerProvider);
    expect(auth.status, AuthStatus.authenticated);
    expect(auth.user?.fullName, 'Abebe Kebede');
    expect(repo.calls, 1); // confirmed in the background
  });

  test('the background check signs out only a session the server rejects', () async {
    final s = await _start(
      tokens: _session,
      cachedUser: true,
      repo: _Repo(() async => throw const AppFailure(kind: FailureKind.unauthorized, message: 'expired')),
    );
    await _settle();
    expect(s.container.read(authControllerProvider).status, AuthStatus.unauthenticated);
    expect(s.keystore.values, isEmpty);
    expect(s.storage.readCachedUser(), isNull);
  });

  test('offline with a cached profile keeps the session', () async {
    final s = await _start(
      tokens: _session,
      cachedUser: true,
      repo: _Repo(() async => throw const AppFailure(kind: FailureKind.network, message: 'offline')),
    );
    await _settle();
    expect(s.container.read(authControllerProvider).status, AuthStatus.authenticated);
    expect(s.keystore.values, isNotEmpty);
  });

  test('first start without a cache: offline shows Retry (session kept); retry gets in', () async {
    var online = false;
    final repo = _Repo(() async => online ? _me : throw const AppFailure(kind: FailureKind.network, message: 'offline'));
    final s = await _start(tokens: _session, repo: repo);
    await _settle();
    var auth = s.container.read(authControllerProvider);
    expect(auth.status, AuthStatus.initializing);
    expect(auth.error, contains('can\'t reach'));
    expect(s.keystore.values, isNotEmpty);

    online = true;
    await s.container.read(authControllerProvider.notifier).restoreSession();
    auth = s.container.read(authControllerProvider);
    expect(auth.status, AuthStatus.authenticated);
    expect(s.storage.readCachedUser()?['id'], 'u1'); // next start is instant
  });

  testWidgets('the splash plays its intro, then offers Retry when the server cannot be reached', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await PreferencesStorage.create();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        preferencesStorageProvider.overrideWithValue(preferences),
        authControllerProvider.overrideWith(_Offline.new),
      ],
      child: const MaterialApp(home: SplashScreen()),
    ));
    expect(find.text('FRIENDS'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1400));
    final container = ProviderScope.containerOf(tester.element(find.byType(SplashScreen)));
    expect(container.read(splashIntroDoneProvider), isTrue);
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect((container.read(authControllerProvider.notifier) as _Offline).retries, 1);
    await tester.pumpWidget(const SizedBox()); // stop the ambient animation
  });
}

class _Offline extends AuthController {
  int retries = 0;
  @override
  AuthState build() => const AuthState(status: AuthStatus.initializing, error: 'We can\'t reach Friends right now.');
  @override
  Future<void> restoreSession() async => retries++;
}
