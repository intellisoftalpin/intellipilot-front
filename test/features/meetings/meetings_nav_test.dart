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
import 'package:intellipilot/features/meetings/domain/project_access_cache.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_profile_repository.dart';

const _pid = '0190f0e0-0000-7000-8000-000000000001';

/// The signed-in user (`u1` in [FakeProfileRepository]) holds a role with
/// [permissions] in the project.
class _Projects extends Fake implements ProjectsRepository {
  _Projects(this.permissions);
  final Set<Permission> permissions;
  int rosterCalls = 0;

  @override
  Future<Result<ProjectCounts, AppFailure>> getProjectCounts(
    String projectId,
  ) async => const Ok(
    ProjectCounts(myIssues: 0, issues: 0, epics: 0, milestones: 0),
  );

  @override
  Future<Result<Project, AppFailure>> getProject(String id) async =>
      const Err(NotFoundFailure());

  @override
  Future<Result<List<Membership>, AppFailure>> listMembers(
    String projectId,
  ) async {
    rosterCalls++;
    return Ok([
      Membership(
        id: 'mem',
        projectId: projectId,
        userId: 'u1',
        roleId: 'r1',
        roleSlug: 'custom',
        createdAt: DateTime(2026),
      ),
    ]);
  }

  @override
  Future<Result<List<Role>, AppFailure>> listRoles(String projectId) async =>
      Ok([
        Role(
          id: 'r1',
          projectId: projectId,
          slug: 'custom',
          name: 'Custom',
          order: 0,
          isAdmin: false,
          permissions: permissions,
        ),
      ]);
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

Future<void> _setUp(Set<Permission> permissions) async {
  await resetDependencies();
  await configureForTests(
    settingsStorage: InMemoryKeyValueStorage(),
    uiStorage: InMemoryKeyValueStorage(),
    authRepository: FakeAuthRepository(),
    profileRepository: FakeProfileRepository(),
    projectsRepository: _Projects(permissions),
    catalogRepository: _Catalog(),
    docsRepository: _Docs(),
  );
  getIt.registerSingleton<ProjectEventsService>(_Events());
  getIt<SessionBloc>().add(
    const SessionEstablished(
      TokenResponse(accessToken: 't', tokenType: 'Bearer', expiresIn: 3600),
    ),
  );
}

Future<void> _pump(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(1400, 1000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  Widget page(GoRouterState s) => Center(child: Text('page:${s.uri.path}'));
  final router = GoRouter(
    initialLocation: '/projects/$_pid',
    routes: [
      ShellRoute(
        builder: (_, _, child) => MainShell(child: child),
        routes: [
          GoRoute(path: '/projects/:id', builder: (_, s) => page(s)),
          GoRoute(path: '/projects/:id/:a', builder: (_, s) => page(s)),
        ],
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(resetDependencies);

  final meetingsRow = find.byIcon(Icons.groups_outlined);

  // Set up outside the widget test's fake clock (as the shell tests do): the
  // session schedules its token refresh an hour out, which a fake-async test
  // would report as a pending timer.
  group('without meeting.view', () {
    setUp(() => _setUp({Permission.issueView, Permission.wikiView}));

    testWidgets('there is no Meetings entry', (tester) async {
      await _pump(tester);
      expect(meetingsRow, findsNothing);
    });
  });

  group('with meeting.view', () {
    setUp(() => _setUp({Permission.issueView, Permission.meetingView}));

    testWidgets('the Meetings entry shows and navigates', (tester) async {
      await _pump(tester);
      expect(meetingsRow, findsOneWidget);
      await tester.tap(meetingsRow);
      await tester.pumpAndSettle();
      expect(find.text('page:/projects/$_pid/meetings'), findsOneWidget);
    });

    test('access is cached per project and cleared on demand', () async {
      final projects = getIt<ProjectsRepository>() as _Projects;
      final cache = getIt<ProjectAccessCache>();
      expect((await cache.access(_pid)).has(Permission.meetingView), isTrue);
      await cache.access(_pid);
      expect(projects.rosterCalls, 1);
      cache.clear();
      await cache.access(_pid);
      expect(projects.rosterCalls, 2);
    });
  });
}
