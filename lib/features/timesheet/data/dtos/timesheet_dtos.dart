// DTOs for the time-tracking feature. Field names mirror the backend JSON
// (see `intellipilot_core::time_tracking`) so parsing is a direct mapping.

/// Category of a time entry. Wire strings match the backend exactly.
enum EntryKind {
  work('work'),
  vacation('vacation'),
  illness('illness'),
  dayOff('day_off'),
  holiday('holiday');

  const EntryKind(this.wire);
  final String wire;

  bool get isAbsence => this != EntryKind.work;

  static EntryKind fromWire(String w) => EntryKind.values.firstWhere(
    (e) => e.wire == w,
    orElse: () => EntryKind.work,
  );
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

  double get hours => minutes / 60.0;

  /// Best human label for the linked work item (or absence kind).
  String get label {
    if (kind.isAbsence) return kind.wire;
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
  });

  factory AssignedTask.fromJson(Map<String, dynamic> j) => AssignedTask(
    id: j['id'] as String,
    projectId: j['project_id'] as String,
    projectName: j['project_name'] as String? ?? '',
    reference: (j['reference'] as num).toInt(),
    subject: j['subject'] as String? ?? '',
  );

  final String id;
  final String projectId;
  final String projectName;
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
