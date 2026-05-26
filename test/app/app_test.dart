import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/app/app.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/l10n/locale_cubit.dart';
import 'package:intellipilot/app/theme/theme_cubit.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';

void main() {
  setUp(() async {
    await resetDependencies();
    await configureForTests(
      settingsStorage: InMemoryKeyValueStorage(),
      uiStorage: InMemoryKeyValueStorage(),
    );
  });

  tearDown(resetDependencies);

  testWidgets('rebuilds MaterialApp when theme and locale change',
      (tester) async {
    await tester.pumpWidget(const IntelliPilotApp());
    await tester.pumpAndSettle();
    expect(find.text('Welcome to IntelliPilot'), findsOneWidget);

    await getIt<ThemeCubit>().setMode(ThemeMode.dark);
    await tester.pumpAndSettle();
    await getIt<LocaleCubit>().setLocale(const Locale('en'));
    await tester.pumpAndSettle();

    // Still renders the home page after both transitions.
    expect(find.text('Welcome to IntelliPilot'), findsOneWidget);
  });
}
