// Underscore-prefixed constructor fields read clearer than initializing
// formals here, matching the other cubits in this codebase.
// ignore_for_file: prefer_initializing_formals
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/timesheet/data/dtos/timesheet_dtos.dart';
import 'package:intellipilot/features/timesheet/domain/timesheet_repository.dart';

sealed class TimesheetState extends Equatable {
  const TimesheetState();
  @override
  List<Object?> get props => const [];
}

final class TimesheetLoading extends TimesheetState {
  const TimesheetLoading();
}

final class TimesheetFailed extends TimesheetState {
  const TimesheetFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

final class TimesheetLoaded extends TimesheetState {
  const TimesheetLoaded({
    required this.year,
    required this.month,
    required this.entries,
    required this.summary,
    required this.balance,
    this.busy = false,
    this.lastError,
  });

  final int year;
  final int month;
  final List<TimeEntry> entries;
  final TimesheetSummary summary;
  final VacationBalance balance;
  final bool busy;
  final AppFailure? lastError;

  /// Entries grouped by date (newest first), with worked time before absences.
  Map<String, List<TimeEntry>> get byDate {
    final map = <String, List<TimeEntry>>{};
    for (final e in entries) {
      (map[e.entryDate] ??= []).add(e);
    }
    return map;
  }

  TimesheetLoaded copyWith({
    List<TimeEntry>? entries,
    TimesheetSummary? summary,
    VacationBalance? balance,
    bool? busy,
    AppFailure? lastError,
  }) => TimesheetLoaded(
    year: year,
    month: month,
    entries: entries ?? this.entries,
    summary: summary ?? this.summary,
    balance: balance ?? this.balance,
    busy: busy ?? this.busy,
    lastError: lastError,
  );

  @override
  List<Object?> get props => [
    year,
    month,
    entries.map((e) => '${e.id}:${e.version}').toList(),
    busy,
    lastError,
  ];
}

class TimesheetCubit extends Cubit<TimesheetState> {
  TimesheetCubit({
    required TimesheetRepository repo,
    required int year,
    required int month,
  }) : _repo = repo,
       _year = year,
       _month = month,
       super(const TimesheetLoading());

  final TimesheetRepository _repo;
  int _year;
  int _month;

  String get _from => _iso(_year, _month, 1);
  String get _to => _iso(_year, _month, _lastDay(_year, _month));

  Future<void> load() async {
    emit(const TimesheetLoading());
    final entries = await _repo.listMyEntries(from: _from, to: _to);
    final summary = await _repo.mySummary(year: _year, month: _month);
    final balance = await _repo.myBalance();
    final fail =
        entries.failureOrNull ?? summary.failureOrNull ?? balance.failureOrNull;
    if (fail != null) {
      emit(TimesheetFailed(fail));
      return;
    }
    emit(
      TimesheetLoaded(
        year: _year,
        month: _month,
        entries: entries.valueOrNull!,
        summary: summary.valueOrNull!,
        balance: balance.valueOrNull!,
      ),
    );
  }

  Future<void> changeMonth(int delta) async {
    var m = _month + delta;
    var y = _year;
    while (m < 1) {
      m += 12;
      y -= 1;
    }
    while (m > 12) {
      m -= 12;
      y += 1;
    }
    _year = y;
    _month = m;
    await load();
  }

  Future<AppFailure?> logTime({
    required String date,
    required int minutes,
    EntryKind kind = EntryKind.work,
    String? issueId,
    String? projectId,
    String? meetingType,
    String? note,
  }) => _mutate(
    () => _repo.logTime(
      kind: kind,
      issueId: issueId,
      projectId: projectId,
      meetingType: meetingType,
      date: date,
      minutes: minutes,
      note: note,
    ),
  );

  Future<AppFailure?> editEntry({
    required String id,
    required int minutes,
    required int version,
    String? note,
  }) => _mutate(
    () => _repo.updateEntry(
      id: id,
      minutes: minutes,
      version: version,
      note: note,
    ),
  );

  Future<AppFailure?> deleteEntry(String id) =>
      _mutate(() => _repo.deleteEntry(id));

  Future<AppFailure?> bookAbsence({
    required EntryKind kind,
    required String startDate,
    required String endDate,
    int? minutesPerDay,
    String? note,
  }) => _mutate(
    () => _repo.bookAbsence(
      kind: kind,
      startDate: startDate,
      endDate: endDate,
      minutesPerDay: minutesPerDay,
      note: note,
      skipWeekends: true,
    ),
  );

  Future<AppFailure?> _mutate<T>(
    Future<Result<T, AppFailure>> Function() op,
  ) async {
    final s = state;
    if (s is TimesheetLoaded) emit(s.copyWith(busy: true, lastError: null));
    final res = await op();
    final fail = res.failureOrNull;
    if (fail != null) {
      if (s is TimesheetLoaded) emit(s.copyWith(busy: false, lastError: fail));
      return fail;
    }
    await load();
    return null;
  }

  static String _iso(int y, int m, int d) =>
      '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';

  static int _lastDay(int y, int m) => DateTime(y, m + 1, 0).day;
}
