import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/members_cubit.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/features/projects/presentation/widgets/join_project.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_profile_repository.dart';

const _pid = '0190f0e0-0000-7000-8000-000000000001';

Project _project() => Project(
  id: _pid,
  slug: 'proj',
  name: 'Proj',
  description: '',
  ownerId: 'owner',
  visibility: ProjectVisibility.private,
  kanbanEnabled: true,
  backlogEnabled: true,
  wikiEnabled: true,
  epicsEnabled: true,
  createdAt: DateTime.utc(2026),
  issuePrefix: 'PR',
);

/// A project owned by someone else. The signed-in user (`u1`) is not a member
/// until [joinProject] (or [addAs]) puts him in.
class _Projects extends Fake implements ProjectsRepository {
  final members = <Membership>[_member('owner', 'r-admin', 'admin')];
  final joins = <String>[];
  bool failJoin = false;

  // Listed out of order on purpose: the join dialog sorts and preselects
  // the admin role regardless.
  final roles = [
    const Role(
      id: 'r-stake',
      projectId: _pid,
      slug: 'stakeholder',
      name: 'Stakeholder',
      order: 3,
      isAdmin: false,
      permissions: {Permission.issueView},
    ),
    const Role(
      id: 'r-admin',
      projectId: _pid,
      slug: 'admin',
      name: 'Admin',
      order: 0,
      isAdmin: true,
      permissions: {},
    ),
  ];

  static Membership _member(String userId, String roleId, String slug) =>
      Membership(
        id: 'mem-$userId',
        projectId: _pid,
        userId: userId,
        roleId: roleId,
        roleSlug: slug,
        createdAt: DateTime(2026),
      );

  void addAs(String userId, String slug) {
    final role = roles.firstWhere((r) => r.slug == slug);
    members.add(_member(userId, role.id, slug));
  }

  @override
  Future<Result<Project, AppFailure>> getProject(String id) async =>
      Ok(_project());

  @override
  Future<Result<ProjectCounts, AppFailure>> getProjectCounts(
    String projectId,
  ) async => const Ok(
    ProjectCounts(myIssues: 0, issues: 0, epics: 0, milestones: 0),
  );

  @override
  Future<Result<List<Membership>, AppFailure>> listMembers(
    String projectId,
  ) async => Ok(List.of(members));

  @override
  Future<Result<List<Role>, AppFailure>> listRoles(String projectId) async =>
      Ok(List.of(roles));

  @override
  Future<Result<Unit, AppFailure>> joinProject(
    String projectId, {
    required String roleSlug,
  }) async {
    joins.add(roleSlug);
    if (failJoin) return const Err(ForbiddenFailure());
    addAs('u1', roleSlug);
    return const Ok<Unit, AppFailure>(Unit.instance);
  }
}

