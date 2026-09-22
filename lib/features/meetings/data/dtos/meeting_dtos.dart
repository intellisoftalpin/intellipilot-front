import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';

/// What a meeting file is to its meeting (`attachments.kind`).
enum ArtifactKind {
  recording('recording'),
  transcript('transcript'),
  summary('summary'),
  other('other');

  const ArtifactKind(this.wire);
  final String wire;

  /// Unknown or missing values read as [other] — a newer server may add kinds.
  static ArtifactKind fromWire(String? wire) {
    for (final k in values) {
      if (k.wire == wire) return k;
    }
    return other;
  }
}

/// The link sets a meeting carries; [wire] is the path segment of the
/// `/links/{kind}/{target_id}` endpoints.
enum MeetingLinkKind {
  participants('participants'),
  issues('issues'),
  epics('epics'),
  customers('customers');

  const MeetingLinkKind(this.wire);
  final String wire;
}

/// A calendar day with no time of day. Meetings are kept on the date they
/// were entered — never shifted through a time zone — so the client only ever
/// deals in plain `YYYY-MM-DD` values.
DateTime parseMeetingDate(String iso) {
  final parts = iso.split('-');
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

String formatMeetingDate(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// A local wall-clock time, `HH:MM`, in the meeting's own time zone.
class MeetingTime implements Comparable<MeetingTime> {
  const MeetingTime(this.hour, this.minute);

  /// Accepts `HH:MM` and `HH:MM:SS`. Returns null for anything else.
  static MeetingTime? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }
    return MeetingTime(h, m);
  }

  final int hour;
  final int minute;

  int get minutesOfDay => hour * 60 + minute;

  String get wire =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  int compareTo(MeetingTime other) =>
      minutesOfDay.compareTo(other.minutesOfDay);

  @override
  bool operator ==(Object other) =>
      other is MeetingTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => wire;
}

List<String> _ids(Object? raw) =>
    (raw as List<dynamic>? ?? const []).map((e) => e as String).toList();

/// One row of the calendar: the meeting without its long texts.
class MeetingListItem {
  const MeetingListItem({
    required this.id,
    required this.projectId,
    required this.title,
    required this.date,
    required this.timezone,
    this.startTime,
    this.endTime,
    this.location = '',
    this.hasSummary = false,
    this.hasTranscript = false,
    this.recordingCount = 0,
    this.fileCount = 0,
    this.participantIds = const [],
  });

  factory MeetingListItem.fromJson(Map<String, dynamic> json) =>
      MeetingListItem(
        id: json['id'] as String,
        projectId: json['project_id'] as String,
        title: json['title'] as String? ?? '',
        date: parseMeetingDate(json['meeting_date'] as String),
        startTime: MeetingTime.tryParse(json['start_time'] as String?),
        endTime: MeetingTime.tryParse(json['end_time'] as String?),
        timezone: json['timezone'] as String? ?? 'UTC',
        location: json['location'] as String? ?? '',
        hasSummary: json['has_summary'] as bool? ?? false,
        hasTranscript: json['has_transcript'] as bool? ?? false,
        recordingCount: (json['recording_count'] as num?)?.toInt() ?? 0,
        fileCount: (json['file_count'] as num?)?.toInt() ?? 0,
        participantIds: _ids(json['participant_ids']),
      );

  final String id;
  final String projectId;
  final String title;

  /// The calendar day, at local midnight (only y/m/d are meaningful).
  final DateTime date;
  final MeetingTime? startTime;
  final MeetingTime? endTime;
  final String timezone;
  final String location;
  final bool hasSummary;
  final bool hasTranscript;
  final int recordingCount;
  final int fileCount;
  final List<String> participantIds;
}

/// Meetings on one calendar day, as counted by the server.
class MeetingDayCount {
  const MeetingDayCount({required this.date, required this.count});

  factory MeetingDayCount.fromJson(Map<String, dynamic> json) =>
      MeetingDayCount(
        date: parseMeetingDate(json['date'] as String),
        count: (json['count'] as num?)?.toInt() ?? 0,
      );

  final DateTime date;
  final int count;
}

/// `GET /meetings?from=&to=` — the meetings in range plus per-day counts.
class MeetingRange {
  const MeetingRange({required this.meetings, required this.days});

