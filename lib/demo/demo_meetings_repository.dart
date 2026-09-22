import 'package:dio/dio.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/io/file_picker.dart';
import 'package:intellipilot/core/io/large_upload.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/meetings/data/dtos/meeting_dtos.dart';
import 'package:intellipilot/features/meetings/domain/meetings_repository.dart';

/// In-memory meetings for demo mode: create, edit, link and delete work;
/// files do not (there is no server to hold them).
class DemoMeetingsRepository implements MeetingsRepository {
  final Map<String, Meeting> _meetings = {};
  var _seq = 0;

  Meeting? _find(String projectId, String id) {
    final m = _meetings[id];
    return m != null && m.projectId == projectId ? m : null;
  }

  MeetingListItem _item(Meeting m) => MeetingListItem(
    id: m.id,
    projectId: m.projectId,
    title: m.title,
    date: m.date,
    startTime: m.startTime,
    endTime: m.endTime,
    timezone: m.timezone,
    location: m.location,
    hasSummary: m.summary.isNotEmpty,
    hasTranscript: m.transcript.isNotEmpty,
    participantIds: m.participantIds,
  );

  Meeting _copy(
    Meeting m, {
    String? title,
    DateTime? date,
    bool setTimes = false,
    MeetingTime? startTime,
    MeetingTime? endTime,
    String? timezone,
    String? location,
    String? description,
    String? summary,
    String? transcript,
    List<String>? participantIds,
    List<String>? issueIds,
    List<String>? epicIds,
    List<String>? customerIds,
  }) => Meeting(
    id: m.id,
    projectId: m.projectId,
    title: title ?? m.title,
    date: date ?? m.date,
    startTime: setTimes ? startTime : m.startTime,
    endTime: setTimes ? endTime : m.endTime,
    timezone: timezone ?? m.timezone,
    location: location ?? m.location,
    description: description ?? m.description,
    summary: summary ?? m.summary,
    transcript: transcript ?? m.transcript,
    createdBy: m.createdBy,
    participantIds: participantIds ?? m.participantIds,
    issueIds: issueIds ?? m.issueIds,
    epicIds: epicIds ?? m.epicIds,
    customerIds: customerIds ?? m.customerIds,
    version: m.version + 1,
    createdAt: m.createdAt,
    modifiedAt: DateTime.now(),
  );

