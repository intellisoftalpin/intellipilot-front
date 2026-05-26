import 'package:get_it/get_it.dart';
import 'package:intellipilot/app/l10n/locale_cubit.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/app/theme/theme_cubit.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/core/utils/uuid_gen.dart';
import 'package:logger/logger.dart';

/// Global service locator. Composition is intentionally manual at this stage
/// — when service count grows we can migrate to `injectable` codegen without
/// changing call sites that already go through `getIt<T>()`.
final GetIt getIt = GetIt.instance;

/// Wires all app-lifetime singletons. Must be called from `bootstrap.dart`
/// before `runApp`.
///
/// Tests can call [configureForTests] instead to substitute fakes.
Future<void> configureDependencies({ApiConfig? overrideConfig}) async {
  if (getIt.isRegistered<ApiClient>()) return;

  // --- Boxes (already opened in bootstrap before this runs). -----------
  getIt
    ..registerLazySingleton<KeyValueStorage>(
      () => HiveKeyValueStorage(HiveBoxes.settings),
      instanceName: HiveBoxes.settings,
    )
    ..registerLazySingleton<KeyValueStorage>(
      () => HiveKeyValueStorage(HiveBoxes.ui),
      instanceName: HiveBoxes.ui,
    );

  // --- Primitives ------------------------------------------------------
  getIt
    ..registerLazySingleton<UuidGen>(DefaultUuidGen.new)
    ..registerLazySingleton<Logger>(Logger.new)
    ..registerLazySingleton<ApiConfig>(
      () => overrideConfig ?? ApiConfig.fromEnvironment(),
    );

  // --- App-scoped blocs/cubits ----------------------------------------
  getIt
    ..registerLazySingleton<SessionBloc>(SessionBloc.new)
    ..registerLazySingleton<ThemeCubit>(
      () =>
          ThemeCubit(getIt<KeyValueStorage>(instanceName: HiveBoxes.settings)),
    )
    ..registerLazySingleton<LocaleCubit>(
      () =>
          LocaleCubit(getIt<KeyValueStorage>(instanceName: HiveBoxes.settings)),
    );

  // --- HTTP client (depends on SessionBloc + UuidGen) -----------------
  getIt.registerLazySingleton<ApiClient>(() {
    final session = getIt<SessionBloc>();
    return ApiClient(
      config: getIt<ApiConfig>(),
      uuidGen: getIt<UuidGen>(),
      tokenProvider: () => session.currentAccessToken,
      logger: getIt<Logger>(),
    );
  });
}

/// Configure DI with in-memory implementations for tests.
Future<void> configureForTests({
  required KeyValueStorage settingsStorage,
  required KeyValueStorage uiStorage,
  ApiConfig? apiConfig,
}) async {
  getIt
    ..allowReassignment = true
    ..registerSingleton<KeyValueStorage>(
      settingsStorage,
      instanceName: HiveBoxes.settings,
    )
    ..registerSingleton<KeyValueStorage>(uiStorage, instanceName: HiveBoxes.ui)
    ..registerSingleton<UuidGen>(const DefaultUuidGen())
    ..registerSingleton<Logger>(Logger())
    ..registerSingleton<ApiConfig>(
      apiConfig ?? const ApiConfig(baseUrl: 'http://localhost:8080'),
    )
    ..registerSingleton<SessionBloc>(SessionBloc())
    ..registerSingleton<ThemeCubit>(ThemeCubit(settingsStorage))
    ..registerSingleton<LocaleCubit>(LocaleCubit(settingsStorage));

  getIt.registerSingleton<ApiClient>(
    ApiClient(
      config: getIt<ApiConfig>(),
      uuidGen: getIt<UuidGen>(),
      tokenProvider: () => getIt<SessionBloc>().currentAccessToken,
      logger: getIt<Logger>(),
    ),
  );
}

Future<void> resetDependencies() async => getIt.reset();
