import 'dart:typed_data';

import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/issues_io/data/dtos/issues_io_dtos.dart';

/// Backend operations for exporting and importing project issues.
abstract interface class IssuesIoRepository {
  /// Download all project issues as CSV or XLSX bytes.
  Future<Result<Uint8List, AppFailure>> export(
    String projectId,
    ExportFormat format,
  );

  /// Parse an uploaded file and report the values to map (no writes).
  Future<Result<ImportPreview, AppFailure>> preview(
    String projectId, {
    required String filename,
    required Uint8List bytes,
  });

  /// Commit the import with the resolved mapping.
  Future<Result<ImportResult, AppFailure>> commit(
    String projectId, {
    required String filename,
    required Uint8List bytes,
    required ImportMapping mapping,
  });
}
