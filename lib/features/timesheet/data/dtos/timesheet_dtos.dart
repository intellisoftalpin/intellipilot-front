// DTOs for the time-tracking feature. Field names mirror the backend JSON
// (see `intellipilot_core::time_tracking`) so parsing is a direct mapping.

/// Category of a time entry. Wire strings match the backend exactly.
enum EntryKind {
  work('work', isAbsence: false),
  meeting('meeting', isAbsence: false),
  vacation('vacation', isAbsence: true),
  illness('illness', isAbsence: true),
  dayOff('day_off', isAbsence: true),
  holiday('holiday', isAbsence: true);

  const EntryKind(this.wire, {required this.isAbsence});
  final String wire;

  /// True for the leave kinds (vacation / illness / …) — false for `work`
  /// and `meeting`, which log actual worked time.
  final bool isAbsence;

  static EntryKind fromWire(String w) => EntryKind.values.firstWhere(
    (e) => e.wire == w,
    orElse: () => EntryKind.work,
  );
}

/// The kind of a `meeting` time entry. Wire strings match the backend.
enum MeetingType {
  daily('daily'),
  planning('planning'),
  troubleshooting('troubleshooting'),
  retro('retro'),
  refinement('refinement'),
  other('other');

  const MeetingType(this.wire);
  final String wire;

  static MeetingType? fromWire(String? w) {
    if (w == null) return null;
    for (final m in MeetingType.values) {
      if (m.wire == w) return m;
    }
    return null;
  }
}

class TimeEntry {
  const TimeEntry({
    required this.id,
    required this.userId,
    required this.kind,
    required this.entryDate,
    required this.minutes,
    required this.note,
    required this.version,
    this.projectId,
    this.issueId,
    this.bookingId,
    this.issueRef,
    this.issueSubject,
    this.projectName,
    this.username,
    this.fullName,
    this.meetingType,
  });

  factory TimeEntry.fromJson(Map<String, dynamic> j) => TimeEntry(
    id: j['id'] as String,
    userId: j['user_id'] as String,
    kind: EntryKind.fromWire(j['kind'] as String? ?? 'work'),
    entryDate: j['entry_date'] as String,
    minutes: (j['minutes'] as num).toInt(),
    note: j['note'] as String? ?? '',
    version: (j['version'] as num?)?.toInt() ?? 1,
    projectId: j['project_id'] as String?,
    issueId: j['issue_id'] as String?,
    bookingId: j['booking_id'] as String?,
    issueRef: (j['issue_ref'] as num?)?.toInt(),
    issueSubject: j['issue_subject'] as String?,
    projectName: j['project_name'] as String?,
    username: j['username'] as String?,
    fullName: j['full_name'] as String?,
    meetingType: j['meeting_type'] as String?,
  );

  final String id;
  final String userId;
  final EntryKind kind;
  final String entryDate; // YYYY-MM-DD
  final int minutes;
  final String note;
  final int version;
  final String? projectId;
  final String? issueId;
  final String? bookingId;
  final int? issueRef;
  final String? issueSubject;
  final String? projectName;
  final String? username;
  final String? fullName;

  /// Only set for `meeting` entries (nullable). One of the [MeetingType] wire
  /// values.
  final String? meetingType;

  double get hours => minutes / 60.0;

  /// Best human label for the linked work item (or absence kind).
  String get label {
    if (kind.isAbsence) return kind.wire;
    if (kind == EntryKind.meeting) {
      return projectName != null ? 'meeting · $projectName' : 'meeting';
    }
    if (issueRef != null) {
      return '#$issueRef ${issueSubject ?? ''}'.trim();
    }
    return issueSubject ?? projectName ?? 'work';
  }
}

class TimesheetSummary {
  const TimesheetSummary({
    required this.year,
    required this.month,
    required this.workMinutesPerDay,
    required this.loggedMinutes,
    required this.requiredMinutes,
    required this.workingDays,
    required this.completeDays,
    required this.missingDays,
  });

  factory TimesheetSummary.fromJson(Map<String, dynamic> j) => TimesheetSummary(
    year: (j['year'] as num).toInt(),
    month: (j['month'] as num).toInt(),
    workMinutesPerDay: (j['work_minutes_per_day'] as num).toInt(),
    loggedMinutes: (j['logged_minutes'] as num).toInt(),
    requiredMinutes: (j['required_minutes'] as num).toInt(),
    workingDays: (j['working_days'] as num).toInt(),
    completeDays: (j['complete_days'] as num).toInt(),
    missingDays: (j['missing_days'] as List<dynamic>? ?? const [])
        .map((e) => e as String)
        .toList(),
  );

  final int year;
  final int month;
  final int workMinutesPerDay;
  final int loggedMinutes;
  final int requiredMinutes;
  final int workingDays;
  final int completeDays;
  final List<String> missingDays;

