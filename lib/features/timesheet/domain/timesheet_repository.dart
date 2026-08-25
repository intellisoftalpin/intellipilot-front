import 'dart:typed_data';

import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/timesheet/data/dtos/timesheet_dtos.dart';

/// Worked time logged against a single task (task-detail view).
class IssueTimeSummary {
  const IssueTimeSummary({
    required this.entries,
    required this.totalMinutes,
    required this.myMinutes,
    required this.canSeeAll,
  });
  final List<TimeEntry> entries;
  final int totalMinutes;
  final int myMinutes;
  final bool canSeeAll;
}

/// Export file format selectable by the user.
enum ExportFormat { csv, xlsx }

abstract interface class TimesheetRepository {
  // --- personal -------------------------------------------------------
  Future<Result<List<AssignedTask>, AppFailure>> listAssignedIssues();

  /// Search any loggable task across the caller's projects (not just the ones
  /// assigned to them). Backed by `/me/loggable-issues`.
  Future<Result<List<AssignedTask>, AppFailure>> searchLoggableIssues(
    String? query, {
    String? projectId,
  });

  Future<Result<List<TimeEntry>, AppFailure>> listMyEntries({
    required String from,
    required String to,
    String? projectId,
    String? issueId,
  });

  /// Log worked time for the caller. Either an [issueId] or a [projectId]
  /// (or both) must be supplied for `work`; `meeting` may carry an optional
  /// [projectId] and [meetingType].
  Future<Result<TimeEntry, AppFailure>> logTime({
    required String date,
    required int minutes,
    EntryKind kind = EntryKind.work,
    String? issueId,
    String? projectId,
    String? meetingType,
    String? note,
  });

  Future<Result<TimeEntry, AppFailure>> updateEntry({
    required String id,
    required int minutes,
    required int version,
    String? note,
    String? date,
  });

  Future<Result<Unit, AppFailure>> deleteEntry(String id);

  Future<Result<Unit, AppFailure>> bookAbsence({
    required EntryKind kind,
    required String startDate,
    required String endDate,
    int? minutesPerDay,
    String? note,
    bool skipWeekends,
  });

  Future<Result<Unit, AppFailure>> deleteBooking(String bookingId);

  Future<Result<TimesheetSummary, AppFailure>> mySummary({
    required int year,
    required int month,
  });

  Future<Result<VacationBalance, AppFailure>> myBalance();

  Future<Result<Uint8List, AppFailure>> exportMy({
    required String from,
    required String to,
    required ExportFormat format,
  });

  // --- project / team -------------------------------------------------
  Future<Result<List<TimeEntry>, AppFailure>> listProjectEntries(
    String projectId, {
    required String from,
    required String to,
    String? userId,
  });

  Future<Result<TeamMonth, AppFailure>> teamMonth(
    String projectId, {
    required int year,
    required int month,
  });

  /// Log worked time on behalf of another project member (needs `time.manage`
  /// in that project). Backed by `/projects/{id}/time-entries`.
  Future<Result<TimeEntry, AppFailure>> adminLogTime(
    String projectId, {
    required String userId,
    required String date,
    required int minutes,
    String? issueId,
    String? note,
  });

  Future<Result<TimeEntry, AppFailure>> correctEntry(
    String projectId, {
    required String entryId,
    required int minutes,
    required int version,
    String? note,
    String? date,
  });

  /// Delete another project member's entry (needs `time.manage` in that
  /// project; bypasses period locks). Backed by
  /// `/projects/{id}/time-entries/{entryId}`.
  Future<Result<Unit, AppFailure>> adminDeleteEntry(
    String projectId,
    String entryId,
  );

  Future<Result<List<PeriodLock>, AppFailure>> listLocks(String projectId);

  Future<Result<Unit, AppFailure>> lockPeriod(
    String projectId, {
    required int year,
    required int month,
  });

  Future<Result<Unit, AppFailure>> unlockPeriod(
    String projectId, {
    required int year,
    required int month,
  });

  Future<Result<List<Availability>, AppFailure>> availability(
    String projectId, {
    String? date,
  });

  Future<Result<IssueTimeSummary, AppFailure>> issueTime(
    String projectId,
    String issueId,
  );

  Future<Result<Uint8List, AppFailure>> exportProject(
    String projectId, {
    required String from,
    required String to,
    required ExportFormat format,
    String? userId,
  });

  // --- superadmin -----------------------------------------------------

  /// Cross-project month grid for every user (superadmin only). Backed by
  /// `/admin/time/summary`.
  Future<Result<TeamMonth, AppFailure>> adminGlobalMonth({
    required int year,
    required int month,
  });

  Future<Result<List<VacationAllowance>, AppFailure>> listAllowances(
    String userId,
  );

  Future<Result<Unit, AppFailure>> setAllowance(
    String userId, {
    required int year,
    required double allowanceDays,
    required double carriedOverDays,
    String? note,
  });

  Future<Result<Unit, AppFailure>> setWorkSettings(
    String userId, {
    required int workMinutesPerDay,
  });
}
