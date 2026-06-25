// `_repo` is intentionally kept as a private field rather than an initializing
// formal so its lifetime is obvious within the cubit.
// ignore_for_file: prefer_initializing_formals

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/activity/domain/activity_repository.dart';

/// Filters surfaced as the three-way toggle on the activity stream.
enum ActivityFilter { all, comments, history }

sealed class ActivityStreamState extends Equatable {
  const ActivityStreamState();
  @override
  List<Object?> get props => [];
}

class ActivityStreamLoading extends ActivityStreamState {
  const ActivityStreamLoading();
}

class ActivityStreamFailed extends ActivityStreamState {
  const ActivityStreamFailed();
}

class ActivityStreamLoaded extends ActivityStreamState {
  const ActivityStreamLoaded({
    required this.comments,
    required this.history,
    required this.filter,
    this.busy = false,
  });

  final List<Comment> comments;
  final List<HistoryEvent> history;
  final ActivityFilter filter;
  final bool busy;

  ActivityStreamLoaded copyWith({
    List<Comment>? comments,
    List<HistoryEvent>? history,
    ActivityFilter? filter,
    bool? busy,
  }) => ActivityStreamLoaded(
    comments: comments ?? this.comments,
    history: history ?? this.history,
    filter: filter ?? this.filter,
    busy: busy ?? this.busy,
  );

  /// Single chronological list ready to render. Newest first so users see
  /// recent activity without scrolling.
  List<ActivityEntry> get entries {
    final out = <ActivityEntry>[];
    if (filter == ActivityFilter.all || filter == ActivityFilter.comments) {
      out.addAll(comments.map(ActivityEntry.comment));
    }
    if (filter == ActivityFilter.all || filter == ActivityFilter.history) {
      out.addAll(history.map(ActivityEntry.history));
    }
    out.sort((a, b) => b.at.compareTo(a.at));
    return out;
  }

  @override
  List<Object?> get props => [comments, history, filter, busy];
}

class ActivityStreamCubit extends Cubit<ActivityStreamState> {
  ActivityStreamCubit({
    required ActivityRepository repo,
    required this.projectId,
    required this.kind,
    required this.entityId,
  }) : _repo = repo,
       super(const ActivityStreamLoading());

  final ActivityRepository _repo;
  final String projectId;
  final EntityKind kind;
  final String entityId;

  Future<void> load() async {
    if (!isClosed) emit(const ActivityStreamLoading());
    final commentsRes = await _repo.listComments(projectId, kind, entityId);
    final historyRes = await _repo.listHistory(projectId, kind, entityId);
    final c = commentsRes.valueOrNull;
    final h = historyRes.valueOrNull;
    if (c == null || h == null) {
      if (!isClosed) emit(const ActivityStreamFailed());
      return;
    }
    if (!isClosed) {
      emit(
        ActivityStreamLoaded(
          comments: c,
          history: h,
          filter: ActivityFilter.all,
        ),
      );
    }
  }

  void setFilter(ActivityFilter f) {
    final s = state;
    if (s is! ActivityStreamLoaded) return;
    emit(s.copyWith(filter: f));
  }

  Future<bool> postComment(String body) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return false;
    final s = state;
    if (s is! ActivityStreamLoaded) return false;
    emit(s.copyWith(busy: true));
    final res = await _repo.createComment(
      projectId,
      kind,
      entityId,
      CreateCommentRequest(body: trimmed),
    );
    final c = res.valueOrNull;
    if (c == null) {
      if (!isClosed) emit(s.copyWith(busy: false));
      return false;
    }
    if (!isClosed) {
      emit(
        s.copyWith(comments: [...s.comments, c], busy: false),
      );
    }
    return true;
  }

  Future<bool> editComment(String commentId, String body) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return false;
    final s = state;
    if (s is! ActivityStreamLoaded) return false;
    final res = await _repo.updateComment(
      projectId,
      kind,
      entityId,
      commentId,
      UpdateCommentRequest(body: trimmed),
    );
    final c = res.valueOrNull;
    if (c == null) return false;
    if (!isClosed) {
      emit(
        s.copyWith(
          comments: s.comments.map((x) => x.id == commentId ? c : x).toList(),
        ),
      );
    }
    return true;
  }

  Future<bool> removeComment(String commentId) async {
    final s = state;
    if (s is! ActivityStreamLoaded) return false;
    final res = await _repo.deleteComment(
      projectId,
      kind,
      entityId,
      commentId,
    );
    if (res.valueOrNull == null) return false;
    if (!isClosed) {
      emit(
        s.copyWith(
          comments: s.comments.where((c) => c.id != commentId).toList(),
        ),
      );
    }
    return true;
  }
}
