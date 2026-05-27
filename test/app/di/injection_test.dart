import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/l10n/locale_cubit.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/app/theme/theme_cubit.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/network/cookie_setup.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/core/utils/uuid_gen.dart';
import 'package:intellipilot/features/auth/domain/auth_repository.dart';

import '../../helpers/fake_auth_repository.dart';

void main() {
  setUp(() async {
    await resetDependencies();
    await configureForTests(
      settingsStorage: InMemoryKeyValueStorage(),
      uiStorage: InMemoryKeyValueStorage(),
      authRepository: FakeAuthRepository(),
    );
  });

  tearDown(resetDependencies);

  test('all expected singletons are registered', () {
    expect(getIt<UuidGen>(), isA<UuidGen>());
    expect(getIt<ApiConfig>(), isA<ApiConfig>());
    expect(getIt<ApiClient>(), isA<ApiClient>());
    expect(getIt<ThemeCubit>(), isA<ThemeCubit>());
    expect(getIt<LocaleCubit>(), isA<LocaleCubit>());
    expect(getIt<SessionBloc>(), isA<SessionBloc>());
    expect(getIt<AuthRepository>(), isA<AuthRepository>());
  });

  test('ApiClient is a true singleton', () {
    final a = getIt<ApiClient>();
    final b = getIt<ApiClient>();
    expect(identical(a, b), isTrue);
  });

  test('ApiClient wires the session token provider', () {
    final client = getIt<ApiClient>();
    expect(client.config.baseUrl, 'http://localhost:8080');
  });

  group('configureDependencies (production registration path)', () {
    setUp(() async {
      await resetDependencies();
    });

    test('registers the same surface as configureForTests', () async {
      await configureDependencies(
        overrideConfig: const ApiConfig(baseUrl: 'http://localhost:9999'),
        overrideCookies: CookieSetup.inMemory(),
        storageFactory: (_) => InMemoryKeyValueStorage(),
      );

      expect(getIt<UuidGen>(), isA<UuidGen>());
      expect(getIt<ApiConfig>().baseUrl, 'http://localhost:9999');
      expect(getIt<ApiClient>(), isA<ApiClient>());
      expect(getIt<AuthRepository>(), isA<AuthRepository>());
      expect(getIt<SessionBloc>(), isA<SessionBloc>());
      expect(getIt<ThemeCubit>(), isA<ThemeCubit>());
      expect(getIt<LocaleCubit>(), isA<LocaleCubit>());
    });

    test('is idempotent (second call is a no-op)', () async {
      await configureDependencies(
        overrideCookies: CookieSetup.inMemory(),
        storageFactory: (_) => InMemoryKeyValueStorage(),
      );
      final firstClient = getIt<ApiClient>();
      await configureDependencies(
        overrideCookies: CookieSetup.inMemory(),
        storageFactory: (_) => InMemoryKeyValueStorage(),
      );
      expect(identical(getIt<ApiClient>(), firstClient), isTrue);
    });
  });
}
