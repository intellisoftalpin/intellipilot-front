// Underscore-prefixed fields are clearer than `{required this._repo}` in
// the public constructor — silence the lint at file scope.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/io/file_picker.dart';
import 'package:intellipilot/core/network/sse/project_events_service.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/meetings/data/dtos/meeting_dtos.dart';
import 'package:intellipilot/features/meetings/domain/meetings_repository.dart';

sealed class MeetingDetailState {
  const MeetingDetailState();
}

final class MeetingDetailLoading extends MeetingDetailState {
  const MeetingDetailLoading();
}

final class MeetingDetailFailed extends MeetingDetailState {
  const MeetingDetailFailed(this.failure);
  final AppFailure failure;
}

/// The meeting is gone — deleted here or by someone else.
final class MeetingDetailDeleted extends MeetingDetailState {
  const MeetingDetailDeleted();
}

final class MeetingDetailLoaded extends MeetingDetailState {
  const MeetingDetailLoaded(this.meeting, {this.saving = false});
  final Meeting meeting;

  /// A write is in flight; edit actions disable themselves meanwhile.
  final bool saving;
}

/// Loads one meeting and performs every edit on it. Edits return their
/// failure (null on success) so the page can show it where the user acted;
/// the state always holds the latest meeting the server returned.
class MeetingDetailCubit extends Cubit<MeetingDetailState> {
  MeetingDetailCubit({
    required MeetingsRepository repo,
    required this.projectId,
    required this.meetingId,
    ProjectEventsService? events,
  }) : _repo = repo,
       super(const MeetingDetailLoading()) {
    _sub = events?.watch(projectId).listen(_onEvent);
  }

  final MeetingsRepository _repo;
  final String projectId;
  final String meetingId;
  StreamSubscription<LiveEvent>? _sub;

  Meeting? get meeting => switch (state) {
    MeetingDetailLoaded(:final meeting) => meeting,
    _ => null,
  };

  Future<void> load({bool quiet = false}) async {
    if (!quiet) emit(const MeetingDetailLoading());
    final res = await _repo.get(projectId, meetingId);
    if (isClosed) return;
    res.when(
      ok: (m) => emit(MeetingDetailLoaded(m)),
      err: (f) {
        if (f is NotFoundFailure && quiet) {
          emit(const MeetingDetailDeleted());
        } else if (!quiet || state is! MeetingDetailLoaded) {
          emit(MeetingDetailFailed(f));
        }
      },
    );
  }

  Future<AppFailure?> _write(
    Future<Result<Meeting, AppFailure>> Function() call,
  ) async {
    final current = meeting;
    if (current != null) emit(MeetingDetailLoaded(current, saving: true));
    final res = await call();
    if (isClosed) return null;
    final failure = res.failureOrNull;
    if (failure == null) {
      emit(MeetingDetailLoaded(res.valueOrNull!));
      return null;
    }
    if (failure is ConflictFailure) {
      // Someone else saved first: show their version; the caller reports
      // the conflict so the user can redo the edit on top of it.
      await load(quiet: true);
    } else if (current != null) {
      emit(MeetingDetailLoaded(current));
    }
    return failure;
  }

  /// Applies [body] under the meeting's current revision.
  Future<AppFailure?> update(UpdateMeetingRequest body) {
    final current = meeting;
    if (current == null) return Future.value(const UnknownFailure());
    return _write(
      () => _repo.update(
        projectId,
        meetingId,
        body: body,
        etag: current.etag,
      ),
    );
  }

  Future<AppFailure?> saveSummary(String markdown) =>
      update(UpdateMeetingRequest(summary: markdown));

  Future<AppFailure?> saveTranscript(String text) =>
      update(UpdateMeetingRequest(transcript: text));

  Future<AppFailure?> link(MeetingLinkKind kind, String targetId) =>
      _write(() => _repo.link(projectId, meetingId, kind, targetId));

  Future<AppFailure?> unlink(MeetingLinkKind kind, String targetId) =>
      _write(() => _repo.unlink(projectId, meetingId, kind, targetId));

  Future<AppFailure?> importText(MeetingTextTarget target, PickedFile file) =>
      _write(
        () => _repo.importText(
          projectId,
          meetingId,
          target: target,
          file: file,
        ),
      );

  Future<AppFailure?> deleteArtifact(String attachmentId) async {
    final res = await _repo.deleteArtifact(projectId, meetingId, attachmentId);
    final failure = res.failureOrNull;
    if (failure == null) await load(quiet: true);
    return failure;
  }

  /// Deletes the whole meeting (and its files).
  Future<AppFailure?> deleteMeeting() async {
    final res = await _repo.delete(projectId, meetingId);
    final failure = res.failureOrNull;
    if (failure == null && !isClosed) emit(const MeetingDetailDeleted());
    return failure;
  }

  Future<SignedDownload?> sign(String attachmentId) async =>
      (await _repo.signUrl(projectId, attachmentId)).valueOrNull;

  /// A file finished uploading: pick up the new artifact list.
  Future<void> artifactAdded() => load(quiet: true);

  void _onEvent(LiveEvent e) {
    if (e.isControl) {
      unawaited(load(quiet: true));
      return;
    }
    if (e.payload['meeting_id'] != meetingId) return;
    switch (e.payload['event']) {
      case 'meeting.deleted':
        if (!isClosed) emit(const MeetingDetailDeleted());
      case 'meeting.updated':
        // Our own writes already hold the server's answer; a refetch of an
        // equal version is harmless, and a newer one is what we want.
        final current = meeting;
        if (current == null || state is! MeetingDetailLoaded) return;
        if ((state as MeetingDetailLoaded).saving) return;
        unawaited(load(quiet: true));
    }
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
