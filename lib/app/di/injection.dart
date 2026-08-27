import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:intellipilot/app/branding/branding_cubit.dart';
import 'package:intellipilot/app/l10n/locale_cubit.dart';
import 'package:intellipilot/app/l10n/week_start_cubit.dart';
import 'package:intellipilot/app/router/short_links.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/app/theme/theme_cubit.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/io/file_downloader.dart';
import 'package:intellipilot/core/io/file_picker.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/network/cookie_setup.dart';
import 'package:intellipilot/core/network/server_connection_service.dart';
import 'package:intellipilot/core/network/server_endpoint.dart';
import 'package:intellipilot/core/network/sse/project_events_service.dart';
import 'package:intellipilot/core/network/tls/cert_trust.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/core/utils/uuid_gen.dart';
import 'package:intellipilot/features/accounts/data/account_store.dart';
import 'package:intellipilot/features/accounts/data/scoped_storage.dart';
import 'package:intellipilot/features/accounts/data/secret_store.dart';
import 'package:intellipilot/features/accounts/domain/account_scope.dart';
import 'package:intellipilot/features/accounts/domain/account_switcher.dart';
import 'package:intellipilot/features/activity/data/activity_repository_impl.dart';
import 'package:intellipilot/features/activity/data/project_lookups_cache.dart';
import 'package:intellipilot/features/activity/domain/activity_repository.dart';
import 'package:intellipilot/features/admin/data/admin_repository_impl.dart';
import 'package:intellipilot/features/admin/domain/admin_repository.dart';
import 'package:intellipilot/features/auth/data/auth_repository_impl.dart';
import 'package:intellipilot/features/auth/domain/auth_repository.dart';
import 'package:intellipilot/features/backlog/data/backlog_repository_impl.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/board/data/board_repository_impl.dart';
import 'package:intellipilot/features/board/data/board_snapshot_cache.dart';
import 'package:intellipilot/features/board/domain/board_repository.dart';
import 'package:intellipilot/features/catalog/data/catalog_repository_impl.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/compatibility/domain/compatibility_cubit.dart';
import 'package:intellipilot/features/dashboard/data/dashboard_repository_impl.dart';
import 'package:intellipilot/features/dashboard/data/dtos/dashboard_dtos.dart';
import 'package:intellipilot/features/dashboard/domain/dashboard_repository.dart';
import 'package:intellipilot/features/docs/data/docs_repository_impl.dart';
import 'package:intellipilot/features/docs/domain/docs_repository.dart';
import 'package:intellipilot/features/issues_io/data/issues_io_repository_impl.dart';
import 'package:intellipilot/features/issues_io/domain/issues_io_repository.dart';
import 'package:intellipilot/features/links/data/links_repository_http.dart';
import 'package:intellipilot/features/links/domain/links_repository.dart';
import 'package:intellipilot/features/mfa/data/mfa_repository_impl.dart';
import 'package:intellipilot/features/mfa/data/passkey_service.dart';
import 'package:intellipilot/features/mfa/domain/mfa_repository.dart';
import 'package:intellipilot/features/milestones/data/milestones_repository_impl.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';
import 'package:intellipilot/features/profile/data/profile_repository_impl.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/data/projects_repository_impl.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/search/data/dtos/search_dtos.dart';
import 'package:intellipilot/features/search/data/search_repository_impl.dart';
import 'package:intellipilot/features/search/domain/search_repository.dart';
import 'package:intellipilot/features/timesheet/data/timesheet_repository_impl.dart';
import 'package:intellipilot/features/timesheet/domain/timesheet_repository.dart';
import 'package:intellipilot/features/wiki/data/wiki_repository_impl.dart';
import 'package:intellipilot/features/wiki/domain/wiki_repository.dart';
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

  // Accounts hold the scope that namespaces per-user caches. Registered before
  // the boxes because the scoped ones close over it.
  final accountStore = AccountStore(secrets: KeychainSecretStore());
  final accountScope = AccountScope();
  getIt
    ..registerSingleton<AccountStore>(accountStore)
    ..registerSingleton<AccountScope>(accountScope);

  /// Per-account view of a box: every key is prefixed with the active account,
  /// so one account can never read another's cached data. See
  /// [ScopedKeyValueStorage] for why this is a decorator and not six edits.
  KeyValueStorage scoped(String box) => ScopedKeyValueStorage(
    inner: makeStorage(box),
    scope: () => accountScope.key,
  );

  getIt
    // `settings` is deliberately NOT scoped: theme, locale, week-start and the
    // chosen server are the user's global preferences, not one account's data.
    ..registerLazySingleton<KeyValueStorage>(
      () => makeStorage(HiveBoxes.settings),
      instanceName: HiveBoxes.settings,
    )
    ..registerLazySingleton<KeyValueStorage>(
      () => scoped(HiveBoxes.ui),
      instanceName: HiveBoxes.ui,
    )
    ..registerLazySingleton<KeyValueStorage>(
      () => scoped(HiveBoxes.drafts),
      instanceName: HiveBoxes.drafts,
    )
    ..registerLazySingleton<KeyValueStorage>(
      () => scoped(HiveBoxes.boards),
      instanceName: HiveBoxes.boards,
    );

  /// Everything the app believes purely because of *which* server it talks to.
  ///
  /// Two paths can move the app to a different server — the connect wizard and
  /// an account switch — and anything server-derived has to be invalidated by
  /// both. Keeping it in one closure is the point: the compatibility verdict
  /// was handled ad hoc at each site and branding at neither, which is how the
  /// login screen ended up showing one instance's name, motto and logo while
  /// pointed at a completely different one.
  void invalidateServerDerivedState() {
    // Reset before re-loading, so a server that is unreachable or has no
    // branding shows the bundled default rather than the previous server's.
    getIt<BrandingCubit>().reset();
    unawaited(getIt<BrandingCubit>().load());
    getIt<CompatibilityCubit>().reset();
    unawaited(getIt<CompatibilityCubit>().check());
  }

  // --- Server endpoint --------------------------------------------------
  // Desktop/mobile pick their server at runtime; web is served BY its instance
  // and must keep using relative URLs, so `ServerEndpoint.active` is left unset
  // there and `ApiConfig` falls back to its compile-time (empty) value.
  final endpoint = ServerEndpoint(
    storage: makeStorage(HiveBoxes.settings),
    // An explicitly supplied config is authoritative — that is how tests and
    // alternate entry points pin a server. Only when none is given do we fall
    // back to the define / debug-localhost resolution.
    compileTimeBase: overrideConfig?.baseUrl ?? ServerEndpoint.compileTimePin(),
  );
  getIt.registerSingleton<ServerEndpoint>(endpoint);
  if (!kIsWeb) ServerEndpoint.active = endpoint;
  getIt.registerLazySingleton<CertPinStore>(
    () => CertPinStore(makeStorage(HiveBoxes.settings)),
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
    )
    ..registerLazySingleton<WeekStartCubit>(
      () => WeekStartCubit(
        getIt<KeyValueStorage>(instanceName: HiveBoxes.settings),
      ),
    )
    ..registerLazySingleton<ShortLinkResolver>(ShortLinkResolver.new);

  // ApiClient → AuthRepository → SessionBloc → (ApiClient via refresh hook).
  // We break the cycle by capturing the SessionBloc lookups as closures,
  // so the bloc is only resolved on first invocation — by which point
  // construction has completed.
  getIt.registerLazySingleton<ApiClient>(() {
    final cookies = getIt<CookieSetup>();
    final client = ApiClient(
      config: getIt<ApiConfig>(),
      uuidGen: getIt<UuidGen>(),
      tokenProvider: () => getIt<SessionBloc>().currentAccessToken,
      logger: getIt<Logger>(),
      cookieManager: cookies.manager,
      refreshHook: () => getIt<SessionBloc>().refreshHook(),
    );
    // Honour user-pinned certificates for self-hosted instances. No-op on web,
    // and it only ever accepts an exact pinned fingerprint — see CertPinStore.
    installCertPinning(client.dio, getIt<CertPinStore>());
    return client;
  });
  getIt.registerLazySingleton<ServerConnectionService>(
    () => ServerConnectionService(
      endpoint: getIt<ServerEndpoint>(),
      apiClient: getIt<ApiClient>(),
      certPins: getIt<CertPinStore>(),
      cookies: getIt<CookieSetup>(),
      storage: makeStorage,
      onServerChanged: invalidateServerDerivedState,
    ),
  );
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
  getIt.registerLazySingleton<DashboardRepository>(
    () => DashboardRepositoryImpl(getIt<ApiClient>()),
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
  getIt.registerLazySingleton<WikiRepository>(
    () => WikiRepositoryImpl(getIt<ApiClient>()),
  );
  getIt.registerLazySingleton<DocsRepository>(
    () => DocsRepositoryImpl(getIt<ApiClient>()),
  );
  getIt.registerLazySingleton<LinksRepository>(
    () => LinksRepositoryHttp(getIt<ApiClient>()),
  );
  getIt.registerLazySingleton<AdminRepository>(
    () => AdminRepositoryImpl(getIt<ApiClient>()),
  );
  getIt.registerLazySingleton<TimesheetRepository>(
    () => TimesheetRepositoryImpl(getIt<ApiClient>()),
  );
  getIt.registerLazySingleton<SearchRepository>(
    () => SearchRepositoryImpl(getIt<ApiClient>()),
  );
  getIt.registerLazySingleton<IssuesIoRepository>(
    () => IssuesIoRepositoryImpl(getIt<ApiClient>()),
  );
  getIt.registerLazySingleton<BrandingCubit>(
    () => BrandingCubit(getIt<AuthRepository>(), getIt<ApiConfig>()),
  );
  getIt.registerLazySingleton<PasskeyService>(PasskeyService.new);
  getIt.registerLazySingleton<FileDownloader>(FileDownloader.new);
  getIt.registerLazySingleton<FilePicker>(FilePicker.new);
  getIt.registerLazySingleton<BoardSnapshotCache>(
    () => BoardSnapshotCache(
      getIt<KeyValueStorage>(instanceName: HiveBoxes.boards),
    ),
  );
  getIt.registerLazySingleton<ProjectLookupsCache>(
    () => ProjectLookupsCache(
      profile: getIt<ProfileRepository>(),
      projects: getIt<ProjectsRepository>(),
      catalog: getIt<CatalogRepository>(),
      backlog: getIt<BacklogRepository>(),
      milestones: getIt<MilestonesRepository>(),
    ),
  );
  getIt.registerLazySingleton<ProjectEventsService>(
    () => ProjectEventsService(
      baseUrl: () => getIt<ApiConfig>().baseUrl,
      tokenProvider: () => getIt<SessionBloc>().currentAccessToken,
    ),
  );
  getIt.registerLazySingleton<CompatibilityCubit>(
    () => CompatibilityCubit(api: getIt<ApiClient>()),
  );
  getIt.registerLazySingleton<AccountSwitcher>(
    () => AccountSwitcher(
      store: getIt<AccountStore>(),
      scope: getIt<AccountScope>(),
      endpoint: getIt<ServerEndpoint>(),
      apiClient: getIt<ApiClient>(),
      auth: getIt<AuthRepository>(),
      profiles: getIt<ProfileRepository>(),
      // Lazy: SessionBloc depends on the switcher's callbacks, so resolving it
      // eagerly here would close the cycle.
      session: () => getIt<SessionBloc>(),
      events: () => getIt<ProjectEventsService>(),
      onServerChanged: invalidateServerDerivedState,
    ),
  );
  getIt.registerLazySingleton<SessionBloc>(
    () => SessionBloc(
      repository: getIt<AuthRepository>(),
      // Cached board data must never survive the session that read it.
      // Desktop/mobile present the active account's own refresh token; web
      // passes null and keeps using its HttpOnly cookie.
      refreshTokenProvider: kIsWeb
          ? null
          : () => getIt<AccountSwitcher>().currentRefreshToken(),
      onTokensRotated: kIsWeb
          ? null
          : (token) => getIt<AccountSwitcher>().rememberRotatedToken(token),
      onSessionEstablished: kIsWeb
          ? null
          : (tokens) {
              final switcher = getIt<AccountSwitcher>();
              // A switch establishes a session for an account that is already
              // registered; re-adopting would refetch the profile for nothing.
              if (!switcher.isSwitching) {
                unawaited(switcher.adoptAfterLogin(tokens));
              }
            },
      onSessionEnded: () {
        // Scoped by construction: the board cache reads and writes through an
        // account-namespaced box, so this clears only the account that ended —
        // it used to wipe every account's cache at once.
        unawaited(getIt<BoardSnapshotCache>().clearAll());
        if (getIt.isRegistered<ProjectLookupsCache>()) {
          getIt<ProjectLookupsCache>().clear();
        }
      },
    ),
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
  WikiRepository? wikiRepository,
  DocsRepository? docsRepository,
  LinksRepository? linksRepository,
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
    // Registered as already-configured so the router guard does not divert
    // every test to the connect wizard, and the login footer can resolve it.
    ..registerSingleton<ServerEndpoint>(
      ServerEndpoint(
        storage: settingsStorage,
        compileTimeBase: apiConfig?.baseUrl.isNotEmpty ?? false
            ? apiConfig!.baseUrl
            : ApiConfig.devFallbackBaseUrl,
      ),
    )
    ..registerSingleton<CertPinStore>(CertPinStore(settingsStorage))
    // Accounts: registered so the shell and router can resolve them. Tests get
    // an empty in-memory store, which reports no accounts — the switcher then
    // renders nothing, exactly as with a single account.
    ..registerSingleton<AccountScope>(AccountScope())
    ..registerSingleton<AccountStore>(
      AccountStore(secrets: InMemorySecretStore()),
    )
    ..registerSingleton<UuidGen>(const DefaultUuidGen())
    ..registerSingleton<Logger>(Logger())
    ..registerSingleton<ApiConfig>(
      apiConfig ?? const ApiConfig(baseUrl: 'http://localhost:8080'),
    )
    ..registerSingleton<CookieSetup>(CookieSetup.inMemory())
    ..registerSingleton<AuthRepository>(authRepository)
    ..registerSingleton<MfaRepository>(mfaRepository ?? _NoopMfaRepository())
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
    ..registerSingleton<WikiRepository>(wikiRepository ?? _NoopWikiRepository())
    ..registerSingleton<DocsRepository>(docsRepository ?? _NoopDocsRepository())
    ..registerSingleton<LinksRepository>(
      linksRepository ?? _NoopLinksRepository(),
    )
    ..registerSingleton<FileDownloader>(
      fileDownloader ?? const _InMemoryDownloader(),
    )
    ..registerSingleton<FilePicker>(filePicker ?? const _StubFilePicker())
    ..registerSingleton<TimesheetRepository>(_NoopTimesheetRepository())
    ..registerSingleton<SearchRepository>(_NoopSearchRepository())
    ..registerSingleton<DashboardRepository>(_NoopDashboardRepository())
    ..registerSingleton<SessionBloc>(SessionBloc(repository: authRepository))
    ..registerLazySingleton<CompatibilityCubit>(
      () => CompatibilityCubit(api: getIt<ApiClient>()),
    )
    ..registerLazySingleton<AccountSwitcher>(
      () => AccountSwitcher(
        store: getIt<AccountStore>(),
        scope: getIt<AccountScope>(),
        endpoint: getIt<ServerEndpoint>(),
        apiClient: getIt<ApiClient>(),
        auth: authRepository,
        profiles: getIt<ProfileRepository>(),
        session: () => getIt<SessionBloc>(),
        events: () => getIt<ProjectEventsService>(),
      ),
    )
    // Lazy: the constructor registers a WidgetsBinding observer, so it must not
    // be built by unit tests that never bring a binding up. Registered at all
    // because an account switch shuts the live feeds down, and without this the
    // whole switch path threw "not registered" the moment a test exercised it.
    ..registerLazySingleton<ProjectEventsService>(
      () => ProjectEventsService(
        baseUrl: () => getIt<ApiConfig>().baseUrl,
        tokenProvider: () => null,
      ),
    )
    ..registerSingleton<ThemeCubit>(ThemeCubit(settingsStorage))
    ..registerSingleton<LocaleCubit>(LocaleCubit(settingsStorage))
    ..registerSingleton<WeekStartCubit>(WeekStartCubit(settingsStorage))
    ..registerSingleton<ShortLinkResolver>(ShortLinkResolver())
    ..registerSingleton<BrandingCubit>(
      BrandingCubit(authRepository, getIt<ApiConfig>()),
    );

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
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '_NoopProfileRepository.${invocation.memberName}',
  );
}

