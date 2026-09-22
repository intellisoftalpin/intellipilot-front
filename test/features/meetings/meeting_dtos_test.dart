import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/meetings/data/dtos/meeting_dtos.dart';
import 'package:intellipilot/features/meetings/data/meetings_repository_impl.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';

const _detail = <String, dynamic>{
  'id': 'm1',
  'project_id': 'p1',
  'title': 'Planning',
  'meeting_date': '2026-09-22',
  'start_time': '09:30',
  'end_time': '10:15:00',
  'timezone': 'Europe/Zurich',
  'location': 'https://meet.example/abc',
  'description': 'Agenda',
  'summary': '# Summary',
  'transcript': 'Alice: hi',
  'created_by': 'u1',
  'participant_ids': ['u1', 'u2'],
  'issue_ids': ['i1'],
  'epic_ids': <String>[],
  'customer_ids': ['c1'],
  'version': 3,
  'created_at': '2026-09-20T10:00:00Z',
  'modified_at': '2026-09-21T10:00:00Z',
  'artifacts': [
    {
      'id': 'a1',
      'project_id': 'p1',
      'target_type': 'meeting',
      'target_id': 'm1',
      'uploader_id': 'u1',
      'filename': 'call.mp4',
      'content_type': 'video/mp4',
      'size_bytes': 1048576,
      'sha256': 'x',
      'kind': 'recording',
      'created_at': '2026-09-21T10:00:00Z',
    },
    {
      'id': 'a2',
      'project_id': 'p1',
      'target_type': 'meeting',
      'target_id': 'm1',
      'filename': 'slides.pdf',
      'content_type': 'application/pdf',
      'size_bytes': 10,
      'sha256': 'y',
      'kind': 'mystery',
      'created_at': '2026-09-21T10:00:00Z',
    },
  ],
};

void main() {
  group('Meeting.fromJson', () {
    test('parses every field, times and artefacts', () {
      final m = Meeting.fromJson(_detail);
      expect(m.date, DateTime(2026, 9, 22));
      expect(m.startTime, const MeetingTime(9, 30));
      expect(m.endTime, const MeetingTime(10, 15));
      expect(m.timezone, 'Europe/Zurich');
      expect(m.participantIds, ['u1', 'u2']);
      expect(m.idsOf(MeetingLinkKind.customers), ['c1']);
      expect(m.etag, '"m1:3"');
      expect(m.artifactsOf(ArtifactKind.recording).single.filename, 'call.mp4');
      // An unknown kind reads as "other" rather than failing.
      expect(m.artifactsOf(ArtifactKind.other).single.id, 'a2');
    });

    test('missing optional fields default sensibly', () {
      final m = Meeting.fromJson({
        'id': 'm1',
        'project_id': 'p1',
        'title': 'T',
        'meeting_date': '2026-01-05',
        'start_time': null,
        'end_time': null,
        'created_at': '2026-01-01T00:00:00Z',
        'modified_at': '2026-01-01T00:00:00Z',
      });
      expect(m.startTime, isNull);
      expect(m.timezone, 'UTC');
      expect(m.artifacts, isEmpty);
      expect(m.summary, isEmpty);
    });
  });

  test('MeetingRange.fromJson parses rows and day counts', () {
    final r = MeetingRange.fromJson({
      'meetings': [
        {
          'id': 'm1',
          'project_id': 'p1',
          'title': 'Daily',
          'meeting_date': '2026-09-22',
          'start_time': null,
          'end_time': null,
          'timezone': 'UTC',
          'location': '',
          'has_summary': true,
          'has_transcript': false,
          'recording_count': 2,
          'file_count': 1,
          'participant_ids': ['u1'],
        },
      ],
      'days': [
        {'date': '2026-09-22', 'count': 1},
      ],
    });
    final row = r.meetings.single;
    expect(row.hasSummary, isTrue);
    expect(row.recordingCount, 2);
    expect(row.startTime, isNull);
    expect(r.days.single.date, DateTime(2026, 9, 22));
    expect(r.days.single.count, 1);
  });

  group('requests', () {
    test('create sends the date, times and only filled optionals', () {
      final json = CreateMeetingRequest(
        title: 'Review',
        date: DateTime(2026, 3, 4),
        startTime: const MeetingTime(9, 5),
        endTime: const MeetingTime(10, 0),
        timezone: 'UTC',
      ).toJson();
      expect(json, {
        'title': 'Review',
        'meeting_date': '2026-03-04',
        'start_time': '09:05',
        'end_time': '10:00',
        'timezone': 'UTC',
      });
    });

    test('create drops an end time without a start time', () {
      final json = CreateMeetingRequest(
        title: 'x',
        date: DateTime(2026, 3, 4),
        endTime: const MeetingTime(10, 0),
      ).toJson();
      expect(json.containsKey('end_time'), isFalse);
    });

    test('update with setTimes clears times explicitly', () {
      final json = const UpdateMeetingRequest(setTimes: true).toJson();
      expect(json, {'start_time': null, 'end_time': null});
    });

    test('update without setTimes leaves times alone', () {
      final json = const UpdateMeetingRequest(summary: 's').toJson();
      expect(json, {'summary': 's'});
    });
  });

  group('MeetingTime.tryParse', () {
    test('accepts HH:MM and HH:MM:SS', () {
      expect(MeetingTime.tryParse('07:45'), const MeetingTime(7, 45));
      expect(MeetingTime.tryParse('23:59:00'), const MeetingTime(23, 59));
    });
    test('rejects junk', () {
      expect(MeetingTime.tryParse('24:00'), isNull);
      expect(MeetingTime.tryParse('9'), isNull);
      expect(MeetingTime.tryParse(null), isNull);
    });
  });

  group('failureFromResponse', () {
    test('422 keeps the problem code', () {
      final f = failureFromResponse(
        422,
        '{"type":"https://intellipilot.dev/problems/not_media",'
        '"title":"Not media","status":422,"code":"not_media"}',
      );
      expect(f, isA<ValidationFailure>());
      expect(f.problem?.code, 'not_media');
    });

    test('non-JSON bodies fall back by status', () {
      expect(failureFromResponse(413, '<html>'), isA<UnknownFailure>());
      expect(failureFromResponse(413, '<html>').problem?.status, 413);
      expect(failureFromResponse(412, ''), isA<ConflictFailure>());
      expect(failureFromResponse(503, ''), isA<ServerFailure>());
    });
  });

  test('stakeholder baseline leaves out meeting.view; developers get it', () {
    expect(RolePresets.reader(), isNot(contains(Permission.meetingView)));
    expect(RolePresets.reader(), contains(Permission.wikiView));
    expect(RolePresets.contributor(), contains(Permission.meetingModify));
    expect(
      RolePresets.contributor(),
      isNot(contains(Permission.meetingDelete)),
    );
    expect(RolePresets.maintainer(), contains(Permission.meetingDelete));
    expect(Permission.fromWire('meeting.view'), Permission.meetingView);
  });
}
