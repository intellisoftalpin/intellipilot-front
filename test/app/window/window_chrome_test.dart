import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/app/window/desktop_window.dart';
import 'package:intellipilot/app/window/window_chrome.dart';

const _min = WindowButton.minimize;
const _max = WindowButton.maximize;
const _close = WindowButton.close;

void main() {
  group('DecorationLayout.parse', () {
    test("GNOME's default: a lone close button on the right", () {
      expect(
        DecorationLayout.parse('appmenu:close'),
        DecorationLayout.fallback,
      );
    });

    test('all three on the right, in the given order', () {
      expect(
        DecorationLayout.parse('icon:minimize,maximize,close'),
        const DecorationLayout(right: [_min, _max, _close]),
      );
    });

    test('buttons on the left (elementary, macOS-like layouts)', () {
      expect(
        DecorationLayout.parse('close,minimize,maximize:menu'),
        const DecorationLayout(left: [_close, _min, _max]),
      );
    });

    test('no colon: everything on the left, as GTK reads it', () {
      expect(
        DecorationLayout.parse('close'),
        const DecorationLayout(left: [_close]),
      );
    });

    test('empty or unknown entries give no buttons', () {
      expect(DecorationLayout.parse(''), const DecorationLayout());
      expect(
        DecorationLayout.parse('appmenu,spacer:icon'),
        const DecorationLayout(),
      );
    });
  });

  group('window chrome', () {
    tearDown(() => DesktopWindow.debugOverride(active: false));

    Widget bar() => const MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            WindowControls.left(),
            Expanded(child: Text('content')),
            WindowControls.right(),
          ],
        ),
      ),
    );

    testWidgets('nothing at all off the Linux desktop', (tester) async {
      await tester.pumpWidget(bar());
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('draws exactly the configured buttons on their side', (
      tester,
    ) async {
      DesktopWindow.debugOverride(
        active: true,
        layout: const DecorationLayout(left: [_min], right: [_close]),
      );
      await tester.pumpWidget(bar());

      final close = tester.getCenter(find.byIcon(Icons.close));
      final minimize = tester.getCenter(find.byIcon(Icons.minimize));
      final content = tester.getCenter(find.text('content'));
      expect(minimize.dx, lessThan(content.dx));
      expect(close.dx, greaterThan(content.dx));
      expect(find.byIcon(Icons.crop_square), findsNothing);
    });

    testWidgets('a screen without a top bar gets a drag band and buttons', (
      tester,
    ) async {
      DesktopWindow.debugOverride(
        active: true,
        layout: DecorationLayout.fallback,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: BareWindowFrame(child: Scaffold(body: Text('login'))),
        ),
      );
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.byType(WindowDragArea), findsOneWidget);
    });

    testWidgets('the band steps aside while the app top bar is shown', (
      tester,
    ) async {
      DesktopWindow.debugOverride(
        active: true,
        layout: DecorationLayout.fallback,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: BareWindowFrame(
            child: Scaffold(
              body: TitleBarClaim(child: WindowControls.right()),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(WindowDragArea), findsNothing);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });
  });
}