class _NoopProjectsRepository implements ProjectsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '_NoopProjectsRepository.${invocation.memberName}',
  );
}

class _NoopCatalogRepository implements CatalogRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '_NoopCatalogRepository.${invocation.memberName}',
  );
}

class _NoopBacklogRepository implements BacklogRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '_NoopBacklogRepository.${invocation.memberName}',
  );
}

class _NoopActivityRepository implements ActivityRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '_NoopActivityRepository.${invocation.memberName}',
  );
}

class _NoopMilestonesRepository implements MilestonesRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '_NoopMilestonesRepository.${invocation.memberName}',
  );
}

class _NoopBoardRepository implements BoardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_NoopBoardRepository.${invocation.memberName}');
}

class _NoopDocsRepository implements DocsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_NoopDocsRepository.${invocation.memberName}');
}

class _NoopWikiRepository implements WikiRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_NoopWikiRepository.${invocation.memberName}');
}

class _NoopLinksRepository implements LinksRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_NoopLinksRepository.${invocation.memberName}');
}

class _NoopTimesheetRepository implements TimesheetRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '_NoopTimesheetRepository.${invocation.memberName}',
  );
}

class _NoopSearchRepository implements SearchRepository {
  @override
  Future<Result<SearchResponse, AppFailure>> search(
    String query, {
    String? projectId,
    List<String>? types,
  }) async => const Ok<SearchResponse, AppFailure>(
    SearchResponse(results: [], fuzzy: false),
  );
}

