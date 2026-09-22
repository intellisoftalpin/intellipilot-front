import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/features/meetings/data/dtos/meeting_dtos.dart';
import 'package:intellipilot/features/meetings/presentation/meeting_format.dart';
import 'package:intellipilot/features/meetings/presentation/widgets/meeting_edit_dialog.dart';
import 'package:intellipilot/features/meetings/presentation/widgets/month_calendar.dart';
import 'package:intellipilot/features/meetings/presentation/widgets/transcript_view.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  group('validateMeetingForm', () {
    final day = DateTime(2026, 9, 22);
    test('needs a title and a date', () {
      expect(
        validateMeetingForm(title: ' ', date: day, start: null, end: null),
        MeetingFormError.titleRequired,
      );
      expect(
        validateMeetingForm(title: 'x', date: null, start: null, end: null),
        MeetingFormError.dateRequired,
      );
      expect(
        validateMeetingForm(title: 'x', date: day, start: null, end: null),
        isNull,
      );
    });

    test('an end time needs a start and must come after it', () {
      const nine = MeetingTime(9, 0);
      const ten = MeetingTime(10, 0);
      expect(
        validateMeetingForm(title: 'x', date: day, start: null, end: ten),
        MeetingFormError.endNeedsStart,
      );
      expect(
        validateMeetingForm(title: 'x', date: day, start: ten, end: nine),
        MeetingFormError.endBeforeStart,
      );
      expect(
        validateMeetingForm(title: 'x', date: day, start: ten, end: ten),
        MeetingFormError.endBeforeStart,
      );
      expect(
        validateMeetingForm(title: 'x', date: day, start: nine, end: ten),
        isNull,
      );
      // A start alone is fine.
      expect(
        validateMeetingForm(title: 'x', date: day, start: nine, end: null),
        isNull,
      );
    });
  });

  group('MeetingEditDialog', () {
    testWidgets('refuses an empty title, then returns the form', (
      tester,
    ) async {
      MeetingFormValue? result;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showMeetingEditDialog(
                  context,
                  initialDate: DateTime(2026, 9, 22),
                  defaultTimezone: 'Europe/Zurich',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('meeting-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('meeting-form-error')), findsOneWidget);
      expect(find.text('Enter a title.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('meeting-title')), ' Sync ');
      await tester.tap(find.byKey(const Key('meeting-submit')));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.title, 'Sync');
      expect(result!.date, DateTime(2026, 9, 22));
      expect(result!.timezone, 'Europe/Zurich');
      expect(result!.startTime, isNull);
    });

    testWidgets('editing a meeting whose end precedes its start is refused', (
      tester,
    ) async {
      final bad = Meeting(
        id: 'm1',
        projectId: 'p1',
        title: 'Bad',
        date: DateTime(2026, 9, 22),
        startTime: const MeetingTime(11, 0),
        endTime: const MeetingTime(10, 0),
        timezone: 'UTC',
        version: 1,
        createdAt: DateTime(2026),
        modifiedAt: DateTime(2026),
      );
      await tester.pumpWidget(
        _app(
          MeetingEditDialog(
            initialDate: bad.date,
            defaultTimezone: 'UTC',
            initial: bad,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('meeting-submit')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'The end time must be after the start time, on the same day.',
        ),
        findsOneWidget,
      );
    });
  });

  group('MonthCalendar.gridDays', () {
    test('starts on the configured weekday and spans six weeks', () {
      // September 2026 starts on a Tuesday.
      final monday = MonthCalendar.gridDays(DateTime(2026, 9), 1);
      expect(monday.first, DateTime(2026, 8, 31));
      expect(monday, hasLength(42));
      final sunday = MonthCalendar.gridDays(DateTime(2026, 9), 0);
      expect(sunday.first, DateTime(2026, 8, 30));
    });
  });

  testWidgets('MonthCalendar shows counts and reports taps', (tester) async {
    DateTime? tapped;
    await tester.pumpWidget(
      _app(
        MonthCalendar(
          month: DateTime(2026, 9),
          selectedDay: DateTime(2026, 9, 22),
          today: DateTime(2026, 9, 22),
          countOn: (d) => d == DateTime(2026, 9, 10) ? 5 : 0,
          onSelect: (d) => tapped = d,
          onPrevious: () {},
          onNext: () {},
        ),
      ),
    );
    // More than three meetings show as a number, under the day number.
    expect(
      find.descendant(
        of: find.bySemanticsLabel(RegExp('5 meetings')),
        matching: find.text('5'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('15').first);
    expect(tapped, DateTime(2026, 9, 15));
  });

  group('transcript search', () {
    test('findTranscriptMatches is case-insensitive and non-overlapping', () {
      final lines = ['Alice: Budget review', 'Bob: the BUDGET, budget!', ''];
      final hits = findTranscriptMatches(lines, 'budget');
      expect(hits, const [
        TranscriptMatch(0, 7),
        TranscriptMatch(1, 9),
        TranscriptMatch(1, 17),
      ]);
      expect(findTranscriptMatches(lines, '  '), isEmpty);
      expect(findTranscriptMatches(['aaaa'], 'aa'), hasLength(2));
    });

    testWidgets('the view counts and steps through matches', (tester) async {
      await tester.pumpWidget(
        _app(
          const TranscriptView(
            text: 'Alice: budget first\nBob: no\nCarol: budget again',
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('transcript-search')),
        'budget',
      );
      await tester.pumpAndSettle();
      expect(find.text('1 of 2'), findsOneWidget);

      await tester.tap(find.byTooltip('Next match'));
      await tester.pumpAndSettle();
      expect(find.text('2 of 2'), findsOneWidget);

      await tester.tap(find.byTooltip('Next match'));
      await tester.pumpAndSettle();
      expect(find.text('1 of 2'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('transcript-search')),
        'zebra',
      );
      await tester.pumpAndSettle();
      expect(find.text('No matches'), findsOneWidget);
    });
  });
}
