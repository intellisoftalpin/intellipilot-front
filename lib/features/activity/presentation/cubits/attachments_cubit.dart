// `_repo` is intentionally kept as a private field rather than an initializing
// formal so its lifetime is obvious within the cubit.
// ignore_for_file: prefer_initializing_formals

import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/activity/domain/activity_repository.dart';

sealed class AttachmentsState extends Equatable {
  const AttachmentsState();
  @override
  List<Object?> get props => [];
}

class AttachmentsLoading extends AttachmentsState {
  const AttachmentsLoading();
}

class AttachmentsFailed extends AttachmentsState {
  const AttachmentsFailed();
}

/// In-flight upload — exposed so the UI can render a progress bar + cancel.
class UploadProgress extends Equatable {
  const UploadProgress({
    required this.filename,
    required this.sent,
    required this.total,
    required this.cancelToken,
  });

  final String filename;
  final int sent;

  /// May be -1 when the server hasn't reported Content-Length back yet.
  final int total;
  final CancelToken cancelToken;

  /// Returns null while [total] is unknown so the UI can show an
  /// indeterminate bar.
  double? get fraction {
    if (total <= 0) return null;
    return sent / total;
  }

  @override
  List<Object?> get props => [filename, sent, total];
}

class AttachmentsLoaded extends AttachmentsState {
  const AttachmentsLoaded({
    required this.items,
    this.upload,
    this.error,
  });

  final List<Attachment> items;
  final UploadProgress? upload;
  final String? error;

  AttachmentsLoaded copyWith({
    List<Attachment>? items,
    UploadProgress? upload,
    bool clearUpload = false,
    String? error,
    bool clearError = false,
  }) => AttachmentsLoaded(
    items: items ?? this.items,
    upload: clearUpload ? null : upload ?? this.upload,
    error: clearError ? null : error ?? this.error,
  );

  @override
  List<Object?> get props => [items, upload, error];
}

class AttachmentsCubit extends Cubit<AttachmentsState> {
  AttachmentsCubit({
    required ActivityRepository repo,
    required this.projectId,
    required this.kind,
    required this.entityId,
    required this.maxBytes,
  }) : _repo = repo,
       super(const AttachmentsLoading());

  final ActivityRepository _repo;
  final String projectId;
  final EntityKind kind;
  final String entityId;

  /// Server-side cap (25 MiB for non-image, 32 MiB for image uploads). We
  /// take the larger value and let the server enforce per-MIME limits.
  final int maxBytes;

  Future<void> load() async {
    if (!isClosed) emit(const AttachmentsLoading());
    final res = await _repo.listAttachments(projectId, kind, entityId);
    final items = res.valueOrNull;
    if (items == null) {
      if (!isClosed) emit(const AttachmentsFailed());
      return;
    }
    if (!isClosed) emit(AttachmentsLoaded(items: items));
  }

  /// Refuses oversized files client-side before kicking off the upload.
  Future<bool> upload({
    required String filename,
    required Uint8List bytes,
    String? contentType,
  }) async {
    final s = state;
    if (s is! AttachmentsLoaded) return false;
    if (bytes.length > maxBytes) {
      emit(s.copyWith(error: 'too_large'));
      return false;
    }
    final token = CancelToken();
    emit(
      s.copyWith(
        clearError: true,
        upload: UploadProgress(
          filename: filename,
          sent: 0,
          total: bytes.length,
          cancelToken: token,
        ),
      ),
    );
    final res = await _repo.uploadAttachment(
      projectId,
      kind,
      entityId,
      filename: filename,
      bytes: bytes,
      contentType: contentType,
      cancelToken: token,
      onSendProgress: (sent, total) {
        final cur = state;
        if (cur is! AttachmentsLoaded || cur.upload == null) return;
        emit(
          cur.copyWith(
            upload: UploadProgress(
              filename: filename,
              sent: sent,
              total: total,
              cancelToken: token,
            ),
          ),
        );
      },
    );
    final cur = state;
    if (cur is! AttachmentsLoaded) return false;
    final att = res.valueOrNull;
    if (att == null) {
      emit(cur.copyWith(clearUpload: true, error: 'upload_failed'));
      return false;
    }
    emit(
      cur.copyWith(items: [att, ...cur.items], clearUpload: true),
    );
    return true;
  }

  void cancelUpload() {
    final s = state;
    if (s is! AttachmentsLoaded || s.upload == null) return;
    s.upload!.cancelToken.cancel('cancelled by user');
    emit(s.copyWith(clearUpload: true));
  }

  Future<bool> delete(String attachmentId) async {
    final s = state;
    if (s is! AttachmentsLoaded) return false;
    final res = await _repo.deleteAttachment(projectId, attachmentId);
    if (res.valueOrNull == null) return false;
    if (!isClosed) {
      emit(
        s.copyWith(
          items: s.items.where((a) => a.id != attachmentId).toList(),
        ),
      );
    }
    return true;
  }

  /// Returns the signed URL (or null on failure) so the caller can open it
  /// in a new tab.
  Future<SignedDownload?> sign(String attachmentId) async {
    final res = await _repo.signAttachmentUrl(projectId, attachmentId);
    return res.valueOrNull;
  }
}
