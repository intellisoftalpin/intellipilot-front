import 'package:intellipilot/app/di/injection.dart';
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
import 'package:intellipilot/demo/demo_repositories.dart';
import 'package:intellipilot/demo/demo_store.dart';
import 'package:intellipilot/features/activity/domain/activity_repository.dart';
import 'package:intellipilot/features/auth/domain/auth_repository.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/board/domain/board_repository.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/mfa/data/passkey_service.dart';
import 'package:intellipilot/features/mfa/domain/mfa_repository.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/wiki/domain/wiki_repository.dart';
import 'package:logger/logger.dart';

/// Read at bootstrap to decide whether to run the demo wire-up. Flip on with
/// `--dart-define=INTELLIPILOT_DEMO=true`.
bool get isDemoMode => const bool.fromEnvironment(
  'INTELLIPILOT_DEMO',
);

/// Wire the same DI seams as [configureDependencies], but every repository
/// points at in-memory implementations driven by a single [DemoStore]. The
/// ApiClient is still registered because [SessionBloc] threads it through;
/// the demo repos never call its dio.
Future<void> configureDemoDependencies() async {
  if (getIt.isRegistered<ApiClient>()) return;

  final store = DemoStore();
  seedDemoStore(store);

  const makeStorage = HiveKeyValueStorage.new;
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
    )
    ..registerSingleton<DemoStore>(store)
    ..registerLazySingleton<UuidGen>(DefaultUuidGen.new)
    ..registerLazySingleton<Logger>(Logger.new)
    ..registerLazySingleton<ApiConfig>(
      () => const ApiConfig(baseUrl: 'http://demo.local'),
    )
    ..registerSingleton<CookieSetup>(CookieSetup.inMemory())
    ..registerLazySingleton<ThemeCubit>(
      () => ThemeCubit(
        getIt<KeyValueStorage>(instanceName: HiveBoxes.settings),
      ),
    )
    ..registerLazySingleton<LocaleCubit>(
      () => LocaleCubit(
        getIt<KeyValueStorage>(instanceName: HiveBoxes.settings),
      ),
    );

  getIt.registerLazySingleton<ApiClient>(() {
    return ApiClient(
      config: getIt<ApiConfig>(),
      uuidGen: getIt<UuidGen>(),
      tokenProvider: () => getIt<SessionBloc>().currentAccessToken,
      logger: getIt<Logger>(),
    );
  });
  getIt
    ..registerLazySingleton<AuthRepository>(() => DemoAuthRepository(store))
    ..registerLazySingleton<MfaRepository>(() => DemoMfaRepository(store))
    ..registerLazySingleton<ProfileRepository>(
      () => DemoProfileRepository(store),
    )
    ..registerLazySingleton<ProjectsRepository>(
      () => DemoProjectsRepository(store),
    )
    ..registerLazySingleton<CatalogRepository>(
      () => DemoCatalogRepository(store),
    )
    ..registerLazySingleton<BacklogRepository>(
      () => DemoBacklogRepository(store),
    )
    ..registerLazySingleton<ActivityRepository>(
      () => DemoActivityRepository(store),
    )
    ..registerLazySingleton<MilestonesRepository>(
      () => DemoMilestonesRepository(store),
    )
    ..registerLazySingleton<BoardRepository>(
      () => DemoBoardRepository(store),
    )
    ..registerLazySingleton<WikiRepository>(() => DemoWikiRepository(store))
    ..registerLazySingleton<PasskeyService>(DemoPasskeyService.new)
    ..registerLazySingleton<FileDownloader>(FileDownloader.new)
    ..registerLazySingleton<FilePicker>(FilePicker.new)
    ..registerLazySingleton<SessionBloc>(
      () => SessionBloc(repository: getIt<AuthRepository>()),
    );
}
