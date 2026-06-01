import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/io/file_downloader.dart';
import 'package:intellipilot/core/result/result.dart';
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
}
