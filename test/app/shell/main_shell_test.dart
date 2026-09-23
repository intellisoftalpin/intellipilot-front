import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/app/shell/main_shell.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/network/sse/project_events_service.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/docs/data/dtos/doc_dtos.dart';
import 'package:intellipilot/features/docs/domain/docs_repository.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/search/data/dtos/search_dtos.dart';
import 'package:intellipilot/features/search/domain/search_repository.dart';
import 'package:intellipilot/features/wiki/data/dtos/wiki_dtos.dart';
import 'package:intellipilot/features/wiki/domain/wiki_repository.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_profile_repository.dart';

const _pid = '0190f0e0-0000-7000-8000-000000000001';

class _Projects extends Fake implements ProjectsRepository {
  /// Every id the counts endpoint was asked for — a project *ref* landing
  /// here would 404 against the real server.
  final countsFor = <String>[];

  @override
  Future<Result<ProjectCounts, AppFailure>> getProjectCounts(
    String projectId,
  ) async {
    countsFor.add(projectId);
    return const Ok(
      ProjectCounts(myIssues: 1, issues: 2, epics: 3, milestones: 4),
    );
  }

  @override
  Future<Result<List<Project>, AppFailure>> listProjects() async =>
      Ok([_project()]);

  @override
  Future<Result<Project, AppFailure>> getProject(String id) async =>
      id == _pid ? Ok(_project()) : const Err(NotFoundFailure());

  @override
  Future<Result<Project, AppFailure>> getProjectByPrefix(String prefix) async =>
      prefix.toLowerCase() == _prefix
      ? Ok(_project())
      : const Err(NotFoundFailure());
}

const _prefix = 'pr';

Project _project() => Project(
  id: _pid,
  slug: 'proj',
  name: 'Proj',
  description: '',
  ownerId: 'u1',
  visibility: ProjectVisibility.private,
  kanbanEnabled: true,
  backlogEnabled: true,
  wikiEnabled: true,
  epicsEnabled: true,
  createdAt: DateTime.utc(2026),
  issuePrefix: 'PR',
);

class _Catalog extends Fake implements CatalogRepository {
  @override
  Future<Result<List<Board>, AppFailure>> listBoards(String projectId) async =>
      const Ok([]);
}

final _t = lookupAppLocalizations(const Locale('en'));

class _Wiki extends Fake implements WikiRepository {
  @override
  Future<Result<List<WikiPage>, AppFailure>> list(String projectId) async =>
      const Ok([]);
}

/// Records what the palette asked the search endpoint to rank by.
class _Search extends Fake implements SearchRepository {
  final boosts = <String?>[];

  @override
  Future<Result<SearchResponse, AppFailure>> search(
    String query, {
    String? projectId,
    String? boostProjectId,
    List<String>? types,
  }) async {
    boosts.add(boostProjectId);
    return const Ok(SearchResponse(results: [], fuzzy: false));
  }
}

class _Docs extends Fake implements DocsRepository {
  @override
  Future<Result<List<DocSource>, AppFailure>> listSources(
    String projectId,
  ) async => const Ok([]);
}

class _Events extends Fake implements ProjectEventsService {
  final _controller = StreamController<LiveEvent>.broadcast();

  /// Every id subscribed to; the live feed is addressed by id as well.
  final watched = <String>[];

  @override
  Stream<LiveEvent> watch(String projectId) {
    watched.add(projectId);
    return _controller.stream;
  }
}

/// A router whose pages are placeholders, so only the shell is under test.
GoRouter _router(String initial) {
  Widget page(GoRouterState s) => Center(child: Text('page:${s.uri.path}'));
  return GoRouter(
    initialLocation: initial,
    routes: [
      ShellRoute(
        builder: (_, _, child) => MainShell(child: child),
        routes: [
          GoRoute(path: '/projects', builder: (_, s) => page(s)),
          GoRoute(path: '/projects/:id', builder: (_, s) => page(s)),
          GoRoute(path: '/projects/:id/:a', builder: (_, s) => page(s)),
          GoRoute(path: '/projects/:id/:a/:b', builder: (_, s) => page(s)),
        ],
      ),
    ],
  );
}