  factory MeetingRange.fromJson(Map<String, dynamic> json) => MeetingRange(
    meetings: (json['meetings'] as List<dynamic>? ?? const [])
        .map((e) => MeetingListItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    days: (json['days'] as List<dynamic>? ?? const [])
        .map((e) => MeetingDayCount.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  final List<MeetingListItem> meetings;
  final List<MeetingDayCount> days;
}

/// A meeting with its minutes, links and files.
class Meeting {
  const Meeting({
    required this.id,
    required this.projectId,
    required this.title,
    required this.date,
    required this.timezone,
    required this.version,
    required this.createdAt,
    required this.modifiedAt,
    this.startTime,
    this.endTime,
    this.location = '',
    this.description = '',
    this.summary = '',
    this.transcript = '',
    this.createdBy,
    this.participantIds = const [],
    this.issueIds = const [],
    this.epicIds = const [],
    this.customerIds = const [],
    this.artifacts = const [],
  });

  factory Meeting.fromJson(Map<String, dynamic> json) => Meeting(
    id: json['id'] as String,
    projectId: json['project_id'] as String,
    title: json['title'] as String? ?? '',
    date: parseMeetingDate(json['meeting_date'] as String),
    startTime: MeetingTime.tryParse(json['start_time'] as String?),
    endTime: MeetingTime.tryParse(json['end_time'] as String?),
    timezone: json['timezone'] as String? ?? 'UTC',
    location: json['location'] as String? ?? '',
    description: json['description'] as String? ?? '',
    summary: json['summary'] as String? ?? '',
    transcript: json['transcript'] as String? ?? '',
    createdBy: json['created_by'] as String?,
    participantIds: _ids(json['participant_ids']),
    issueIds: _ids(json['issue_ids']),
    epicIds: _ids(json['epic_ids']),
    customerIds: _ids(json['customer_ids']),
    version: (json['version'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.parse(json['created_at'] as String),
    modifiedAt: DateTime.parse(json['modified_at'] as String),
    artifacts: (json['artifacts'] as List<dynamic>? ?? const [])
        .map((e) => Attachment.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  final String id;
  final String projectId;
  final String title;
  final DateTime date;
  final MeetingTime? startTime;
  final MeetingTime? endTime;
  final String timezone;
  final String location;
  final String description;

  /// Markdown.
  final String summary;

  /// Plain text.
  final String transcript;
  final String? createdBy;
  final List<String> participantIds;
  final List<String> issueIds;
  final List<String> epicIds;
  final List<String> customerIds;
  final int version;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final List<Attachment> artifacts;

  /// The strong revision token the server expects in `If-Match`. Rebuilt from
  /// the body rather than read off the header — see `canonicalEtag`.
  String get etag => '"$id:$version"';

  List<Attachment> artifactsOf(ArtifactKind kind) =>
      artifacts.where((a) => ArtifactKind.fromWire(a.kind) == kind).toList();

  List<String> idsOf(MeetingLinkKind kind) => switch (kind) {
    MeetingLinkKind.participants => participantIds,
    MeetingLinkKind.issues => issueIds,
    MeetingLinkKind.epics => epicIds,
    MeetingLinkKind.customers => customerIds,
  };
}

/// `POST /meetings`.
class CreateMeetingRequest {
  const CreateMeetingRequest({
    required this.title,
    required this.date,
    this.startTime,
    this.endTime,
    this.timezone,
    this.location = '',
    this.description = '',
  });

  final String title;
  final DateTime date;
  final MeetingTime? startTime;
  final MeetingTime? endTime;
  final String? timezone;
  final String location;
  final String description;

  Map<String, dynamic> toJson() => {
    'title': title,
    'meeting_date': formatMeetingDate(date),
    if (startTime != null) 'start_time': startTime!.wire,
    if (startTime != null && endTime != null) 'end_time': endTime!.wire,
    if (timezone != null) 'timezone': timezone,
    if (location.isNotEmpty) 'location': location,
    if (description.isNotEmpty) 'description': description,
  };
}

/// `PATCH /meetings/{id}`. Only the set fields are sent. The details dialog
/// always sends both times, so clearing one is an explicit `null`.
class UpdateMeetingRequest {
  const UpdateMeetingRequest({
    this.title,
    this.date,
    this.setTimes = false,
    this.startTime,
    this.endTime,
    this.timezone,
    this.location,
    this.description,
    this.summary,
    this.transcript,
  });

  final String? title;
  final DateTime? date;

  /// When true, [startTime] / [endTime] are sent as given, `null` clearing.
  final bool setTimes;
  final MeetingTime? startTime;
  final MeetingTime? endTime;
  final String? timezone;
  final String? location;
  final String? description;
  final String? summary;
  final String? transcript;

  Map<String, dynamic> toJson() => {
    'title': ?title,
    if (date != null) 'meeting_date': formatMeetingDate(date!),
    if (setTimes) ...{
      'start_time': startTime?.wire,
      'end_time': startTime == null ? null : endTime?.wire,
    },
    'timezone': ?timezone,
    'location': ?location,
    'description': ?description,
    'summary': ?summary,
    'transcript': ?transcript,
  };
}