UserProfile _superadmin() => UserProfile(
  id: 'u1',
  email: 'u@e.com',
  username: 'user1',
  fullName: 'User One',
  lang: 'en',
  timezone: 'UTC',
  isActive: true,
  isSuperadmin: true,
  mustChangePassword: false,
  createdAt: DateTime(2026, 5, 27),
);

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  group('Permission.isRead', () {
    test('is every view plus the team timesheet, nothing that writes', () {
      expect(
        Permission.values.where((p) => p.isRead).map((p) => p.wire).toSet(),
        {
          'project.view',
          'member.view',
          'role.view',
          'epic.view',
          'issue.view',
          'milestone.view',
          'milestone.business_release.view',
          'wiki.view',
          'doc_source.view',
          'meeting.view',
          'time.view_all',
        },
      );
    });
  });

  group('resolveProjectAccess', () {
    test(
      'a non-member superadmin reads everything and writes nothing',
      () async {
        final access = await resolveProjectAccess(
          _Projects(),
          projectId: _pid,
          userId: 'u1',
          isSuperadmin: true,
        );
        expect(access.isMember, isFalse);
        expect(access.readAll, isTrue);
        expect(access.has(Permission.meetingView), isTrue);
        expect(access.has(Permission.timeViewAll), isTrue);
        expect(access.has(Permission.memberAdd), isFalse);
        expect(access.has(Permission.projectModify), isFalse);
        expect(access.has(Permission.issueCreate), isFalse);
      },
    );

    test('a non-member without superadmin gets nothing', () async {
      final access = await resolveProjectAccess(
        _Projects(),
        projectId: _pid,
        userId: 'u1',
      );
      expect(access.isMember, isFalse);
      expect(access.has(Permission.projectView), isFalse);
    });

    test('a superadmin member writes by role and still reads all', () async {
      final repo = _Projects()..addAs('u1', 'stakeholder');
      final access = await resolveProjectAccess(
        repo,
        projectId: _pid,
        userId: 'u1',
        isSuperadmin: true,
      );
      expect(access.isMember, isTrue);
      expect(access.has(Permission.meetingView), isTrue);
      expect(access.has(Permission.issueCreate), isFalse);
    });
  });

  group('ProjectDetailCubit', () {
    test(
      'a non-member superadmin may join; after joining he may not',
      () async {
        final repo = _Projects();
        final changes = ValueNotifier(0);
        final cubit = ProjectDetailCubit(
          repo: repo,
          projectId: _pid,
          currentUserId: 'u1',
          isSuperadmin: true,
          accessChanges: changes,
        );
        addTearDown(cubit.close);
        await cubit.load();
        var s = cubit.state as ProjectDetailLoaded;
        expect(s.canJoin, isTrue);
        expect(s.has(Permission.memberView), isTrue);
        expect(s.has(Permission.memberAdd), isFalse);

        // Someone else's join (the banner, the Members tab) announces the
        // change; the cubit picks up the new rights without a reload.
        repo.addAs('u1', 'admin');
        changes.value++;
        await Future<void>.delayed(Duration.zero);
        s = cubit.state as ProjectDetailLoaded;
        expect(s.canJoin, isFalse);
        expect(s.isMember, isTrue);
        expect(s.has(Permission.memberAdd), isTrue);
      },
    );

    test('a member is never offered to join', () async {
      final cubit = ProjectDetailCubit(
        repo: _Projects()..addAs('u1', 'stakeholder'),
        projectId: _pid,
        currentUserId: 'u1',
        isSuperadmin: true,
      );
      addTearDown(cubit.close);
      await cubit.load();
      expect((cubit.state as ProjectDetailLoaded).canJoin, isFalse);
    });
  });

  group('MembersCubit.join', () {
    test('joins with the role and reloads the roster', () async {
      final repo = _Projects();
      final cubit = MembersCubit(repo: repo, projectId: _pid);
      addTearDown(cubit.close);
      await cubit.load();
      expect(await cubit.join('admin'), isNull);
      expect(repo.joins, ['admin']);
      final s = cubit.state as MembersLoaded;
      expect(s.members.map((m) => m.userId), contains('u1'));
    });

    test('returns the failure', () async {
      final repo = _Projects()..failJoin = true;
      final cubit = MembersCubit(repo: repo, projectId: _pid);
      addTearDown(cubit.close);
      await cubit.load();
      expect(await cubit.join('admin'), isA<ForbiddenFailure>());
      expect((cubit.state as MembersLoaded).lastError, isA<ForbiddenFailure>());
    });
  });

  group('JoinProjectCard', () {
    Future<_Projects> pump(
      WidgetTester tester, {
      required bool superadmin,
    }) async {
      final repo = _Projects();
      final detail = ProjectDetailCubit(
        repo: repo,
        projectId: _pid,
        currentUserId: 'u1',
        isSuperadmin: superadmin,
      );
      final members = MembersCubit(repo: repo, projectId: _pid);
      addTearDown(detail.close);
      addTearDown(members.close);
      await tester.pumpWidget(
        _app(
          MultiBlocProvider(
            providers: [
              BlocProvider.value(value: detail),
              BlocProvider.value(value: members),
            ],
            child: JoinProjectCard(roles: repo.roles),
          ),
        ),
      );
      await tester.runAsync(() async {
        await detail.load();
        await members.load();
      });
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('is hidden from a non-superadmin', (tester) async {
      await pump(tester, superadmin: false);
      expect(find.text('Join project'), findsNothing);
    });

    testWidgets('joins with the preselected admin role', (tester) async {
      final repo = await pump(tester, superadmin: true);
      await tester.tap(find.widgetWithText(FilledButton, 'Join project'));
      await tester.pumpAndSettle();

      // Admin is preselected even though the roster lists it second.
      final dialog = find.byType(AlertDialog);
      expect(
        find.descendant(of: dialog, matching: find.text('Admin')),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: dialog,
          matching: find.widgetWithText(FilledButton, 'Join project'),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(repo.joins, ['admin']);
    });
  });

  group('read-only banner in the shell', () {
    late _Projects projects;

    setUp(() async {
      projects = _Projects();
      await resetDependencies();
      await configureForTests(
        settingsStorage: InMemoryKeyValueStorage(),
        uiStorage: InMemoryKeyValueStorage(),
        authRepository: FakeAuthRepository(),
        profileRepository: FakeProfileRepository(
          getProfileHandler: () async => Ok(_superadmin()),
        ),
        projectsRepository: projects,
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

    Future<void> pumpShell(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(1400, 1000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        initialLocation: '/projects/$_pid',
        routes: [
          ShellRoute(
            builder: (_, _, child) => MainShell(child: child),
            routes: [
              GoRoute(
                path: '/projects/:id',
                builder: (_, _) => const Center(child: Text('page')),
              ),
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

    final banner = find.text(
      "Read-only — you're not a member of this project.",
    );

    testWidgets('shows for a non-member superadmin and goes after joining', (
      tester,
    ) async {
      await pumpShell(tester);
      expect(banner, findsOneWidget);
      expect(find.text('page'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Join project'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Join project'),
        ),
      );
      await tester.pumpAndSettle();

      expect(projects.joins, ['admin']);
      expect(banner, findsNothing);
      expect(find.text('page'), findsOneWidget);
    });

    testWidgets('does not show for a member', (tester) async {
      projects.addAs('u1', 'stakeholder');
      getIt<ProjectAccessCache>().clear();
      await pumpShell(tester);
      expect(banner, findsNothing);
    });
  });
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
