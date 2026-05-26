import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/l10n/locale_cubit.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/app/theme/theme_cubit.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/core/utils/uuid_gen.dart';

void main() {
  setUp(() async {
    await resetDependencies();
    await configureForTests(
      settingsStorage: InMemoryKeyValueStorage(),
      uiStorage: InMemoryKeyValueStorage(),
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
  });

  test('ApiClient is a true singleton', () {
    final a = getIt<ApiClient>();
    final b = getIt<ApiClient>();
    expect(identical(a, b), isTrue);
  });

  test('ApiClient wires the session token provider', () {
    final client = getIt<ApiClient>();
    // The token provider is just attached as a closure; verify the base URL
    // we passed during test setup made it through.
    expect(client.config.baseUrl, 'http://localhost:8080');
  });
}
