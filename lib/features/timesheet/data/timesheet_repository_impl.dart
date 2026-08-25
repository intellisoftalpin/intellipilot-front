import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/error/failure_mapper.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/timesheet/data/dtos/timesheet_dtos.dart';
import 'package:intellipilot/features/timesheet/domain/timesheet_repository.dart';

class TimesheetRepositoryImpl implements TimesheetRepository {
  TimesheetRepositoryImpl(this._api);
  final ApiClient _api;

  List<TimeEntry> _entries(dynamic data) =>
      ((data as Map<String, dynamic>)['entries'] as List<dynamic>? ?? const [])
          .map((e) => TimeEntry.fromJson(e as Map<String, dynamic>))
          .toList();

  // --- personal -------------------------------------------------------

  @override
  Future<Result<List<AssignedTask>, AppFailure>> listAssignedIssues() async {
    final res = await _api.get('/api/v1/me/assigned-issues');
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final list = (body['issues'] as List<dynamic>? ?? const [])
            .map((e) => AssignedTask.fromJson(e as Map<String, dynamic>))
            .toList();
        return Ok(list);
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<List<AssignedTask>, AppFailure>> searchLoggableIssues(
    String? query, {
    String? projectId,
  }) async {
    final res = await _api.get(
      '/api/v1/me/loggable-issues',
      query: {
        'search': ?query,
        'project_id': ?projectId,
      },
    );
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final list = (body['issues'] as List<dynamic>? ?? const [])
            .map((e) => AssignedTask.fromJson(e as Map<String, dynamic>))
            .toList();
        return Ok(list);
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<List<TimeEntry>, AppFailure>> listMyEntries({
    required String from,
    required String to,
    String? projectId,
    String? issueId,
  }) async {
    final res = await _api.get(
      '/api/v1/me/time-entries',
      query: {
        'from': from,
        'to': to,
        'project_id': ?projectId,
        'issue_id': ?issueId,
      },
    );
    return res.when(ok: (r) => Ok(_entries(r.data)), err: Err.new);
  }

  @override
  Future<Result<TimeEntry, AppFailure>> logTime({
    required String date,
    required int minutes,
    EntryKind kind = EntryKind.work,
    String? issueId,
    String? projectId,
    String? meetingType,
    String? note,
  }) async {
    final res = await _api.post(
      '/api/v1/me/time-entries',
      body: {
        'kind': kind.wire,
        'issue_id': ?issueId,
        'project_id': ?projectId,
        'meeting_type': ?meetingType,
        'date': date,
        'minutes': minutes,
        'note': ?note,
      },
    );
    return res.when(
      ok: (r) => Ok(TimeEntry.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<TimeEntry, AppFailure>> updateEntry({
    required String id,
    required int minutes,
    required int version,
    String? note,
    String? date,
  }) =>
      _patchEntry('/api/v1/me/time-entries/$id', minutes, version, note, date);

  @override
  Future<Result<Unit, AppFailure>> deleteEntry(String id) =>
      _delete('/api/v1/me/time-entries/$id');

  @override
  Future<Result<Unit, AppFailure>> bookAbsence({
    required EntryKind kind,
    required String startDate,
    required String endDate,
    int? minutesPerDay,
    String? note,
    bool skipWeekends = true,
  }) async {
    final res = await _api.post(
      '/api/v1/me/absences',
      body: {
        'kind': kind.wire,
        'start_date': startDate,
        'end_date': endDate,
        'minutes_per_day': ?minutesPerDay,
        'note': ?note,
        'skip_weekends': skipWeekends,
      },
    );
    return res.when(
      ok: (_) => const Ok<Unit, AppFailure>(Unit.instance),
      err: Err.new,
    );
  }

  @override
  Future<Result<Unit, AppFailure>> deleteBooking(String bookingId) =>
      _delete('/api/v1/me/absences/$bookingId');

  @override
  Future<Result<TimesheetSummary, AppFailure>> mySummary({
    required int year,
    required int month,
  }) async {
    final res = await _api.get(
      '/api/v1/me/timesheet/summary',
      query: {'year': year, 'month': month},
    );
    return res.when(
      ok: (r) => Ok(TimesheetSummary.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<VacationBalance, AppFailure>> myBalance() async {
    final res = await _api.get('/api/v1/me/vacation-balance');
    return res.when(
      ok: (r) => Ok(VacationBalance.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<Uint8List, AppFailure>> exportMy({
    required String from,
    required String to,
    required ExportFormat format,
  }) => _downloadBytes('/api/v1/me/time-entries/export', {
    'from': from,
    'to': to,
    'format': format.name,
  });

  // --- project / team -------------------------------------------------

  @override
  Future<Result<List<TimeEntry>, AppFailure>> listProjectEntries(
    String projectId, {
    required String from,
    required String to,
    String? userId,
  }) async {
    final res = await _api.get(
      '/api/v1/projects/$projectId/time-entries',
      query: {
        'from': from,
        'to': to,
        'user_id': ?userId,
      },
    );
    return res.when(ok: (r) => Ok(_entries(r.data)), err: Err.new);
  }

  @override
  Future<Result<TeamMonth, AppFailure>> teamMonth(
    String projectId, {
    required int year,
    required int month,
  }) async {
    final res = await _api.get(
      '/api/v1/projects/$projectId/time/summary',
      query: {'year': year, 'month': month},
    );
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        return Ok(
          TeamMonth(
            members: (body['members'] as List<dynamic>? ?? const [])
                .map((e) => TeamMemberMonth.fromJson(e as Map<String, dynamic>))
                .toList(),
            // Absent for callers who may not know; never coerce to 0.
            excludedMembers: (body['excluded_members'] as num?)?.toInt(),
          ),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<TimeEntry, AppFailure>> adminLogTime(
    String projectId, {
    required String userId,
    required String date,
    required int minutes,
    String? issueId,
    String? note,
  }) async {
    final res = await _api.post(
      '/api/v1/projects/$projectId/time-entries',
      body: {
        'user_id': userId,
        'issue_id': ?issueId,
        'date': date,
        'minutes': minutes,
        'note': ?note,
      },
    );
    return res.when(
      ok: (r) => Ok(TimeEntry.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<TimeEntry, AppFailure>> correctEntry(
    String projectId, {
    required String entryId,
    required int minutes,
    required int version,
    String? note,
    String? date,
  }) => _patchEntry(
    '/api/v1/projects/$projectId/time-entries/$entryId',
    minutes,
    version,
    note,
    date,
  );

  @override
  Future<Result<Unit, AppFailure>> adminDeleteEntry(
    String projectId,
    String entryId,
  ) => _delete('/api/v1/projects/$projectId/time-entries/$entryId');

  @override
  Future<Result<List<PeriodLock>, AppFailure>> listLocks(
    String projectId,
  ) async {
    final res = await _api.get('/api/v1/projects/$projectId/time/locks');
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final list = (body['locks'] as List<dynamic>? ?? const [])
            .map((e) => PeriodLock.fromJson(e as Map<String, dynamic>))
            .toList();
        return Ok(list);
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<Unit, AppFailure>> lockPeriod(
    String projectId, {
    required int year,
    required int month,
  }) async {
    final res = await _api.post(
      '/api/v1/projects/$projectId/time/locks',
      body: {'year': year, 'month': month},
    );
    return res.when(
      ok: (_) => const Ok<Unit, AppFailure>(Unit.instance),
      err: Err.new,
    );
  }

  @override
  Future<Result<Unit, AppFailure>> unlockPeriod(
    String projectId, {
    required int year,
    required int month,
  }) => _delete('/api/v1/projects/$projectId/time/locks/$year/$month');

  @override
  Future<Result<List<Availability>, AppFailure>> availability(
    String projectId, {
    String? date,
  }) async {
    final res = await _api.get(
      '/api/v1/projects/$projectId/availability',
      query: {'date': ?date},
    );
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final list = (body['unavailable'] as List<dynamic>? ?? const [])
            .map((e) => Availability.fromJson(e as Map<String, dynamic>))
            .toList();
        return Ok(list);
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<IssueTimeSummary, AppFailure>> issueTime(
    String projectId,
    String issueId,
  ) async {
    final res = await _api.get(
      '/api/v1/projects/$projectId/issues/$issueId/time',
    );
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        return Ok(
          IssueTimeSummary(
            entries: _entries(body),
            totalMinutes: (body['total_minutes'] as num?)?.toInt() ?? 0,
            myMinutes: (body['my_minutes'] as num?)?.toInt() ?? 0,
            canSeeAll: body['can_see_all'] as bool? ?? false,
          ),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<Uint8List, AppFailure>> exportProject(
    String projectId, {
    required String from,
    required String to,
    required ExportFormat format,
    String? userId,
  }) => _downloadBytes('/api/v1/projects/$projectId/time-entries/export', {
    'from': from,
    'to': to,
    'format': format.name,
    'user_id': ?userId,
  });

  // --- superadmin -----------------------------------------------------

  @override
  Future<Result<TeamMonth, AppFailure>> adminGlobalMonth({
    required int year,
    required int month,
  }) async {
    final res = await _api.get(
      '/api/v1/admin/time/summary',
      query: {'year': year, 'month': month},
    );
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        return Ok(
          TeamMonth(
            members: (body['members'] as List<dynamic>? ?? const [])
                .map((e) => TeamMemberMonth.fromJson(e as Map<String, dynamic>))
                .toList(),
            // Absent for callers who may not know; never coerce to 0.
            excludedMembers: (body['excluded_members'] as num?)?.toInt(),
          ),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<List<VacationAllowance>, AppFailure>> listAllowances(
    String userId,
  ) async {
    final res = await _api.get(
      '/api/v1/admin/users/$userId/vacation-allowances',
    );
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final list = (body['allowances'] as List<dynamic>? ?? const [])
            .map((e) => VacationAllowance.fromJson(e as Map<String, dynamic>))
            .toList();
        return Ok(list);
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<Unit, AppFailure>> setAllowance(
    String userId, {
    required int year,
    required double allowanceDays,
    required double carriedOverDays,
    String? note,
  }) async {
    try {
      await _api.dio.put<dynamic>(
        '/api/v1/admin/users/$userId/vacation-allowances/$year',
        data: {
          'allowance_days': allowanceDays,
          'carried_over_days': carriedOverDays,
          'note': ?note,
        },
      );
      return const Ok<Unit, AppFailure>(Unit.instance);
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> setWorkSettings(
    String userId, {
    required int workMinutesPerDay,
  }) async {
    try {
      await _api.dio.patch<dynamic>(
        '/api/v1/admin/users/$userId/work-settings',
        data: {'work_minutes_per_day': workMinutesPerDay},
      );
      return const Ok<Unit, AppFailure>(Unit.instance);
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  // --- shared helpers -------------------------------------------------

  Future<Result<TimeEntry, AppFailure>> _patchEntry(
    String path,
    int minutes,
    int version,
    String? note,
    String? date,
  ) async {
    try {
      final r = await _api.dio.patch<dynamic>(
        path,
        data: {
          'minutes': minutes,
          'version': version,
          'note': ?note,
          'date': ?date,
        },
      );
      return Ok(TimeEntry.fromJson(r.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  Future<Result<Unit, AppFailure>> _delete(String path) async {
    try {
      await _api.dio.delete<dynamic>(path);
      return const Ok<Unit, AppFailure>(Unit.instance);
    } on DioException catch (e) {
      if (e.response?.statusCode == 204) {
        return const Ok<Unit, AppFailure>(Unit.instance);
      }
      return Err(mapDioExceptionToFailure(e));
    }
  }

  Future<Result<Uint8List, AppFailure>> _downloadBytes(
    String path,
    Map<String, dynamic> query,
  ) async {
    try {
      final r = await _api.dio.get<List<int>>(
        path,
        queryParameters: query,
        options: Options(responseType: ResponseType.bytes),
      );
      return Ok(Uint8List.fromList(r.data ?? const []));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }
}
