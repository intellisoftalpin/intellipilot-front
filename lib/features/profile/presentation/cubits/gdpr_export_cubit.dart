// Underscore-prefixed fields are clearer than `{required this._repo}` in
// the public constructor — silence the lint at file scope.
// ignore_for_file: prefer_initializing_formals
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/io/file_downloader.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';

sealed class GdprExportState extends Equatable {
  const GdprExportState();
  @override
  List<Object?> get props => const [];
}

final class GdprIdle extends GdprExportState {
  const GdprIdle();
}

final class GdprRunning extends GdprExportState {
  const GdprRunning();
}

final class GdprDownloaded extends GdprExportState {
  const GdprDownloaded({required this.bytesCount, required this.viaClipboard});
  final int bytesCount;
  final bool viaClipboard;
  @override
  List<Object?> get props => [bytesCount, viaClipboard];
}

final class GdprFailed extends GdprExportState {
  const GdprFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class GdprExportCubit extends Cubit<GdprExportState> {
  GdprExportCubit({
    required ProfileRepository repo,
    required FileDownloader downloader,
  }) : _repo = repo,
       _downloader = downloader,
       super(const GdprIdle());

  final ProfileRepository _repo;
  final FileDownloader _downloader;

  bool get canDownload => _downloader.canDownload;

  Future<void> run() async {
    emit(const GdprRunning());
    final res = await _repo.exportData();
    await res.when(
      ok: (json) async {
        const enc = JsonEncoder.withIndent('  ');
        final body = enc.convert(json);
        await _downloader.download(
          filename: 'intellipilot-export.json',
          mimeType: 'application/json',
          contents: body,
        );
        emit(
          GdprDownloaded(
            bytesCount: body.length,
            viaClipboard: !_downloader.canDownload,
          ),
        );
      },
      err: (f) async => emit(GdprFailed(f)),
    );
  }
}
