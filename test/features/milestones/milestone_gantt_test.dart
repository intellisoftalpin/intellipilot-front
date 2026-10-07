import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';
import 'package:intellipilot/features/milestones/presentation/cubits/all_milestones_cubit.dart';
import 'package:intellipilot/features/milestones/presentation/widgets/milestone_gantt.dart';
import 'package:intellipilot/features/milestones/presentation/widgets/progress_ring.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';
import 'package:mocktail/mocktail.dart';

Milestone _m(
  String id, {
  bool closed = false,
  DateTime? start,
  DateTime? end,
  String projectId = 'p1',
}) => Milestone(
  id: id,
  projectId: projectId,
  name: 'Milestone $id',
  slug: id,
  closed: closed,
  order: 1,
  version: 1,
  createdAt: DateTime(2026),
  modifiedAt: DateTime(2026),
  startDate: start,
  endDate: end,
);

GanttEntry _e(Milestone m, {MilestoneProjectRef? project}) => GanttEntry(
  milestone: m,
  color: const Color(0xFF0079BC),
  taskTotal: 4,
  taskClosed: 1,
  project: project,
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

class _Repo extends Mock implements MilestonesRepository {}

void main() {
  setUpAll(() => registerFallbackValue(MilestoneStateFilter.open));

  group('ProgressRing', () {
    testWidgets('a full ring shows a check, not "100%"', (tester) async {
      await _pump(tester, const ProgressRing(value: 1, size: 28));
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.text('100%'), findsNothing);
    });

    testWidgets('partial progress shows the percentage', (tester) async {
      await _pump(tester, const ProgressRing(value: 0.33, size: 28));
      expect(find.text('33%'), findsOneWidget);
    });
  });

  group('MilestoneGantt', () {
    final now = DateTime.now();
    final open = _m(
      'a',
      start: now.subtract(const Duration(days: 10)),
      end: now.add(const Duration(days: 20)),
    );
    final done = _m(
      'b',
      closed: true,
      start: now.subtract(const Duration(days: 60)),
      end: now.subtract(const Duration(days: 30)),
    );

    testWidgets('completed band is collapsed and shows only its count', (
      tester,
    ) async {
      var toggled = 0;
      await _pump(
        tester,
        MilestoneGantt(
          open: [_e(open)],
          completed: [_e(done)],
          completedCount: 3,
          completedExpanded: false,
          completedLoading: false,
          onToggleCompleted: () => toggled++,
          zoom: GanttZoom.initial,
          showBusinessRelease: false,
          onOpen: (_) {},
        ),
      );
      expect(find.text('Milestone a'), findsOneWidget);
      expect(find.text('Milestone b'), findsNothing);
      expect(find.text('Completed (3)'), findsOneWidget);
      await tester.tap(find.text('Completed (3)'));
      expect(toggled, 1);
    });

    testWidgets('expanded band lists the completed milestones', (
      tester,
    ) async {
      await _pump(
        tester,
        MilestoneGantt(
          open: [_e(open)],
          completed: [_e(done)],
          completedCount: 1,
          completedExpanded: true,
          completedLoading: false,
          onToggleCompleted: () {},
          zoom: GanttZoom.initial,
          showBusinessRelease: false,
          onOpen: (_) {},
        ),
      );
      expect(find.text('Milestone b'), findsOneWidget);
    });

    testWidgets('grouping by project adds a header per project', (
      tester,
    ) async {
      const p1 = MilestoneProjectRef(
        id: 'p1',
        name: 'Pass Securium',
        prefix: 'PS',
        color: '#0079bc',
      );
      const p2 = MilestoneProjectRef(
        id: 'p2',
        name: 'IntelliPilot',
        prefix: 'IP',
        color: '#cc0000',
      );
      final other = _m(
        'c',
        projectId: 'p2',
        start: now,
        end: now.add(const Duration(days: 5)),
      );
      await _pump(
        tester,
        MilestoneGantt(
          open: [
            _e(open, project: p1),
            _e(other, project: p2),
          ],
          completed: const [],
          completedCount: 0,
          completedExpanded: false,
          completedLoading: false,
          onToggleCompleted: () {},
          zoom: GanttZoom.initial,
          showBusinessRelease: false,
          grouping: GanttGrouping.byProject,
          onOpen: (_) {},
        ),
      );
      expect(find.text('Pass Securium'), findsOneWidget);
      expect(find.text('IntelliPilot'), findsOneWidget);
      expect(find.text('PS'), findsOneWidget);
      expect(find.text('IP'), findsOneWidget);
    });

    testWidgets('opens centred on today', (tester) async {
      await _pump(
        tester,
        MilestoneGantt(
          open: [_e(open)],
          completed: const [],
          completedCount: 0,
          completedExpanded: false,
          completedLoading: false,
          onToggleCompleted: () {},
          zoom: GanttZoom.initial,
          showBusinessRelease: false,
          onOpen: (_) {},
        ),
      );
      final pill = tester.getCenter(find.text('Today'));
      // The chart viewport starts after the 340px label column (+16 gutter)
      // and runs to the right edge.
      const viewportCentre = 356 + (1400 - 356) / 2;
      expect(pill.dx, closeTo(viewportCentre, 8));
    });
  });

  group('AllMilestonesCubit', () {
    final page = MilestoneOverviewPage(
      items: [
        MilestoneOverview(
          milestone: _m('a'),
          project: const MilestoneProjectRef(
            id: 'p1',
            name: 'P',
            prefix: 'P',
            color: '',
          ),
          taskTotal: 0,
          taskClosed: 0,
          epicCount: 0,
        ),
      ],
      completedCount: 2,
    );

    test(
      'loads only open milestones, then completed on first expand',
      () async {
        final repo = _Repo();
        when(() => repo.listAll(state: any(named: 'state'))).thenAnswer(
          (_) async => Ok<MilestoneOverviewPage, AppFailure>(page),
        );
        final cubit = AllMilestonesCubit(repo: repo);
        await cubit.load();
        verify(() => repo.listAll(state: MilestoneStateFilter.open)).called(1);
        verifyNever(() => repo.listAll(state: MilestoneStateFilter.completed));
        expect((cubit.state as AllMilestonesLoaded).completedCount, 2);

        await cubit.toggleCompleted();
        verify(
          () => repo.listAll(state: MilestoneStateFilter.completed),
        ).called(1);
        expect((cubit.state as AllMilestonesLoaded).completedExpanded, isTrue);
        await cubit.close();
      },
    );
  });
}
