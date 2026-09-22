import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/io/large_upload.dart';
import 'package:intellipilot/core/network/sse/project_events_service.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/meetings/data/dtos/meeting_dtos.dart';
import 'package:intellipilot/features/meetings/presentation/cubits/meeting_uploads_cubit.dart';
import 'package:intellipilot/features/meetings/presentation/cubits/meetings_calendar_cubit.dart';

import 'fake_meetings_repository.dart';

class _Events extends Fake implements ProjectEventsService {
  final controller = StreamController<LiveEvent>.broadcast();
  @override
  Stream<LiveEvent> watch(String projectId) => controller.stream;
}

const _file = PickedUpload(
  name: 'call.mp4',
  sizeBytes: 1000,
  handle: Object(),
);

void main() {
  group('MeetingsCalendarCubit', () {
    late FakeMeetingsRepository repo;

    setUp(() {
      repo = FakeMeetingsRepository()
        ..rows = [
          meetingRow('a', DateTime(2026, 9, 22)),
          meetingRow('b', DateTime(2026, 9, 22)),
          meetingRow('c', DateTime(2026, 9, 3)),
          meetingRow('d', DateTime(2026, 10, 1)),
        ];
    });

    MeetingsCalendarCubit build() => MeetingsCalendarCubit(
      repo: repo,
      projectId: 'p1',
      now: () => DateTime(2026, 9, 22, 15, 30),
    );

    test(
      'starts on today and loads the month plus a week either side',
      () async {
        final c = build();
        expect(c.state.selectedDay, DateTime(2026, 9, 22));
        expect(c.state.month, DateTime(2026, 9));
        await c.load();
        expect(repo.rangeCalls.single, (
          DateTime(2026, 8, 25),
          DateTime(2026, 10, 7),
        ));
        expect(c.state.loading, isFalse);
        expect(c.state.countOn(DateTime(2026, 9, 22)), 2);
        expect(c.state.selectedMeetings.map((m) => m.id), ['a', 'b']);
        // Adjacent-month days in the grid have their counts too.
        expect(c.state.countOn(DateTime(2026, 10, 1)), 1);
        await c.close();
      },
    );

    test('selecting a day in the month does not refetch', () async {
      final c = build();
      await c.load();
      await c.selectDay(DateTime(2026, 9, 3));
      expect(c.state.selectedMeetings.single.id, 'c');
      expect(repo.rangeCalls, hasLength(1));
      await c.close();
    });

    test('selecting a day of another month switches and loads it', () async {
      final c = build();
      await c.load();
      await c.selectDay(DateTime(2026, 10, 1));
      expect(c.state.month, DateTime(2026, 10));
      expect(repo.rangeCalls.last.$1, DateTime(2026, 9, 24));
      expect(c.state.selectedMeetings.single.id, 'd');
      await c.close();
    });

    test('shiftMonth keeps the day number, clamped to the month', () async {
      final c = MeetingsCalendarCubit(
        repo: repo,
        projectId: 'p1',
        initialDay: DateTime(2026, 1, 31),
      );
      await c.shiftMonth(1);
      expect(c.state.month, DateTime(2026, 2));
      expect(c.state.selectedDay, DateTime(2026, 2, 28));
      await c.shiftMonth(-2);
      expect(c.state.selectedDay, DateTime(2025, 12, 28));
      await c.close();
    });

    test('today() returns to the current day', () async {
      final c = build();
      await c.shiftMonth(3);
      await c.today();
      expect(c.state.selectedDay, DateTime(2026, 9, 22));
      expect(c.state.month, DateTime(2026, 9));
      await c.close();
    });

    test('a live meeting event reloads; other events do not', () async {
      final events = _Events();
      final c = MeetingsCalendarCubit(
        repo: repo,
        projectId: 'p1',
        events: events,
        now: () => DateTime(2026, 9, 22),
      );
      await c.load();
      events.controller.add(
        const LiveEvent.change({'event': 'issue.updated'}),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(repo.rangeCalls, hasLength(1));
      events.controller.add(
        const LiveEvent.change({'event': 'meeting.created', 'meeting_id': 'x'}),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(repo.rangeCalls, hasLength(2));
      await c.close();
    });
  });

  group('MeetingUploadsCubit', () {
    late FakeMeetingsRepository repo;
    var uploadedCalls = 0;

    setUp(() {
      repo = FakeMeetingsRepository();
      uploadedCalls = 0;
    });

    MeetingUploadsCubit build() => MeetingUploadsCubit(
      repo: repo,
      projectId: 'p1',
      meetingId: 'm1',
      onUploaded: () async => uploadedCalls++,
    );

    test('reports progress and drops the row on success', () async {
      final c = build();
      final done = c.upload(_file, ArtifactKind.recording);
      await Future<void>.delayed(Duration.zero);
      expect(c.state.single.status, UploadStatus.running);
      expect(c.state.single.fraction, 0);

      repo.lastProgress!(250, 1000);
      expect(c.state.single.sent, 250);
      expect(c.state.single.fraction, 0.25);

      repo.pendingUpload!.complete(Ok(attachment('a1')));
      await done;
      expect(c.state, isEmpty);
      expect(uploadedCalls, 1);
      await c.close();
    });

    test('cancel aborts and leaves a cancelled row until dismissed', () async {
      final c = build();
      final done = c.upload(_file, ArtifactKind.other);
      await Future<void>.delayed(Duration.zero);
      final id = c.state.single.id;

      c.cancel(id);
      await done;
      expect(repo.lastCancelToken!.isCancelled, isTrue);
      expect(c.state.single.status, UploadStatus.cancelled);
      expect(uploadedCalls, 0);

      c.dismiss(id);
      expect(c.state, isEmpty);
      await c.close();
    });

    test('a server rejection keeps the failure for display', () async {
      final c = build();
      final done = c.upload(_file, ArtifactKind.recording);
      await Future<void>.delayed(Duration.zero);
      repo.pendingUpload!.complete(
        const Err(ValidationFailure(fieldErrors: [])),
      );
      await done;
      expect(c.state.single.status, UploadStatus.failed);
      expect(c.state.single.failure, isA<ValidationFailure>());
      await c.close();
    });

    test('closing the cubit cancels running uploads', () async {
      final c = build();
      unawaited(c.upload(_file, ArtifactKind.recording));
      await Future<void>.delayed(Duration.zero);
      await c.close();
      expect(repo.lastCancelToken!.isCancelled, isTrue);
    });
  });
}
