// Underscore-prefixed fields are clearer than `{required this._repo}` in
// the public constructor — silence the lint at file scope.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/io/large_upload.dart';
import 'package:intellipilot/features/meetings/data/dtos/meeting_dtos.dart';
import 'package:intellipilot/features/meetings/domain/meetings_repository.dart';

enum UploadStatus { running, done, failed, cancelled }

/// One file on its way up.
class MeetingUpload {
  const MeetingUpload({
    required this.id,
    required this.name,
    required this.kind,
    required this.total,
    this.sent = 0,
    this.status = UploadStatus.running,
    this.failure,
  });

  final int id;
  final String name;
  final ArtifactKind kind;
  final int sent;
  final int total;
  final UploadStatus status;
  final AppFailure? failure;

  /// 0..1, or null while the size is unknown.
  double? get fraction => total <= 0 ? null : (sent / total).clamp(0.0, 1.0);

  MeetingUpload copyWith({
    int? sent,
    int? total,
    UploadStatus? status,
    AppFailure? failure,
  }) => MeetingUpload(
    id: id,
    name: name,
    kind: kind,
    sent: sent ?? this.sent,
    total: total ?? this.total,
    status: status ?? this.status,
    failure: failure ?? this.failure,
  );
}

/// Uploads meeting files — possibly several gigabytes each — with progress and
/// cancel. Finished uploads leave the list on their own; failed and cancelled
/// ones stay until dismissed so the user sees why.
class MeetingUploadsCubit extends Cubit<List<MeetingUpload>> {
  MeetingUploadsCubit({
    required MeetingsRepository repo,
    required this.projectId,
    required this.meetingId,
    this.onUploaded,
  }) : _repo = repo,
       super(const []);

  final MeetingsRepository _repo;
  final String projectId;
  final String meetingId;

  /// Called after each successful upload (the page refetches the meeting).
  final Future<void> Function()? onUploaded;

  final Map<int, CancelToken> _tokens = {};
  int _seq = 0;

  bool get isSupported => _repo.supportsLargeUploads;

  /// Opens the platform picker; null when cancelled or unsupported.
  Future<PickedUpload?> pick({String? accept}) =>
      _repo.pickUpload(accept: accept);

  bool get hasRunning => state.any((u) => u.status == UploadStatus.running);

  void _patch(int id, MeetingUpload Function(MeetingUpload) change) {
    if (isClosed) return;
    emit([
      for (final u in state)
        if (u.id == id) change(u) else u,
    ]);
  }

  /// Starts uploading [file] as [kind]; completes when it has finished,
  /// failed or been cancelled.
  Future<void> upload(PickedUpload file, ArtifactKind kind) async {
    final id = ++_seq;
    final token = CancelToken();
    _tokens[id] = token;
    emit([
      ...state,
      MeetingUpload(id: id, name: file.name, kind: kind, total: file.sizeBytes),
    ]);
    final res = await _repo.uploadArtifact(
      projectId,
      meetingId,
      file: file,
      kind: kind,
      cancelToken: token,
      onProgress: (sent, total) =>
          _patch(id, (u) => u.copyWith(sent: sent, total: total)),
    );
    _tokens.remove(id);
    final failure = res.failureOrNull;
    if (failure == null) {
      if (isClosed) return;
      emit(state.where((u) => u.id != id).toList());
      await onUploaded?.call();
      return;
    }
    _patch(
      id,
      (u) => isUploadCancelled(failure) || token.isCancelled
          ? u.copyWith(status: UploadStatus.cancelled)
          : u.copyWith(status: UploadStatus.failed, failure: failure),
    );
  }

  void cancel(int id) => _tokens[id]?.cancel();

  void dismiss(int id) {
    if (isClosed) return;
    emit(state.where((u) => u.id != id).toList());
  }

  @override
  Future<void> close() {
    for (final t in _tokens.values) {
      t.cancel();
    }
    return super.close();
  }
}