  bool get hasGaps => missingDays.isNotEmpty;
}

class VacationYear {
  const VacationYear({
    required this.year,
    required this.allowanceDays,
    required this.carriedOverDays,
    required this.usedDays,
    required this.remainingDays,
  });

  factory VacationYear.fromJson(Map<String, dynamic> j) => VacationYear(
    year: (j['year'] as num).toInt(),
    allowanceDays: (j['allowance_days'] as num).toDouble(),
    carriedOverDays: (j['carried_over_days'] as num).toDouble(),
    usedDays: (j['used_days'] as num).toDouble(),
    remainingDays: (j['remaining_days'] as num).toDouble(),
  );

  final int year;
  final double allowanceDays;
  final double carriedOverDays;
  final double usedDays;
  final double remainingDays;
}

class VacationBalance {
  const VacationBalance({required this.years});

  factory VacationBalance.fromJson(Map<String, dynamic> j) => VacationBalance(
    years: (j['years'] as List<dynamic>? ?? const [])
        .map((e) => VacationYear.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  final List<VacationYear> years;
}

class PeriodLock {
  const PeriodLock({required this.year, required this.month});

  factory PeriodLock.fromJson(Map<String, dynamic> j) => PeriodLock(
    year: (j['year'] as num).toInt(),
    month: (j['month'] as num).toInt(),
  );

  final int year;
  final int month;
}

class Availability {
  const Availability({
    required this.userId,
    required this.username,
    required this.fullName,
    required this.kind,
  });

  factory Availability.fromJson(Map<String, dynamic> j) => Availability(
    userId: j['user_id'] as String,
    username: j['username'] as String? ?? '',
    fullName: j['full_name'] as String? ?? '',
    kind: EntryKind.fromWire(j['kind'] as String? ?? 'vacation'),
  );

  final String userId;
  final String username;
  final String fullName;
  final EntryKind kind;

  String get displayName => fullName.isNotEmpty ? fullName : username;
}

/// One month of a team grid: the visible rows, plus how many members the
/// server withheld because they are excluded from timesheet reports.
///
/// [excludedMembers] is `null` when the caller is not entitled to know — the
/// API omits the field for non-superadmins rather than sending zero, so a
/// project manager cannot infer that a specific colleague is excluded.
class TeamMonth {
  const TeamMonth({required this.members, this.excludedMembers});

  final List<TeamMemberMonth> members;
  final int? excludedMembers;

  /// True when there is a non-zero, disclosed exclusion count to surface.
  bool get hasExclusions => (excludedMembers ?? 0) > 0;
}

class TeamMemberMonth {
  const TeamMemberMonth({
    required this.userId,
    required this.username,
    required this.fullName,
    required this.totalMinutes,
    required this.days,
  });

  factory TeamMemberMonth.fromJson(Map<String, dynamic> j) => TeamMemberMonth(
    userId: j['user_id'] as String,
    username: j['username'] as String? ?? '',
    fullName: j['full_name'] as String? ?? '',
    totalMinutes: (j['total_minutes'] as num).toInt(),
    days: {
      for (final d in (j['days'] as List<dynamic>? ?? const []))
        (d as Map<String, dynamic>)['date'] as String: (d['minutes'] as num)
            .toInt(),
    },
  );

  final String userId;
  final String username;
  final String fullName;
  final int totalMinutes;
  final Map<String, int> days; // date -> minutes

  String get displayName => fullName.isNotEmpty ? fullName : username;
}

class AssignedTask {
  const AssignedTask({
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.reference,
    required this.subject,
    this.projectSlug = '',
  });

  factory AssignedTask.fromJson(Map<String, dynamic> j) => AssignedTask(
    id: j['id'] as String,
    projectId: j['project_id'] as String,
    projectName: j['project_name'] as String? ?? '',
    projectSlug: j['project_slug'] as String? ?? '',
    reference: (j['reference'] as num).toInt(),
    subject: j['subject'] as String? ?? '',
  );

  final String id;
  final String projectId;
  final String projectName;
  final String projectSlug;
  final int reference;
  final String subject;

  String get label => '$projectName #$reference — $subject';
}

class VacationAllowance {
  const VacationAllowance({
    required this.year,
    required this.allowanceDays,
    required this.carriedOverDays,
    required this.note,
  });

  factory VacationAllowance.fromJson(Map<String, dynamic> j) =>
      VacationAllowance(
        year: (j['year'] as num).toInt(),
        allowanceDays: (j['allowance_days'] as num).toDouble(),
        carriedOverDays: (j['carried_over_days'] as num).toDouble(),
        note: j['note'] as String? ?? '',
      );

  final int year;
  final double allowanceDays;
  final double carriedOverDays;
  final String note;
}
