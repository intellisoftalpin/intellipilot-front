// Underscore-prefixed fields are clearer than `{required this._repo}` in
// the public constructor — silence the lint at file scope.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/network/sse/project_events_service.dart';
import 'package:intellipilot/features/meetings/data/dtos/meeting_dtos.dart';
import 'package:intellipilot/features/meetings/domain/meetings_repository.dart';

DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// State of the meetings calendar: which month is shown, which day is picked,
/// and the meetings of the month (plus the days around it that a six-week
/// grid shows).
class MeetingsCalendarState {
  const MeetingsCalendarState({
    required this.month,
    required this.selectedDay,
    this.loading = true,
    this.meetings = const [],
    this.counts = const {},
    this.failure,
  });

  /// First day of the displayed month.
  final DateTime month;
  final DateTime selectedDay;
  final bool loading;

  /// Everything loaded for the displayed range, server order (by date, then
  /// untimed first, then start time, then title).
  final List<MeetingListItem> meetings;

  /// Meetings per day for the displayed range.
  final Map<DateTime, int> counts;
  final AppFailure? failure;

  int countOn(DateTime day) => counts[_dayOf(day)] ?? 0;

  List<MeetingListItem> meetingsOn(DateTime day) {
    final d = _dayOf(day);
    return meetings.where((m) => m.date == d).toList();
  }

  List<MeetingListItem> get selectedMeetings => meetingsOn(selectedDay);

  MeetingsCalendarState copyWith({
    DateTime? month,
    DateTime? selectedDay,
    bool? loading,
    List<MeetingListItem>? meetings,
    Map<DateTime, int>? counts,
    AppFailure? failure,
    bool clearFailure = false,
  }) => MeetingsCalendarState(
    month: month ?? this.month,
    selectedDay: selectedDay ?? this.selectedDay,
    loading: loading ?? this.loading,
    meetings: meetings ?? this.meetings,
    counts: counts ?? this.counts,
    failure: clearFailure ? null : (failure ?? this.failure),
  );
}

/// Drives the meetings dashboard. Loads a month at a time — the month plus a
/// week either side, which covers every day a six-week grid can show whatever
/// the week start — and reloads on live meeting events.
class MeetingsCalendarCubit extends Cubit<MeetingsCalendarState> {
  MeetingsCalendarCubit({
    required MeetingsRepository repo,
    required this.projectId,
    ProjectEventsService? events,
    DateTime Function()? now,
    DateTime? initialDay,
  }) : _repo = repo,
       _now = now ?? DateTime.now,
       super(_initial(initialDay ?? (now ?? DateTime.now)())) {
    _sub = events?.watch(projectId).listen(_onEvent);
  }

  static MeetingsCalendarState _initial(DateTime day) {
    final d = _dayOf(day);
    return MeetingsCalendarState(
      month: DateTime(d.year, d.month),
      selectedDay: d,
    );
  }

  final MeetingsRepository _repo;
  final String projectId;
  final DateTime Function() _now;
  StreamSubscription<LiveEvent>? _sub;
  Timer? _debounce;
  int _seq = 0;

  /// First and last day fetched for [month].
  static (DateTime, DateTime) rangeFor(DateTime month) {
    final first = DateTime(month.year, month.month);
    final last = DateTime(month.year, month.month + 1, 0);
    return (
      first.subtract(const Duration(days: 7)),
      last.add(const Duration(days: 7)),
    );
  }

  Future<void> load() async {
    final seq = ++_seq;
    final month = state.month;
    emit(state.copyWith(loading: true));
    final (from, to) = rangeFor(month);
    final res = await _repo.listRange(projectId, from: from, to: to);
    // A later month switch owns the state now.
    if (isClosed || seq != _seq) return;
    final failure = res.failureOrNull;
    if (failure != null) {
      emit(state.copyWith(loading: false, failure: failure));
      return;
    }
    final range = res.valueOrNull!;
    emit(
      state.copyWith(
        loading: false,
        meetings: range.meetings,
        counts: {for (final d in range.days) _dayOf(d.date): d.count},
        clearFailure: true,
      ),
    );
  }

  /// Picks [day]; a day outside the shown month switches to its month.
  Future<void> selectDay(DateTime day) async {
    final d = _dayOf(day);
    if (d.year == state.month.year && d.month == state.month.month) {
      emit(state.copyWith(selectedDay: d));
      return;
    }
    emit(state.copyWith(month: DateTime(d.year, d.month), selectedDay: d));
    await load();
  }

  /// Moves the shown month by [delta]; the selection follows to the same day
  /// number, clamped to the new month's length.
  Future<void> shiftMonth(int delta) async {
    final m = DateTime(state.month.year, state.month.month + delta);
    final lastDay = DateTime(m.year, m.month + 1, 0).day;
    final day = state.selectedDay.day.clamp(1, lastDay);
    emit(state.copyWith(month: m, selectedDay: DateTime(m.year, m.month, day)));
    await load();
  }

  Future<void> today() => selectDay(_now());

  void _onEvent(LiveEvent e) {
    final ev = e.payload['event'];
    final relevant = e.isControl || (ev is String && ev.startsWith('meeting.'));
    if (!relevant) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!isClosed) unawaited(load());
    });
  }

  @override
  Future<void> close() async {
    _debounce?.cancel();
    await _sub?.cancel();
    return super.close();
  }
}
