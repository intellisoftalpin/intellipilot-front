import 'dart:typed_data';

import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/io/file_downloader.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/profile/data/dtos/personal_token_dtos.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';

class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({
    this.getProfileHandler,
    this.updateProfileHandler,
    this.deleteAccountHandler,
    this.exportDataHandler,
  });

  Future<Result<UserProfile, AppFailure>> Function()? getProfileHandler;
  Future<Result<UserProfile, AppFailure>> Function(ProfileUpdateRequest)?
  updateProfileHandler;
  Future<Result<AccountErasureResponse, AppFailure>> Function()?
  deleteAccountHandler;
  Future<Result<Map<String, dynamic>, AppFailure>> Function()?
  exportDataHandler;

  int getCalls = 0;
  int updateCalls = 0;
  int deleteCalls = 0;
  int exportCalls = 0;

  @override
  Future<Result<UserProfile, AppFailure>> getProfile() async {
    getCalls++;
    return getProfileHandler?.call() ??
        Future.value(
          Ok<UserProfile, AppFailure>(
            UserProfile(
              id: 'u1',
              email: 'u@e.com',
              username: 'user1',
              fullName: 'User One',
              lang: 'en',
              timezone: 'UTC',
              isActive: true,
              isSuperadmin: false,
              mustChangePassword: false,
              createdAt: DateTime(2026, 5, 27),
            ),
          ),
        );
  }

  @override
  Future<Result<UserProfile, AppFailure>> updateProfile(
    ProfileUpdateRequest patch,
  ) async {
    updateCalls++;
    return updateProfileHandler?.call(patch) ??
        Future.value(
          Ok<UserProfile, AppFailure>(
            UserProfile(
              id: 'u1',
              email: 'u@e.com',
              username: 'user1',
              fullName: patch.fullName ?? 'User One',
              lang: patch.lang ?? 'en',
              timezone: patch.timezone ?? 'UTC',
              isActive: true,
              isSuperadmin: false,
              mustChangePassword: false,
              createdAt: DateTime(2026, 5, 27),
            ),
          ),
        );
  }

  @override
  Future<Result<AccountErasureResponse, AppFailure>> deleteAccount() async {
    deleteCalls++;
    return deleteAccountHandler?.call() ??
        Future.value(
          Ok<AccountErasureResponse, AppFailure>(
            AccountErasureResponse(
              status: 'scheduled_for_erasure',
              graceUntil: DateTime(2026, 6, 26),
            ),
          ),
        );
  }

  @override
  Future<Result<Map<String, dynamic>, AppFailure>> exportData() async {
    exportCalls++;
    return exportDataHandler?.call() ??
        Future.value(
          const Ok<Map<String, dynamic>, AppFailure>({
            'user': {'id': 'u1'},
            'audit_events': <dynamic>[],
          }),
        );
  }

  @override
  Future<Result<Unit, AppFailure>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  @override
  Future<Result<UserProfile, AppFailure>> uploadAvatar({
    required String filename,
    required Uint8List bytes,
    String? contentType,
  }) => getProfile();

  @override
  Future<Result<UserProfile, AppFailure>> setEmojiAvatar(String emoji) =>
      getProfile();

  @override
  Future<Result<Unit, AppFailure>> deleteAvatar() async =>
      const Ok<Unit, AppFailure>(Unit.instance);

  /// In-memory personal token state, so cubit tests can drive the lifecycle.
  PersonalTokenDto? personalToken;

  PersonalTokenDto get _defaultToken => PersonalTokenDto(
    id: 'tok1',
    prefix: 'ippt_Ab12cd',
    last4: 'wx90',
    createdAt: DateTime(2026, 5, 27),
  );

  @override
  Future<Result<PersonalTokenDto?, AppFailure>> getPersonalToken() async =>
      Ok<PersonalTokenDto?, AppFailure>(personalToken);

  @override
  Future<Result<PersonalTokenSecretResult, AppFailure>>
  createPersonalToken() async {
    personalToken = _defaultToken;
    return Ok<PersonalTokenSecretResult, AppFailure>(
      PersonalTokenSecretResult(
        token: personalToken!,
        secret: 'ippt_secret-value-wx90',
      ),
    );
  }

  @override
  Future<Result<PersonalTokenSecretResult, AppFailure>>
  resetPersonalToken() async => createPersonalToken();

  @override
  Future<Result<Unit, AppFailure>> disablePersonalToken() async {
    final t = personalToken;
    if (t != null) {
      personalToken = PersonalTokenDto(
        id: t.id,
        prefix: t.prefix,
        last4: t.last4,
        createdAt: t.createdAt,
        disabledAt: DateTime(2026, 5, 28),
      );
    }
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  @override
  Future<Result<Unit, AppFailure>> enablePersonalToken() async {
    final t = personalToken;
    if (t != null) {
      personalToken = PersonalTokenDto(
        id: t.id,
        prefix: t.prefix,
        last4: t.last4,
        createdAt: t.createdAt,
      );
    }
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  @override
  Future<Result<Unit, AppFailure>> deletePersonalToken() async {
    personalToken = null;
    return const Ok<Unit, AppFailure>(Unit.instance);
  }
}

class RecordingDownloader implements FileDownloader {
  RecordingDownloader({this.supportsDownload = true});

  bool supportsDownload;
  String? lastFilename;
  String? lastContents;
  int calls = 0;

  @override
  bool get canDownload => supportsDownload;

  @override
  Future<bool> download({
    required String filename,
    required String mimeType,
    required String contents,
  }) async {
    calls++;
    lastFilename = filename;
    lastContents = contents;
    return true;
  }

  @override
  Future<bool> downloadBytes({
    required String filename,
    required String mimeType,
    required List<int> bytes,
  }) async {
    calls++;
    lastFilename = filename;
    return true;
  }
}