Future<GoRouter> _pump(
  WidgetTester tester, {
  required Size size,
  required String location,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = _router(location);
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  late InMemoryKeyValueStorage ui;
  late _Projects projects;
  late _Events events;
  late _Search search;

  setUp(() async {
    ui = InMemoryKeyValueStorage();
    await resetDependencies();
    await configureForTests(
      settingsStorage: InMemoryKeyValueStorage(),
      uiStorage: ui,
      authRepository: FakeAuthRepository(),
      profileRepository: FakeProfileRepository(
        getProfileHandler: () async => const Err(NetworkFailure()),
      ),
      projectsRepository: projects = _Projects(),
      wikiRepository: _Wiki(),
      catalogRepository: _Catalog(),
      docsRepository: _Docs(),
    );
    getIt
      ..registerSingleton<ProjectEventsService>(events = _Events())
      ..registerSingleton<SearchRepository>(search = _Search());
    getIt<SessionBloc>().add(
      const SessionEstablished(
        TokenResponse(accessToken: 't', tokenType: 'Bearer', expiresIn: 3600),
      ),
    );
  });

  tearDown(resetDependencies);

  final settingsIcon = find.byIcon(Icons.settings_outlined);
  final menuButton = find.byTooltip('Open project menu');

  group('project rail in a short window', () {
    for (final expanded in [true, false]) {
      testWidgets(
        '${expanded ? 'expanded' : 'collapsed'}: last row scrolls into reach',
        (tester) async {
          await ui.set<bool>('project_rail.expanded', expanded);
          // 800px keeps the top bar in its compact form beside either rail
          // width; the full bar needs ~900px to itself.
          final router = await _pump(
            tester,
            size: const Size(800, 400),
            location: '/projects/$_pid',
          );

          expect(find.byType(Scrollbar), findsOneWidget);
          // Settings starts below the fold…
          expect(tester.getTopLeft(settingsIcon).dy, greaterThan(400));

          // …and scrolling brings it into view, where it navigates.
          await tester.ensureVisible(settingsIcon);
          await tester.pumpAndSettle();
          expect(tester.getBottomLeft(settingsIcon).dy, lessThanOrEqualTo(400));
          await tester.tap(settingsIcon);
          await tester.pumpAndSettle();

          expect(
            router.routerDelegate.currentConfiguration.uri.path,
            '/projects/$_pid/settings',
          );
        },
      );
    }
  });

  group('project drawer on narrow screens', () {
    testWidgets('opens from the menu button, navigates and closes', (
      tester,
    ) async {
      final router = await _pump(
        tester,
        size: const Size(400, 800),
        location: '/projects/$_pid',
      );

      // No rail on a phone: its rows only exist inside the drawer.
      expect(find.text('Issues'), findsNothing);
      await tester.tap(menuButton);
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);
      expect(find.text('Issues'), findsOneWidget);
      // Counts ride along, as in the rail.
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.text('Issues'));
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/projects/$_pid/issues',
      );
      expect(find.byType(Drawer), findsNothing);
      expect(find.text('page:/projects/$_pid/issues'), findsOneWidget);
    });

    testWidgets('closes when a route change comes from elsewhere', (
      tester,
    ) async {
      final router = await _pump(
        tester,
        size: const Size(400, 800),
        location: '/projects/$_pid',
      );
      await tester.tap(menuButton);
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);

      router.go('/projects/$_pid/epics');
      await tester.pumpAndSettle();

      expect(find.byType(Drawer), findsNothing);
    });

    testWidgets('absent on wide screens, where the rail shows instead', (
      tester,
    ) async {
      await _pump(
        tester,
        size: const Size(1000, 800),
        location: '/projects/$_pid',
      );

      expect(menuButton, findsNothing);
      expect(find.text('Issues'), findsOneWidget);
    });

    testWidgets('absent outside a project', (tester) async {
      await _pump(tester, size: const Size(400, 800), location: '/projects');

      expect(menuButton, findsNothing);
      expect(find.text('page:/projects'), findsOneWidget);
    });
  });

  group('short project URLs', () {
    // The address bar holds `/projects/pr/...` — the project's prefix, not
    // its id ([ShortLinkGate] rewrites every project URL to that form). The
    // counts endpoint and the live feed are addressed by id, so the shell has
    // to resolve the segment before it asks for anything: passing the prefix
    // through 404s, and the badges never appear.
    testWidgets('rail asks for counts and events by id, never the prefix', (
      tester,
    ) async {
      await _pump(
        tester,
        size: const Size(1000, 800),
        location: '/projects/$_prefix/issues',
      );

      expect(projects.countsFor, [_pid]);
      expect(events.watched, [_pid]);
      // The badge proves the counts actually landed.
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('drawer does the same on a phone', (tester) async {
      await _pump(
        tester,
        size: const Size(400, 800),
        location: '/projects/$_prefix/issues',
      );
      await tester.tap(menuButton);
      await tester.pumpAndSettle();

      expect(projects.countsFor, [_pid]);
      expect(events.watched, [_pid]);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('palette ranks by the resolved id, not the prefix', (
      tester,
    ) async {
      // `boost_project_id` is typed as an id server-side: a prefix there is
      // a 400 for the whole request, which blanked search inside projects.
      await _pump(
        tester,
        size: const Size(1000, 800),
        location: '/projects/$_prefix/issues',
      );

      await tester.tap(find.byTooltip(_t.topNavSearchPlaceholder).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'auth');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(search.boosts, isNotEmpty);
      expect(search.boosts, everyElement(_pid));
    });

    testWidgets('rail links keep the short form', (tester) async {
      final router = await _pump(
        tester,
        size: const Size(1000, 800),
        location: '/projects/$_prefix/issues',
      );

      await tester.tap(find.text('Epics'));
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/projects/$_prefix/epics',
      );
    });
  });
}
