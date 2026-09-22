import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/app/shell/keyboard_shortcuts.dart';
import 'package:intellipilot/app/shell/main_shell.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/network/sse/project_events_service.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/features/activity/data/project_lookups_cache.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/backlog/presentation/widgets/issue_edit_dialog.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/docs/data/dtos/doc_dtos.dart';
import 'package:intellipilot/features/docs/domain/docs_repository.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_profile_repository.dart';

// `u1` is FakeProfileRepository's signed-in user.
const _me = 'u1';
const _alpha = '0190f0e0-0000-7000-8000-00000000000a';
const _beta = '0190f0e0-0000-7000-8000-00000000000b';

final _created = DateTime.utc(2026);

Project _project(String id, String name, String prefix) => Project(
  id: id,
  slug: name.toLowerCase(),
  name: name,
  description: '',
  ownerId: _me,
  visibility: ProjectVisibility.private,
  kanbanEnabled: true,
  backlogEnabled: true,
  wikiEnabled: true,
  epicsEnabled: true,
  createdAt: _created,
  issuePrefix: prefix,
);

TaxonomyItem _type(String projectId, String id, String name) => TaxonomyItem(
  id: id,
  projectId: projectId,
  kind: TaxonomyKind.issueType,
  name: name,
  slug: name.toLowerCase(),
  color: '',
  order: 0,
  createdAt: _created,
);

/// Alpha: the caller is a developer (may create). Beta: a stakeholder (may
/// not).
class _Projects extends Fake implements ProjectsRepository {
  @override
  Future<Result<List<Project>, AppFailure>> listProjects() async => Ok([
    _project(_beta, 'Beta', 'BE'),
    _project(_alpha, 'Alpha', 'AL'),
  ]);

  @override
  Future<Result<List<Membership>, AppFailure>> listMembers(
    String projectId,
  ) async => Ok([
    Membership(
      id: 'm-$projectId',
      projectId: projectId,
      userId: _me,
      roleId: 'r-$projectId',
      roleSlug: projectId == _alpha ? 'dev' : 'stakeholder',
      createdAt: _created,
    ),
  ]);

  @override
  Future<Result<List<Role>, AppFailure>> listRoles(String projectId) async =>
      Ok([
        Role(
          id: 'r-$projectId',
          projectId: projectId,
          slug: projectId == _alpha ? 'dev' : 'stakeholder',
          name: 'Role',
          order: 0,
          isAdmin: false,
          permissions: projectId == _alpha
              ? {Permission.issueView, Permission.issueCreate}
              : {Permission.issueView},
        ),
      ]);

  @override
  Future<Result<ProjectCounts, AppFailure>> getProjectCounts(
    String projectId,
  ) async => const Ok(
    ProjectCounts(myIssues: 0, issues: 0, epics: 0, milestones: 0),
  );

  @override
  Future<Result<Project, AppFailure>> getProject(String id) async =>
      const Err(NotFoundFailure());
}

class _Catalog extends Fake implements CatalogRepository {
  @override
  Future<Result<List<Board>, AppFailure>> listBoards(String projectId) async =>
      const Ok([]);

  @override
  Future<Result<List<TaxonomyItem>, AppFailure>> listTaxonomy(
    String projectId,
    TaxonomyKind kind,
  ) async => Ok([
    if (projectId == _alpha) _type(_alpha, 't-bug', 'Bug'),
    if (projectId == _beta) _type(_beta, 't-story', 'Story'),
  ]);
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

/// Creation fails, so the flow ends at the snackbar instead of opening the
/// (heavy) detail sheet.
class _Backlog extends Fake implements BacklogRepository {
  String? lastProjectId;
  CreateIssueRequest? lastRequest;

  @override
  Future<Result<Issue, AppFailure>> createIssue(
    String projectId,
    CreateIssueRequest body,
  ) async {
    lastProjectId = projectId;
    lastRequest = body;
    return const Err(NetworkFailure());
  }
}

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
        ],
      ),
    ],
  );
}

