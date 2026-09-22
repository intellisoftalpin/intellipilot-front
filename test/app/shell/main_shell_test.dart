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
import 'package:intellipilot/l10n/generated/app_localizations.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_profile_repository.dart';

const _pid = '0190f0e0-0000-7000-8000-000000000001';

class _Projects extends Fake implements ProjectsRepository {
  @override
  Future<Result<ProjectCounts, AppFailure>> getProjectCounts(
    String projectId,
  ) async => const Ok(
    ProjectCounts(myIssues: 1, issues: 2, epics: 3, milestones: 4),
  );

  @override
  Future<Result<Project, AppFailure>> getProject(String id) async =>
      const Err(NotFoundFailure());
}

class _Catalog extends Fake implements CatalogRepository {
  @override
  Future<Result<List<Board>, AppFailure>> listBoards(String projectId) async =>
      const Ok([]);
}

class _Docs extends Fake implements DocsRepository {
  @override
  Future<Result<List<DocSource>, AppFailure>> listSources(
    String projectId,
  ) async => const Ok([]);
}

class _Events extends Fake implements ProjectEventsService {
  final _controller = StreamController<LiveEvent>.broadcast();

  @override
  Stream<LiveEvent> watch(String projectId) => _controller.stream;
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
      projectsRepository: _Projects(),
      catalogRepository: _Catalog(),
      docsRepository: _Docs(),
    );
    getIt.registerSingleton<ProjectEventsService>(_Events());
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
}
