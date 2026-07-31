import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/ui/breadcrumb_bar.dart';

Future<void> _pump(WidgetTester tester, List<Crumb> crumbs) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: BreadcrumbBar(crumbs: crumbs)),
    ),
  );
}

void main() {
  testWidgets('the trailing crumb is tappable when it carries a target', (
    tester,
  ) async {
    // Regression: the active (last) segment used to render as plain text even
    // with onTap set, silently dropping the entity-key link on detail pages.
    var taps = 0;
    await _pump(tester, [
      Crumb(label: 'Projects', onTap: () {}),
      Crumb(label: 'PS-398', mono: true, onTap: () => taps++),
    ]);

    await tester.tap(find.text('PS-398'));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('a trailing crumb with no target stays plain text', (
    tester,
  ) async {
    await _pump(tester, [
      Crumb(label: 'Projects', onTap: () {}),
      const Crumb(label: 'Backlog'),
    ]);

    expect(
      find.ancestor(of: find.text('Backlog'), matching: find.byType(InkWell)),
      findsNothing,
    );
  });

  testWidgets('intermediate crumbs remain tappable', (tester) async {
    var taps = 0;
    await _pump(tester, [
      Crumb(label: 'Projects', onTap: () => taps++),
      const Crumb(label: 'Backlog'),
    ]);

    await tester.tap(find.text('Projects'));
    await tester.pump();

    expect(taps, 1);
  });
}
