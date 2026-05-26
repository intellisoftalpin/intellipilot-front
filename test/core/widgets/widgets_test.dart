import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/widgets/app_scaffold.dart';
import 'package:intellipilot/core/widgets/empty_state.dart';
import 'package:intellipilot/core/widgets/error_view.dart';
import 'package:intellipilot/core/widgets/loading_indicator.dart';
import 'package:intellipilot/core/widgets/primary_button.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('LoadingIndicator renders with optional label', (tester) async {
    await tester.pumpWidget(_wrap(const LoadingIndicator(label: 'Loading…')));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Loading…'), findsOneWidget);
  });

  testWidgets('EmptyState shows title and optional message', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const EmptyState(title: 'No projects', message: 'Create your first'),
      ),
    );
    expect(find.text('No projects'), findsOneWidget);
    expect(find.text('Create your first'), findsOneWidget);
    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
  });

  testWidgets('PrimaryButton renders label and fires onPressed', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(PrimaryButton(label: 'Go', onPressed: () => taps++)),
    );
    await tester.tap(find.text('Go'));
    expect(taps, 1);
  });

  testWidgets('PrimaryButton shows spinner and is disabled when loading', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(PrimaryButton(label: 'Go', loading: true, onPressed: () => taps++)),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    expect(taps, 0);
  });

  testWidgets('PrimaryButton with icon renders as FilledButton.icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(PrimaryButton(label: 'Go', icon: Icons.send, onPressed: () {})),
    );
    expect(find.byIcon(Icons.send), findsOneWidget);
  });

  testWidgets('ErrorView shows status-specific copy and fires onRetry', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      _wrap(
        ErrorView(
          failure: const NetworkFailure(),
          retryLabel: 'Try again',
          onRetry: () => retries++,
        ),
      ),
    );
    expect(find.text('You appear to be offline'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retries, 1);
  });

  testWidgets('ErrorView maps every AppFailure subtype to a distinct title', (
    tester,
  ) async {
    Future<String> titleFor(AppFailure f) async {
      await tester.pumpWidget(_wrap(ErrorView(failure: f)));
      final widget = tester.widget<Text>(
        find
            .descendant(of: find.byType(ErrorView), matching: find.byType(Text))
            .first,
      );
      return widget.data!;
    }

    final titles = <String>{};
    titles
      ..add(await titleFor(const NetworkFailure()))
      ..add(await titleFor(const UnauthorizedFailure()))
      ..add(await titleFor(const ForbiddenFailure()))
      ..add(await titleFor(const NotFoundFailure()))
      ..add(await titleFor(const ValidationFailure(fieldErrors: [])))
      ..add(await titleFor(const ConflictFailure()))
      ..add(await titleFor(const RateLimitedFailure()))
      ..add(await titleFor(const ServerFailure()))
      ..add(await titleFor(const UnknownFailure()));
    expect(titles.length, 9);
  });

  testWidgets('AppScaffold wraps body in a constrained box by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppScaffold(title: Text('T'), body: Text('body')),
      ),
    );
    expect(find.byType(ConstrainedBox), findsWidgets);
    expect(find.text('T'), findsOneWidget);
    expect(find.text('body'), findsOneWidget);
  });

  testWidgets('AppScaffold renders full-bleed when constrained: false', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppScaffold(
          title: Text('T'),
          body: SizedBox.shrink(),
          constrained: false,
        ),
      ),
    );
    expect(find.text('T'), findsOneWidget);
  });
}
