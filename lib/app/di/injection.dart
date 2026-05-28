import 'package:get_it/get_it.dart';
import 'package:intellipilot/app/l10n/locale_cubit.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/app/theme/theme_cubit.dart';
import 'package:intellipilot/core/io/file_downloader.dart';
import 'package:intellipilot/core/io/file_picker.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/network/cookie_setup.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/core/utils/uuid_gen.dart';
import 'package:intellipilot/features/activity/data/activity_repository_impl.dart';
import 'package:intellipilot/features/activity/domain/activity_repository.dart';
import 'package:intellipilot/features/auth/data/auth_repository_impl.dart';
import 'package:intellipilot/features/auth/domain/auth_repository.dart';
import 'package:intellipilot/features/backlog/data/backlog_repository_impl.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/board/data/board_repository_impl.dart';
import 'package:intellipilot/features/board/domain/board_repository.dart';
import 'package:intellipilot/features/catalog/data/catalog_repository_impl.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/mfa/data/mfa_repository_impl.dart';
import 'package:intellipilot/features/mfa/data/passkey_service.dart';
import 'package:intellipilot/features/mfa/domain/mfa_repository.dart';
import 'package:intellipilot/features/milestones/data/milestones_repository_impl.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';
import 'package:intellipilot/features/profile/data/profile_repository_impl.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/data/projects_repository_impl.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:logger/logger.dart';

/// Global service locator. Composition is intentionally manual at this stage
/// — when service count grows we can migrate to `injectable` codegen without
/// changing call sites that already go through `getIt<T>()`.
final GetIt getIt = GetIt.instance;

/// Wires all app-lifetime singletons. Must be called from `bootstrap.dart`
/// before `runApp`.
///
/// Tests can call [configureForTests] instead to substitute fakes.
Future<void> configureDependencies({
  ApiConfig? overrideConfig,
  CookieSetup? overrideCookies,
  KeyValueStorage Function(String boxName)? storageFactory,
}) async {
  if (getIt.isRegistered<ApiClient>()) return;

  // --- Boxes (already opened in bootstrap before this runs). -----------
  // Tests can pass [storageFactory] to bypass Hive bootstrap.
  final makeStorage = storageFactory ?? HiveKeyValueStorage.new;
  getIt
    ..registerLazySingleton<KeyValueStorage>(
      () => makeStorage(HiveBoxes.settings),
      instanceName: HiveBoxes.settings,
    )
    ..registerLazySingleton<KeyValueStorage>(
      () => makeStorage(HiveBoxes.ui),
      instanceName: HiveBoxes.ui,
    )
    ..registerLazySingleton<KeyValueStorage>(
      () => makeStorage(HiveBoxes.drafts),
      instanceName: HiveBoxes.drafts,
    )
    ..registerLazySingleton<KeyValueStorage>(
      () => makeStorage(HiveBoxes.boards),
      instanceName: HiveBoxes.boards,
    );

  // --- Primitives ------------------------------------------------------
  final cookies = overrideCookies ?? await CookieSetup.create();
  getIt
    ..registerLazySingleton<UuidGen>(DefaultUuidGen.new)
    ..registerLazySingleton<Logger>(Logger.new)
    ..registerLazySingleton<ApiConfig>(
      () => overrideConfig ?? ApiConfig.fromEnvironment(),
    )
    ..registerSingleton<CookieSetup>(cookies);

  // --- App-scoped blocs/cubits (SessionBloc needs the repository, so we
  //     register the repository first against a not-yet-built ApiClient via
  //     a late binding pattern). ------------------------------------------
  getIt
    ..registerLazySingleton<ThemeCubit>(
      () =>
          ThemeCubit(getIt<KeyValueStorage>(instanceName: HiveBoxes.settings)),
    )
    ..registerLazySingleton<LocaleCubit>(
      () =>
          LocaleCubit(getIt<KeyValueStorage>(instanceName: HiveBoxes.settings)),
    );

  // ApiClient → AuthRepository → SessionBloc → (ApiClient via refresh hook).
  // We break the cycle by capturing the SessionBloc lookups as closures,
  // so the bloc is only resolved on first invocation — by which point
  // construction has completed.
  getIt.registerLazySingleton<ApiClient>(() {
    final cookies = getIt<CookieSetup>();
    return ApiClient(
      config: getIt<ApiConfig>(),
      uuidGen: getIt<UuidGen>(),
      tokenProvider: () => getIt<SessionBloc>().currentAccessToken,
      logger: getIt<Logger>(),
      cookieManager: cookies.manager,
      refreshHook: () => getIt<SessionBloc>().refreshHook(),
    );
  });
  getIt.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(getIt<ApiClient>()),
  );
  getIt.registerLazySingleton<MfaRepository>(
    () => MfaRepositoryImpl(getIt<ApiClient>()),
  );
  getIt.registerLazySingleton<ProfileRepository>(
    () => ProfileRepositoryImpl(getIt<ApiClient>()),
  );
  getIt.registerLazySingleton<ProjectsRepository>(
    () => ProjectsRepositoryImpl(getIt<ApiClient>()),
  );
  getIt.registerLazySingleton<CatalogRepository>(
    () => CatalogRepositoryImpl(getIt<ApiClient>()),
  );
  getIt.registerLazySingleton<BacklogRepository>(
    () => BacklogRepositoryImpl(getIt<ApiClient>()),
  );
  getIt.registerLazySingleton<ActivityRepository>(
    () => ActivityRepositoryImpl(getIt<ApiClient>()),
  );
  getIt.registerLazySingleton<MilestonesRepository>(
    () => MilestonesRepositoryImpl(getIt<ApiClient>()),
  );
  getIt.registerLazySingleton<BoardRepository>(
    () => BoardRepositoryImpl(getIt<ApiClient>()),
  );
  getIt.registerLazySingleton<PasskeyService>(PasskeyService.new);
  getIt.registerLazySingleton<FileDownloader>(FileDownloader.new);
  getIt.registerLazySingleton<FilePicker>(FilePicker.new);
  getIt.registerLazySingleton<SessionBloc>(
    () => SessionBloc(repository: getIt<AuthRepository>()),
  );
}

