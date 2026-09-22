import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/network/sse/project_events_service.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/meetings/data/dtos/meeting_dtos.dart';
import 'package:intellipilot/features/meetings/presentation/meeting_page.dart';
import 'package:intellipilot/features/meetings/presentation/meetings_page.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_profile_repository.dart';
import 'fake_meetings_repository.dart';

class _Projects extends Fake implements ProjectsRepository {
  _Projects(this.permissions);
  final Set<Permission> permissions;

  @override
  Future<Result<List<Membership>, AppFailure>> listMembers(
    String projectId,
  ) async => Ok([
    Membership(
      id: 'mem',
      projectId: projectId,
      userId: 'u1',
      roleId: 'r1',
      roleSlug: 'dev',
      createdAt: DateTime(2026),
    ),
  ]);

  @override
  Future<Result<List<Role>, AppFailure>> listRoles(String projectId) async =>
      Ok([
        Role(
          id: 'r1',
          projectId: projectId,
          slug: 'dev',
          name: 'Dev',
          order: 0,
          isAdmin: false,
          permissions: permissions,
        ),
      ]);
}

class _Events extends Fake implements ProjectEventsService {
  final _controller = StreamController<LiveEvent>.broadcast();
  @override
  Stream<LiveEvent> watch(String projectId) => _controller.stream;
}

final _today = DateTime.now();
final _day = DateTime(_today.year, _today.month, _today.day);

Meeting _meeting() => Meeting(
  id: 'm1',
  projectId: 'p1',
  title: 'Sprint review',
  date: _day,
  startTime: const MeetingTime(9, 30),
  endTime: const MeetingTime(10, 30),
  timezone: 'UTC',
  location: 'https://meet.example/x',
  summary: '## Decisions\n- ship it',
  transcript: 'Alice: hello\nBob: budget talk',
  version: 2,
  createdAt: DateTime(2026),
  modifiedAt: DateTime(2026),
  artifacts: [
    Attachment(
      id: 'a1',
      projectId: 'p1',
      targetType: 'meeting',
      targetId: 'm1',
      filename: 'call.mp4',
      contentType: 'video/mp4',
      sizeBytes: 5 * 1024 * 1024,
      sha256: '',
      createdAt: DateTime(2026),
      kind: 'recording',
    ),
    Attachment(
      id: 'a2',
      projectId: 'p1',
      targetType: 'meeting',
      targetId: 'm1',
      filename: 'slides.pdf',
      contentType: 'application/pdf',
      sizeBytes: 2048,
      sha256: '',
      createdAt: DateTime(2026),
      kind: 'other',
    ),
  ],
);

late FakeMeetingsRepository _repo;

Future<void> _setUp(Set<Permission> permissions) async {
  await resetDependencies();
  _repo = FakeMeetingsRepository()
    ..rows = [meetingRow('m1', _day, title: 'Sprint review')]
    ..detail = _meeting();
  await configureForTests(
    settingsStorage: InMemoryKeyValueStorage(),
    uiStorage: InMemoryKeyValueStorage(),
    authRepository: FakeAuthRepository(),
    profileRepository: FakeProfileRepository(),
    projectsRepository: _Projects(permissions),
    meetingsRepository: _repo,
  );
  getIt.registerSingleton<ProjectEventsService>(_Events());
}

Future<void> _pump(WidgetTester tester, Widget page, Size size) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: page),
    ),
  );
  await tester.pumpAndSettle();
}

/// The tab bar scrolls on narrow screens: bring the tab into view first.
Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(resetDependencies);

  group('as a developer', () {
    setUp(
      () => _setUp({
        Permission.meetingView,
        Permission.meetingCreate,
        Permission.meetingModify,
      }),
    );

    for (final size in const [Size(1400, 900), Size(390, 800)]) {
      testWidgets('dashboard lays out at ${size.width.toInt()}px', (
        tester,
      ) async {
        await _pump(tester, const MeetingsPage(projectId: 'p1'), size);
        expect(tester.takeException(), isNull);
        expect(find.text('New meeting'), findsOneWidget);
        expect(find.text('Sprint review'), findsOneWidget);
        expect(find.text('09:00–10:00'), findsNothing);
        expect(_repo.rangeCalls, hasLength(1));
      });

      testWidgets('meeting page shows every tab at ${size.width.toInt()}px', (
        tester,
      ) async {
        await _pump(
          tester,
          const MeetingPage(projectId: 'p1', meetingId: 'm1'),
          size,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Sprint review'), findsOneWidget);
        expect(find.textContaining('09:30–10:30'), findsOneWidget);
        // Edit but no delete for a developer.
        expect(find.byKey(const Key('meeting-edit')), findsOneWidget);
        expect(find.byKey(const Key('meeting-delete')), findsNothing);

        await _tapTab(tester, 'Transcript');
        expect(find.textContaining('budget talk'), findsOneWidget);

        await _tapTab(tester, 'Recordings (1)');
        expect(find.text('call.mp4'), findsOneWidget);
        expect(find.byKey(const Key('recording-play')), findsOneWidget);
        expect(find.text('Upload recording'), findsOneWidget);

        await _tapTab(tester, 'Files (1)');
        expect(find.text('slides.pdf'), findsOneWidget);

        await _tapTab(tester, 'Links');
        expect(find.text('Participants'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('without meeting.view', () {
    setUp(() => _setUp({Permission.issueView}));

    testWidgets('the dashboard says so and loads nothing', (tester) async {
      await _pump(
        tester,
        const MeetingsPage(projectId: 'p1'),
        const Size(1200, 800),
      );
      expect(
        find.text("You don't have access to this project's meetings."),
        findsOneWidget,
      );
      expect(_repo.rangeCalls, isEmpty);
    });
  });
}
