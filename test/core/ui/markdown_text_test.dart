import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/core/models/user_ref.dart';
import 'package:intellipilot/core/ui/markdown_text.dart';

/// Walks the rendered paragraph spans and returns every one that carries a tap
/// recognizer — i.e. every span the user can actually click.
List<TextSpan> _linkSpans(WidgetTester tester) {
  final out = <TextSpan>[];
  for (final w in tester.widgetList<Text>(find.byType(Text))) {
    final span = w.textSpan;
    span?.visitChildren((s) {
      if (s is TextSpan && s.recognizer != null) out.add(s);
      return true;
    });
  }
  return out;
}

Future<void> _pump(WidgetTester tester, String source) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: MarkdownText(source)),
    ),
  );
}

void main() {
  group('MarkdownText links', () {
    testWidgets('[label](url) renders a tappable span showing the label', (
      tester,
    ) async {
      await _pump(tester, 'See [the docs](https://example.com/guide) now.');
      final links = _linkSpans(tester);
      expect(links, hasLength(1));
      expect(links.single.text, 'the docs');
      expect(links.single.mouseCursor, SystemMouseCursors.click);
    });

    testWidgets('bare https URLs are autolinked', (tester) async {
      await _pump(tester, 'Ticket at https://example.com/x please');
      final links = _linkSpans(tester);
      expect(links, hasLength(1));
      expect(links.single.text, 'https://example.com/x');
    });

    testWidgets('trailing sentence punctuation stays out of the link', (
      tester,
    ) async {
      await _pump(tester, 'Go to https://example.com/page.');
      expect(_linkSpans(tester).single.text, 'https://example.com/page');
    });

    testWidgets('bare-URL matcher does not double-match a markdown link', (
      tester,
    ) async {
      await _pump(tester, '[docs](https://example.com)');
      final links = _linkSpans(tester);
      expect(links, hasLength(1));
      expect(links.single.text, 'docs');
    });

    testWidgets('URLs inside code spans are not linkified', (tester) async {
      await _pump(tester, 'run `curl https://example.com` first');
      expect(_linkSpans(tester), isEmpty);
    });

    testWidgets('links inside list items are still tappable', (tester) async {
      await _pump(tester, '- see [one](https://a.example)\n- and plain text');
      expect(_linkSpans(tester), hasLength(1));
    });

    testWidgets('plain text produces no recognizers', (tester) async {
      await _pump(tester, 'nothing clickable here');
      expect(_linkSpans(tester), isEmpty);
    });

    testWidgets('recognizers survive a source change without crashing', (
      tester,
    ) async {
      await _pump(tester, 'a [one](https://a.example)');
      expect(_linkSpans(tester).single.text, 'one');
      await _pump(tester, 'b [two](https://b.example)');
      await tester.pumpAndSettle();
      expect(_linkSpans(tester).single.text, 'two');
    });
  });

  group('MarkdownText navigation', () {
    // The description/comment renderer wraps everything in a SelectionArea so
    // one drag selects the whole text. That competes with link taps in the
    // gesture arena, so assert a real tap still routes rather than being
    // swallowed by selection.
    testWidgets('tapping an in-app link navigates via go_router', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                const Scaffold(body: MarkdownText('[go](/target)')),
          ),
          GoRoute(
            path: '/target',
            builder: (_, _) => const Scaffold(body: Text('ARRIVED')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      expect(find.text('ARRIVED'), findsNothing);

      // Tap the glyphs themselves, not the centre of the stretched paragraph
      // box — the label is short and left-aligned, so the box centre is empty
      // space past the end of the text and would hit no span at all.
      final para = find.byType(RichText).first;
      await tester.tapAt(tester.getTopLeft(para) + const Offset(4, 8));
      await tester.pumpAndSettle();

      expect(find.text('ARRIVED'), findsOneWidget);
    });
  });

  group('MarkdownText images', () {
    testWidgets('![alt](url) renders an image, not a link with a stray !', (
      tester,
    ) async {
      await _pump(tester, 'before ![shot](https://x.example/a.png) after');
      expect(find.byType(Image), findsOneWidget);
      // Regression: the image matcher must beat the link matcher, which shares
      // the `[..](..)` tail and would otherwise leave a literal "!" behind.
      expect(_linkSpans(tester), isEmpty);
      expect(find.textContaining('!'), findsNothing);
    });

    testWidgets('a plain link next to an image still works', (tester) async {
      await _pump(
        tester,
        '![a](https://x.example/a.png) and [docs](https://d.example)',
      );
      expect(find.byType(Image), findsOneWidget);
      expect(_linkSpans(tester).single.text, 'docs');
    });
  });

  group('MarkdownText mentions', () {
    final ann = UserRef(
      id: 'u1',
      username: 'ann',
      fullName: 'Ann Lee',
      email: 'ann@example.com',
      card: const UserCard(),
    );

    testWidgets('a known @handle renders as a chip', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownText('ping @ann please', mentions: {'ann': ann}),
          ),
        ),
      );
      expect(find.text('Ann Lee'), findsOneWidget);
    });

    testWidgets('an unknown @handle stays plain text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownText('ping @nobody', mentions: {'ann': ann}),
          ),
        ),
      );
      expect(find.text('Ann Lee'), findsNothing);
      expect(find.textContaining('@nobody'), findsOneWidget);
    });

    testWidgets('an email address does not open a mention', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownText('mail a@ann.com', mentions: {'ann': ann}),
          ),
        ),
      );
      expect(find.text('Ann Lee'), findsNothing);
    });
  });

  group('MarkdownText blocks', () {
    testWidgets('bold and italic still render after the link change', (
      tester,
    ) async {
      await _pump(tester, 'a **bold** and _italic_ line');
      expect(find.byType(MarkdownText), findsOneWidget);
      expect(_linkSpans(tester), isEmpty);
    });

    testWidgets('empty source renders nothing', (tester) async {
      await _pump(tester, '');
      expect(find.byType(SelectionArea), findsNothing);
    });
  });
}
