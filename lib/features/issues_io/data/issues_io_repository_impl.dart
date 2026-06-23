import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/error/failure_mapper.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/issues_io/data/dtos/issues_io_dtos.dart';
import 'package:intellipilot/features/issues_io/domain/issues_io_repository.dart';

const _base = '/api/v1/projects';

class IssuesIoRepositoryImpl implements IssuesIoRepository {
  IssuesIoRepositoryImpl(this._api);
  final ApiClient _api;

  @override
  Future<Result<Uint8List, AppFailure>> export(
    String projectId,
    ExportFormat format,
  ) async {
    try {
      final r = await _api.dio.get<List<int>>(
        '$_base/$projectId/issues/export',
        queryParameters: {'format': format.wire},
        options: Options(responseType: ResponseType.bytes),
      );
      return Ok(Uint8List.fromList(r.data ?? const []));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<ImportPreview, AppFailure>> preview(
    String projectId, {
    required String filename,
    required Uint8List bytes,
  }) async {
    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      });
      final res = await _api.dio.post<dynamic>(
        '$_base/$projectId/issues/import/preview',
        data: form,
        options: Options(contentType: 'multipart/form-data'),
      );
      return Ok(ImportPreview.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<ImportResult, AppFailure>> commit(
    String projectId, {
    required String filename,
    required Uint8List bytes,
    required ImportMapping mapping,
  }) async {
    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: filename),
        'mapping': jsonEncode(mapping.toJson()),
      });
      final res = await _api.dio.post<dynamic>(
        '$_base/$projectId/issues/import',
        data: form,
        options: Options(contentType: 'multipart/form-data'),
      );
      return Ok(ImportResult.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }
}