Future<void> _pump(
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
      // Mounted like the app does: above the router's Navigator.
      builder: (context, child) => GlobalShortcutsShell(
        router: router,
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _t = lookupAppLocalizations(const Locale('en'));
final _createButton = find.byKey(const ValueKey('top-create'));
final _projectField = find.byKey(const ValueKey('issue-create-project'));
final _subjectField = find.byKey(const ValueKey('issue-create-subject'));

FilledButton _submitButton(WidgetTester tester) => tester.widget<FilledButton>(
  find.byKey(const ValueKey('issue-create-submit')),
);

void main() {
  late _Backlog backlog;

  setUp(() async {
    backlog = _Backlog();
    await resetDependencies();
    await configureForTests(
      settingsStorage: InMemoryKeyValueStorage(),
      uiStorage: InMemoryKeyValueStorage(),
      authRepository: FakeAuthRepository(),
      profileRepository: FakeProfileRepository(),
      projectsRepository: _Projects(),
      catalogRepository: _Catalog(),
      backlogRepository: backlog,
      docsRepository: _Docs(),
    );
    getIt
      ..registerSingleton<ProjectEventsService>(_Events())
      ..registerSingleton<ProjectLookupsCache>(
        ProjectLookupsCache(
          profile: getIt<ProfileRepository>(),
          projects: getIt<ProjectsRepository>(),
          catalog: getIt<CatalogRepository>(),
          backlog: getIt<BacklogRepository>(),
          milestones: getIt<MilestonesRepository>(),
        ),
      );
    getIt<SessionBloc>().add(
      const SessionEstablished(
        TokenResponse(accessToken: 't', tokenType: 'Bearer', expiresIn: 3600),
      ),
    );
  });

  tearDown(resetDependencies);

  group('top bar', () {
    // Test fonts draw every glyph a full em wide — far wider than real text —
    // so fitting here means fitting with room to spare on real screens.
    const outside = <double>[360, 480, 640, 820, 935, 1100, 1440, 1920];
    const inProject = <double>[360, 599, 640, 935, 1100, 1440, 1920];
    for (final (location, widths) in [
      ('/projects', outside),
      ('/projects/$_alpha', inProject),
    ]) {
      for (final width in widths) {
        testWidgets('lays out without overflow at ${width.toInt()}px '
            'on $location', (tester) async {
          await _pump(tester, size: Size(width, 700), location: location);
          expect(tester.takeException(), isNull);
          expect(_createButton, findsOneWidget);
        });
      }
    }

    testWidgets('Create carries its label when there is room', (tester) async {
      await _pump(tester, size: const Size(1440, 700), location: '/projects');
      expect(
        find.descendant(of: _createButton, matching: find.text('Create')),
        findsOneWidget,
      );
    });

    testWidgets('Create is icon-only on a phone', (tester) async {
      await _pump(tester, size: const Size(360, 700), location: '/projects');
      expect(
        find.descendant(of: _createButton, matching: find.text('Create')),
        findsNothing,
      );
      expect(find.byTooltip(_t.topCreateTooltip), findsOneWidget);
    });
  });

  group('global create dialog', () {
    testWidgets('preselects the current project and loads its types', (
      tester,
    ) async {
      await _pump(
        tester,
        size: const Size(1440, 900),
        location: '/projects/$_alpha',
      );
      await tester.tap(_createButton);
      await tester.pumpAndSettle();

      expect(find.text(_t.actionNewIssue), findsOneWidget);
      expect(
        find.descendant(of: _projectField, matching: find.text('Alpha · AL')),
        findsOneWidget,
      );

      await tester.tap(find.text(_t.issueFieldType));
      await tester.pumpAndSettle();
      expect(find.text('Bug'), findsWidgets);
      expect(find.text('Story'), findsNothing);
    });

    testWidgets('Create stays disabled until there is a title', (
      tester,
    ) async {
      await _pump(
        tester,
        size: const Size(1440, 900),
        location: '/projects/$_alpha',
      );
      await tester.tap(_createButton);
      await tester.pumpAndSettle();

      expect(_submitButton(tester).onPressed, isNull);
      await tester.enterText(_subjectField, '   ');
      await tester.pump();
      expect(_submitButton(tester).onPressed, isNull);
      await tester.enterText(_subjectField, 'Login broken');
      await tester.pump();
      expect(_submitButton(tester).onPressed, isNotNull);
    });

    testWidgets('switching project reloads types and re-checks permission', (
      tester,
    ) async {
      await _pump(
        tester,
        size: const Size(1440, 900),
        location: '/projects/$_alpha',
      );
      await tester.tap(_createButton);
      await tester.pumpAndSettle();
      await tester.enterText(_subjectField, 'Something');
      await tester.pump();

      await tester.tap(_projectField);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beta · BE').last);
      await tester.pumpAndSettle();

      // Beta's types now, not Alpha's…
      await tester.tap(find.text(_t.issueFieldType));
      await tester.pumpAndSettle();
      expect(find.text('Story'), findsWidgets);
      expect(find.text('Bug'), findsNothing);
      await tester.tap(find.text('Story').last);
      await tester.pumpAndSettle();

      // …and a stakeholder there can't create, whatever the title.
      expect(find.text(_t.issueCreateNoPermission), findsOneWidget);
      expect(_submitButton(tester).onPressed, isNull);
    });

    testWidgets('outside a project nothing is preselected', (tester) async {
      await _pump(tester, size: const Size(1440, 900), location: '/projects');
      await tester.tap(_createButton);
      await tester.pumpAndSettle();
      await tester.enterText(_subjectField, 'Something');
      await tester.pump();

      expect(
        find.descendant(of: _projectField, matching: find.text('Alpha · AL')),
        findsNothing,
      );
      expect(_submitButton(tester).onPressed, isNull);
    });

    testWidgets('submits to the picked project and reports a failure', (
      tester,
    ) async {
      await _pump(
        tester,
        size: const Size(1440, 900),
        location: '/projects/$_alpha',
      );
      await tester.tap(_createButton);
      await tester.pumpAndSettle();
      await tester.enterText(_subjectField, '  Login broken ');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('issue-create-submit')));
      await tester.pumpAndSettle();

      expect(backlog.lastProjectId, _alpha);
      expect(backlog.lastRequest!.subject, 'Login broken');
      expect(find.text(_t.ttActionFailed), findsOneWidget);
      expect(find.text(_t.actionNewIssue), findsNothing);
    });
  });

  group('c shortcut', () {
    testWidgets('opens the create dialog for the current project', (
      tester,
    ) async {
      await _pump(
        tester,
        size: const Size(1440, 900),
        location: '/projects/$_alpha',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pumpAndSettle();

      expect(find.text(_t.actionNewIssue), findsOneWidget);
      expect(
        find.descendant(of: _projectField, matching: find.text('Alpha · AL')),
        findsOneWidget,
      );
    });

    testWidgets('leaves Cmd/Ctrl+C alone', (tester) async {
      await _pump(tester, size: const Size(1440, 900), location: '/projects');
      for (final modifier in [
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.controlLeft,
      ]) {
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(modifier);
        await tester.pumpAndSettle();
      }
      expect(find.text(_t.actionNewIssue), findsNothing);
    });

    testWidgets('types a plain c into a focused text field', (tester) async {
      await _pump(tester, size: const Size(1440, 900), location: '/projects');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      // The subject field has focus now; a `c` there is text, not a second
      // dialog.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });

  group('fixed-project dialog (Issues page, board column)', () {
    testWidgets('returns the trimmed subject and picked type', (
      tester,
    ) async {
      CreateIssueRequest? result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showIssueEditDialog(
                context,
                types: [_type(_alpha, 't-bug', 'Bug')],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // No project picker in this mode.
      expect(_projectField, findsNothing);
      expect(_submitButton(tester).onPressed, isNull);

      await tester.enterText(_subjectField, ' Crash on save ');
      await tester.tap(find.text(_t.issueFieldType));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bug').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('issue-create-submit')));
      await tester.pumpAndSettle();

      expect(result?.subject, 'Crash on save');
      expect(result?.typeId, 't-bug');
    });
  });
}