// Returns empty (not throwing) data so widget tests that boot onto the home
// dashboard settle instead of spinning on an infinite loading indicator.
class _NoopDashboardRepository implements DashboardRepository {
  @override
  Future<Result<HomeDashboard, AppFailure>> getHome() async =>
      const Ok<HomeDashboard, AppFailure>(
        HomeDashboard(
          assignedTotal: 0,
          overdue: 0,
          dueSoon: 0,
          vacationDaysLeft: 0,
          byStatus: [],
          byProject: [],
          attention: [],
        ),
      );

  @override
  Future<Result<ProjectDashboard, AppFailure>> getProject(
    String projectId,
  ) async => const Ok<ProjectDashboard, AppFailure>(
    ProjectDashboard(
      total: 0,
      open: 0,
      overdue: 0,
      unassigned: 0,
      bugsOpen: 0,
      myAssigned: 0,
      myOverdue: 0,
      byStatus: [],
      myByStatus: [],
      byType: [],
      byPriority: [],
      byCategory: [],
      epics: [],
      throughput: [],
    ),
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

  @override
  Future<bool> downloadBytes({
    required String filename,
    required String mimeType,
    required List<int> bytes,
  }) async => true;
}

class _StubFilePicker implements FilePicker {
  const _StubFilePicker();

  @override
  bool get isSupported => false;

  @override
  Future<PickedFile?> pickSingleFile() async => null;
}
