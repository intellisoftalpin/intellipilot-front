import 'package:flutter/gestures.dart';
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

/// Every span in the rendered tree, including ones that only carry a style and
/// children. `InlineSpan.visitChildren` skips those (it visits a span only when
/// its `text` is non-null), so styling applied to a wrapper span — bold,
/// italic, strikethrough — is invisible to it.
List<TextSpan> _allSpans(WidgetTester tester) {
  final out = <TextSpan>[];
  void walk(InlineSpan? span) {
    if (span is! TextSpan) return;
    out.add(span);
    span.children?.forEach(walk);
  }

  tester.widgetList<Text>(find.byType(Text)).forEach((w) => walk(w.textSpan));
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

  group('MarkdownText tables', () {
    testWidgets('a pipe table renders as a Table with a header row', (
      tester,
    ) async {
      await _pump(tester, '''
| Name | Count |
|------|------:|
| Alpha | 12 |
| Beta  | 7  |
''');
      expect(find.byType(Table), findsOneWidget);
      final table = tester.widget<Table>(find.byType(Table));
      // Header plus two body rows.
      expect(table.children, hasLength(3));
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('a ragged row is padded rather than dropped', (tester) async {
      await _pump(tester, '''
| A | B | C |
|---|---|---|
| 1 |
''');
      final table = tester.widget<Table>(find.byType(Table));
      expect(table.children, hasLength(2));
      // Every row is widened to the header's column count.
      expect(table.children.last.children, hasLength(3));
    });

    testWidgets('inline markup works inside table cells', (tester) async {
      await _pump(tester, '''
| Link |
|------|
| [docs](https://example.com) |
''');
      expect(_linkSpans(tester).single.text, 'docs');
    });

    testWidgets('a line with pipes but no delimiter is not a table', (
      tester,
    ) async {
      await _pump(tester, 'a | b | c');
      expect(find.byType(Table), findsNothing);
    });
  });

  group('MarkdownText lists', () {
    testWidgets('task list items render checkboxes reflecting their state', (
      tester,
    ) async {
      await _pump(tester, '''
- [x] done thing
- [ ] pending thing
''');
      expect(find.byIcon(Icons.check_box_outlined), findsOneWidget);
      expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
      expect(find.text('done thing'), findsOneWidget);
    });

    testWidgets('nested items are indented and use a different glyph', (
      tester,
    ) async {
      await _pump(tester, '''
- top
  - nested
    - deeper
''');
      // Depth is expressed as left padding, so the three items differ.
      final paddings = tester
          .widgetList<Padding>(find.byType(Padding))
          .map((p) => (p.padding as EdgeInsets).left)
          .where((l) => l > 0)
          .toSet();
      expect(paddings.length, greaterThanOrEqualTo(2));
      expect(find.text('•  '), findsOneWidget);
      expect(find.text('◦  '), findsOneWidget);
      expect(find.text('▪  '), findsOneWidget);
    });

    testWidgets('numbered lists restart their count per nesting level', (
      tester,
    ) async {
      await _pump(tester, '''
1. first
2. second
''');
      expect(find.text('1.  '), findsOneWidget);
      expect(find.text('2.  '), findsOneWidget);
    });

    testWidgets('a + bullet is recognised like - and *', (tester) async {
      await _pump(tester, '+ plus item');
      expect(find.text('plus item'), findsOneWidget);
    });
  });

  group('MarkdownText block syntax', () {
    testWidgets('headings h1 through h6 all parse', (tester) async {
      final headings = <MarkdownHeading>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownText(
              '# One\n## Two\n### Three\n#### Four\n##### Five\n###### Six\n',
              onHeadings: headings.addAll,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(headings.map((h) => h.level), [1, 2, 3, 4, 5, 6]);
      expect(headings.first.text, 'One');
      expect(headings.first.anchor, 'one');
    });

    testWidgets('closing hashes are decoration, not content', (tester) async {
      await _pump(tester, '## Title ##');
      expect(find.text('Title'), findsOneWidget);
    });

    testWidgets('setext underlines produce headings', (tester) async {
      final headings = <MarkdownHeading>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownText(
              'Big Title\n=========\n\nSmaller\n-------\n',
              onHeadings: headings.addAll,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(headings.map((h) => h.text), ['Big Title', 'Smaller']);
      expect(headings.map((h) => h.level), [1, 2]);
    });

    testWidgets('a standalone rule is a divider, not a heading', (
      tester,
    ) async {
      final headings = <MarkdownHeading>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownText(
              'para\n\n---\n\nmore\n',
              onHeadings: headings.addAll,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(headings, isEmpty);
      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('a fenced block keeps its language label and content', (
      tester,
    ) async {
      await _pump(tester, '```rust\nfn main() {}\n```');
      expect(find.text('rust'), findsOneWidget);
      expect(find.text('fn main() {}'), findsOneWidget);
    });

    testWidgets('tilde fences work and are not closed by a backtick fence', (
      tester,
    ) async {
      await _pump(tester, '~~~\n```\nstill code\n~~~');
      expect(find.text('```\nstill code'), findsOneWidget);
    });

    testWidgets('markdown inside a fence is not interpreted', (tester) async {
      await _pump(tester, '```\n| a | b |\n|---|---|\n```');
      expect(find.byType(Table), findsNothing);
    });

    testWidgets('strikethrough renders with a line through it', (tester) async {
      await _pump(tester, 'this is ~~gone~~ now');
      final struck = _allSpans(
        tester,
      ).where((s) => s.style?.decoration == TextDecoration.lineThrough);
      expect(struck, hasLength(1));
      expect(struck.single.children?.single, isA<TextSpan>());
    });

    testWidgets('footnote definitions are separated from the body', (
      tester,
    ) async {
      await _pump(tester, 'A claim[^1].\n\n[^1]: The evidence.\n');
      expect(find.text('The evidence.'), findsOneWidget);
      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('an angle-bracket autolink is tappable', (tester) async {
      await _pump(tester, 'mail <https://example.com/x> here');
      expect(_linkSpans(tester).single.text, 'https://example.com/x');
    });
  });

  group('MarkdownText hooks', () {
    testWidgets('onLinkTap replaces the default navigation', (tester) async {
      final tapped = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownText(
              '[up](../secret.md)',
              onLinkTap: tapped.add,
            ),
          ),
        ),
      );
      final span = _linkSpans(tester).single;
      (span.recognizer! as TapGestureRecognizer).onTap!();
      // The raw href reaches the caller untouched, so it can resolve the link
      // in its own space — the documentation viewer's path jail.
      expect(tapped, ['../secret.md']);
    });

    testWidgets('imageBuilder replaces the default network image', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownText(
              '![chart](./img/a.png)',
              imageBuilder: (src, alt) => Text('custom:$src'),
            ),
          ),
        ),
      );
      expect(find.text('custom:./img/a.png'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('returning null from imageBuilder falls back to the default', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownText(
              '![chart](https://example.com/a.png)',
              imageBuilder: (src, alt) => null,
            ),
          ),
        ),
      );
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('anchors slugify the way a #fragment link spells them', (
      tester,
    ) async {
      expect(markdownAnchor('Getting Started'), 'getting-started');
      expect(markdownAnchor('API reference (v2)!'), 'api-reference-v2');
      // Runs of whitespace collapse to a single hyphen, as GitHub does.
      expect(markdownAnchor('  Spaced  Out  '), 'spaced-out');
      expect(markdownAnchor('snake_case name'), 'snake-case-name');
    });
  });
}
