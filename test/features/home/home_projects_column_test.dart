import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/features/dashboard/data/dtos/dashboard_dtos.dart';
import 'package:intellipilot/features/dashboard/domain/dashboard_repository.dart';
import 'package:intellipilot/features/home/presentation/home_page.dart';
import 'package:intellipilot/features/projects/presentation/widgets/project_avatar.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_profile_repository.dart';

class _FakeDashboard implements DashboardRepository {
  @override
  Future<Result<HomeDashboard, AppFailure>> getHome() async => const Ok(
    HomeDashboard(
      assignedTotal: 84,
      overdue: 0,
      dueSoon: 0,
      vacationDaysLeft: 0,
      byStatus: [],
      byProject: [
        ProjectBucket(
          projectId: 'p1',
          slug: 'pass-securium',
          name: 'Pass Securium',
          issuePrefix: 'PS',
        ),
        ProjectBucket(projectId: 'p2', slug: 'liftoff', name: 'Liftoff'),
      ],
      attention: [],
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpAt(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: HomePage(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    await resetDependencies();
    await configureForTests(
      settingsStorage: InMemoryKeyValueStorage(),
      uiStorage: InMemoryKeyValueStorage(),
      authRepository: FakeAuthRepository(),
      profileRepository: FakeProfileRepository(),
    );
    getIt
      ..unregister<DashboardRepository>()
      ..registerSingleton<DashboardRepository>(_FakeDashboard());
  });

  tearDown(resetDependencies);

  testWidgets('wide: projects get a column of their own on the right', (
    tester,
  ) async {
    await _pumpAt(tester, 1400);

    final project = tester.getTopLeft(find.text('Pass Securium'));
    final kpi = tester.getTopLeft(find.text('84'));
    expect(project.dx, greaterThan(kpi.dx + 600));
    expect(
      project.dy,
      lessThan(tester.getTopLeft(find.textContaining('Welcome')).dy + 100),
      reason: 'the column starts at the top, not below the other sections',
    );
  });

  testWidgets('narrow: projects go back under the rest', (tester) async {
    await _pumpAt(tester, 800);

    final project = tester.getTopLeft(find.text('Pass Securium'));
    final kpi = tester.getTopLeft(find.text('84'));
    expect(project.dy, greaterThan(kpi.dy));
  });

  testWidgets('cards show icon and name, in server order, and no counts', (
    tester,
  ) async {
    await _pumpAt(tester, 1400);

    expect(find.byType(ProjectAvatar), findsNWidgets(2));
    expect(find.text('PS'), findsOneWidget, reason: 'initials fallback');
    expect(
      tester.getTopLeft(find.text('Pass Securium')).dy,
      lessThan(tester.getTopLeft(find.text('Liftoff')).dy),
    );
    expect(find.textContaining('open'), findsNothing);
  });
}