/// Configure DI with in-memory implementations for tests.
Future<void> configureForTests({
  required KeyValueStorage settingsStorage,
  required KeyValueStorage uiStorage,
  required AuthRepository authRepository,
  KeyValueStorage? draftsStorage,
  MfaRepository? mfaRepository,
  PasskeyService? passkeyService,
  ProfileRepository? profileRepository,
  ProjectsRepository? projectsRepository,
  CatalogRepository? catalogRepository,
  BacklogRepository? backlogRepository,
  ActivityRepository? activityRepository,
  MilestonesRepository? milestonesRepository,
  BoardRepository? boardRepository,
  FileDownloader? fileDownloader,
  FilePicker? filePicker,
  ApiConfig? apiConfig,
}) async {
  getIt
    ..allowReassignment = true
    ..registerSingleton<KeyValueStorage>(
      settingsStorage,
      instanceName: HiveBoxes.settings,
    )
    ..registerSingleton<KeyValueStorage>(uiStorage, instanceName: HiveBoxes.ui)
    ..registerSingleton<KeyValueStorage>(
      draftsStorage ?? InMemoryKeyValueStorage(),
      instanceName: HiveBoxes.drafts,
    )
    ..registerSingleton<KeyValueStorage>(
      InMemoryKeyValueStorage(),
      instanceName: HiveBoxes.boards,
    )
    ..registerSingleton<UuidGen>(const DefaultUuidGen())
    ..registerSingleton<Logger>(Logger())
    ..registerSingleton<ApiConfig>(
      apiConfig ?? const ApiConfig(baseUrl: 'http://localhost:8080'),
    )
    ..registerSingleton<CookieSetup>(CookieSetup.inMemory())
    ..registerSingleton<AuthRepository>(authRepository)
    ..registerSingleton<MfaRepository>(
      mfaRepository ?? _NoopMfaRepository(),
    )
    ..registerSingleton<PasskeyService>(
      passkeyService ?? const _StubPasskeyService(),
    )
    ..registerSingleton<ProfileRepository>(
      profileRepository ?? _NoopProfileRepository(),
    )
    ..registerSingleton<ProjectsRepository>(
      projectsRepository ?? _NoopProjectsRepository(),
    )
    ..registerSingleton<CatalogRepository>(
      catalogRepository ?? _NoopCatalogRepository(),
    )
    ..registerSingleton<BacklogRepository>(
      backlogRepository ?? _NoopBacklogRepository(),
    )
    ..registerSingleton<ActivityRepository>(
      activityRepository ?? _NoopActivityRepository(),
    )
    ..registerSingleton<MilestonesRepository>(
      milestonesRepository ?? _NoopMilestonesRepository(),
    )
    ..registerSingleton<BoardRepository>(
      boardRepository ?? _NoopBoardRepository(),
    )
    ..registerSingleton<FileDownloader>(
      fileDownloader ?? const _InMemoryDownloader(),
    )
    ..registerSingleton<FilePicker>(filePicker ?? const _StubFilePicker())
    ..registerSingleton<SessionBloc>(SessionBloc(repository: authRepository))
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

// Defaults used by [configureForTests] when callers don't pass explicit
// fakes. Keeping them in this file (not the test tree) means widget tests
// using the production DI helper still resolve the type without crashing.

class _NoopMfaRepository implements MfaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_NoopMfaRepository.${invocation.memberName}');
}

class _StubPasskeyService implements PasskeyService {
  const _StubPasskeyService();

  @override
  bool get isSupported => false;

  @override
  Future<Map<String, dynamic>> register(Map<String, dynamic> _) async =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> authenticate(Map<String, dynamic> _) async =>
      throw UnimplementedError();
}

class _NoopProfileRepository implements ProfileRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(
        '_NoopProfileRepository.${invocation.memberName}',
      );
}

class _NoopProjectsRepository implements ProjectsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(
        '_NoopProjectsRepository.${invocation.memberName}',
      );
}

class _NoopCatalogRepository implements CatalogRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(
        '_NoopCatalogRepository.${invocation.memberName}',
      );
}

class _NoopBacklogRepository implements BacklogRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(
        '_NoopBacklogRepository.${invocation.memberName}',
      );
}

class _NoopActivityRepository implements ActivityRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(
        '_NoopActivityRepository.${invocation.memberName}',
      );
}

class _NoopMilestonesRepository implements MilestonesRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(
        '_NoopMilestonesRepository.${invocation.memberName}',
      );
}

class _NoopBoardRepository implements BoardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(
        '_NoopBoardRepository.${invocation.memberName}',
      );
}

class _InMemoryDownloader implements FileDownloader {
  const _InMemoryDownloader();

  @override
  bool get canDownload => false;

  @override
  Future<bool> download({
    required String filename,
    required String mimeType,
    required String contents,
  }) async => true;
}

class _StubFilePicker implements FilePicker {
  const _StubFilePicker();

  @override
  bool get isSupported => false;

  @override
  Future<PickedFile?> pickSingleFile() async => null;
}
