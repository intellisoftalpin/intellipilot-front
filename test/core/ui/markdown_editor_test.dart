import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/ui/markdown_editor.dart';
import 'package:intellipilot/core/ui/markdown_text.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  group('MarkdownEditor split layout', () {
    testWidgets('shows the source and a live preview side by side', (
      tester,
    ) async {
      final controller = TextEditingController(text: '# Handbook');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          SizedBox(
            height: 400,
            child: MarkdownEditor(
              controller: controller,
              layout: MarkdownEditorLayout.split,
              expand: true,
            ),
          ),
        ),
      );
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(MarkdownText), findsOneWidget);
    });

    testWidgets('the preview follows what is typed', (tester) async {
      final controller = TextEditingController(text: 'before');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          SizedBox(
            height: 400,
            child: MarkdownEditor(
              controller: controller,
              layout: MarkdownEditorLayout.split,
              expand: true,
            ),
          ),
        ),
      );
      expect(find.text('before'), findsNWidgets(2)); // field + preview

      await tester.enterText(find.byType(TextField), 'after');
      await tester.pump();
      // The preview repaints without a mention list to piggyback on — the
      // wiki has no members, which is what used to leave it frozen.
      expect(find.text('after'), findsNWidgets(2));
    });

    /// The regression this layout was built for: the wiki editor rebuilt its
    /// controller inside `build`, so every keystroke reset the caret to zero.
    /// An externally owned controller must survive a rebuild untouched.
    testWidgets('an owned controller keeps its caret across rebuilds', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'hello world');
      addTearDown(controller.dispose);

      Widget build(String title) => _host(
        Column(
          children: [
            Text(title),
            SizedBox(
              height: 300,
              child: MarkdownEditor(
                controller: controller,
                layout: MarkdownEditorLayout.split,
                expand: true,
              ),
            ),
          ],
        ),
      );

      await tester.pumpWidget(build('one'));
      controller.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();

      // Force a rebuild from above, as emitting cubit state does.
      await tester.pumpWidget(build('two'));
      expect(controller.selection.baseOffset, 5);
      expect(controller.text, 'hello world');
    });

    testWidgets('split mode drops the preview toggle, stacked keeps it', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'x');
      addTearDown(controller.dispose);
      final t = await AppLocalizations.delegate.load(const Locale('en'));

      await tester.pumpWidget(
        _host(
          SizedBox(
            height: 300,
            child: MarkdownEditor(
              controller: controller,
              layout: MarkdownEditorLayout.split,
              expand: true,
            ),
          ),
        ),
      );
      // Nothing to toggle when both panes are already on screen.
      expect(find.text(t.editorPreview), findsNothing);

      await tester.pumpWidget(
        _host(MarkdownEditor(controller: controller)),
      );
      expect(find.text(t.editorPreview), findsOneWidget);
    });

    testWidgets('the toolbar is present so markdown need not be known', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'plain');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          SizedBox(
            height: 300,
            child: MarkdownEditor(
              controller: controller,
              layout: MarkdownEditorLayout.split,
              expand: true,
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.format_bold), findsOneWidget);

      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      await tester.tap(find.byIcon(Icons.format_bold));
      await tester.pump();
      expect(controller.text, '**plain**');
    });
  });
}
