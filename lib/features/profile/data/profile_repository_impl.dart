import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/error/failure_mapper.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';

const _me = '/api/v1/me';

class ProfileRepositoryImpl implements ProfileRepository {
  ProfileRepositoryImpl(this._api);
  final ApiClient _api;

  @override
  Future<Result<UserProfile, AppFailure>> getProfile() async {
    final res = await _api.get(_me);
    return res.when(
      ok: (r) => Ok(UserProfile.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<UserProfile, AppFailure>> updateProfile(
    ProfileUpdateRequest patch,
  ) async {
    try {
      final response = await _api.dio.patch<dynamic>(_me, data: patch.toJson());
      return Ok(UserProfile.fromJson(response.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<UserProfile, AppFailure>> uploadAvatar({
    required String filename,
    required Uint8List bytes,
    String? contentType,
  }) async {
    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: filename,
          contentType: contentType == null
              ? null
              : DioMediaType.parse(contentType),
        ),
      });
      final res = await _api.dio.put<dynamic>(
        '$_me/avatar',
        data: form,
        options: Options(contentType: 'multipart/form-data'),
      );
      return Ok(UserProfile.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<UserProfile, AppFailure>> setEmojiAvatar(String emoji) async {
    try {
      final res = await _api.dio.put<dynamic>(
        '$_me/avatar/emoji',
        data: {'emoji': emoji},
      );
      return Ok(UserProfile.fromJson(res.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> deleteAvatar() async {
    try {
      await _api.dio.delete<dynamic>('$_me/avatar');
      return const Ok<Unit, AppFailure>(Unit.instance);
    } on DioException catch (e) {
      if (e.response?.statusCode == 204) {
        return const Ok<Unit, AppFailure>(Unit.instance);
      }
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _api.dio.post<dynamic>(
        '$_me/password',
        data: {
          'current_password': currentPassword,
          'new_password': newPassword,
        },
      );
      return const Ok<Unit, AppFailure>(Unit.instance);
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<AccountErasureResponse, AppFailure>> deleteAccount() async {
    try {
      final response = await _api.dio.delete<dynamic>(_me);
      return Ok(
        AccountErasureResponse.fromJson(response.data as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Map<String, dynamic>, AppFailure>> exportData() async {
    final res = await _api.get('$_me/export');
    return res.when(
      ok: (r) => Ok(Map<String, dynamic>.from(r.data as Map)),
      err: Err.new,
    );
  }
}