  @override
  Future<Result<MeetingRange, AppFailure>> listRange(
    String projectId, {
    required DateTime from,
    required DateTime to,
  }) async {
    final list =
        _meetings.values
            .where(
              (m) =>
                  m.projectId == projectId &&
                  !m.date.isBefore(from) &&
                  !m.date.isAfter(to),
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    final counts = <DateTime, int>{};
    for (final m in list) {
      counts[m.date] = (counts[m.date] ?? 0) + 1;
    }
    return Ok(
      MeetingRange(
        meetings: list.map(_item).toList(),
        days: [
          for (final e in counts.entries)
            MeetingDayCount(date: e.key, count: e.value),
        ],
      ),
    );
  }

  @override
  Future<Result<Meeting, AppFailure>> get(
    String projectId,
    String meetingId,
  ) async {
    final m = _find(projectId, meetingId);
    return m == null ? const Err(NotFoundFailure()) : Ok(m);
  }

  @override
  Future<Result<Meeting, AppFailure>> create(
    String projectId,
    CreateMeetingRequest body,
  ) async {
    final now = DateTime.now();
    final m = Meeting(
      id: 'demo-meeting-${++_seq}',
      projectId: projectId,
      title: body.title,
      date: body.date,
      startTime: body.startTime,
      endTime: body.startTime == null ? null : body.endTime,
      timezone: body.timezone ?? 'UTC',
      location: body.location,
      description: body.description,
      version: 1,
      createdAt: now,
      modifiedAt: now,
    );
    _meetings[m.id] = m;
    return Ok(m);
  }

  @override
  Future<Result<Meeting, AppFailure>> update(
    String projectId,
    String meetingId, {
    required UpdateMeetingRequest body,
    required String etag,
  }) async {
    final m = _find(projectId, meetingId);
    if (m == null) return const Err(NotFoundFailure());
    if (m.etag != etag) return const Err(ConflictFailure());
    final next = _copy(
      m,
      title: body.title,
      date: body.date,
      setTimes: body.setTimes,
      startTime: body.startTime,
      endTime: body.endTime,
      timezone: body.timezone,
      location: body.location,
      description: body.description,
      summary: body.summary,
      transcript: body.transcript,
    );
    _meetings[m.id] = next;
    return Ok(next);
  }

  @override
  Future<Result<Unit, AppFailure>> delete(
    String projectId,
    String meetingId,
  ) async {
    _meetings.remove(meetingId);
    return const Ok(Unit.instance);
  }

  Future<Result<Meeting, AppFailure>> _relink(
    String projectId,
    String meetingId,
    MeetingLinkKind kind,
    List<String> Function(List<String>) change,
  ) async {
    final m = _find(projectId, meetingId);
    if (m == null) return const Err(NotFoundFailure());
    final ids = change(m.idsOf(kind));
    final next = _copy(
      m,
      participantIds: kind == MeetingLinkKind.participants ? ids : null,
      issueIds: kind == MeetingLinkKind.issues ? ids : null,
      epicIds: kind == MeetingLinkKind.epics ? ids : null,
      customerIds: kind == MeetingLinkKind.customers ? ids : null,
    );
    _meetings[m.id] = next;
    return Ok(next);
  }

  @override
  Future<Result<Meeting, AppFailure>> link(
    String projectId,
    String meetingId,
    MeetingLinkKind kind,
    String targetId,
  ) => _relink(
    projectId,
    meetingId,
    kind,
    (ids) => ids.contains(targetId) ? ids : [...ids, targetId],
  );

  @override
  Future<Result<Meeting, AppFailure>> unlink(
    String projectId,
    String meetingId,
    MeetingLinkKind kind,
    String targetId,
  ) => _relink(
    projectId,
    meetingId,
    kind,
    (ids) => ids.where((i) => i != targetId).toList(),
  );

  @override
  bool get supportsLargeUploads => false;

  @override
  Future<PickedUpload?> pickUpload({String? accept}) async => null;

  @override
  Future<Result<Attachment, AppFailure>> uploadArtifact(
    String projectId,
    String meetingId, {
    required PickedUpload file,
    required ArtifactKind kind,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async => const Err(ForbiddenFailure());

  @override
  Future<Result<Unit, AppFailure>> deleteArtifact(
    String projectId,
    String meetingId,
    String attachmentId,
  ) async => const Ok(Unit.instance);

  @override
  Future<Result<Meeting, AppFailure>> importText(
    String projectId,
    String meetingId, {
    required MeetingTextTarget target,
    required PickedFile file,
  }) async {
    final m = _find(projectId, meetingId);
    if (m == null) return const Err(NotFoundFailure());
    final text = String.fromCharCodes(file.bytes);
    final next = _copy(
      m,
      summary: target == MeetingTextTarget.summary ? text : null,
      transcript: target == MeetingTextTarget.transcript ? text : null,
    );
    _meetings[m.id] = next;
    return Ok(next);
  }

  @override
  Future<Result<SignedDownload, AppFailure>> signUrl(
    String projectId,
    String attachmentId,
  ) async => const Err(NotFoundFailure());

  @override
  Future<Result<List<MeetingListItem>, AppFailure>> forIssue(
    String projectId,
    String issueId,
  ) async => Ok(
    _meetings.values
        .where((m) => m.projectId == projectId && m.issueIds.contains(issueId))
        .map(_item)
        .toList(),
  );

  @override
  Future<Result<List<MeetingListItem>, AppFailure>> forEpic(
    String projectId,
    String epicId,
  ) async => Ok(
    _meetings.values
        .where((m) => m.projectId == projectId && m.epicIds.contains(epicId))
        .map(_item)
        .toList(),
  );
}
