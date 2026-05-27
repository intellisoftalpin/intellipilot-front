import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';

abstract interface class ProfileRepository {
  Future<Result<UserProfile, AppFailure>> getProfile();

  Future<Result<UserProfile, AppFailure>> updateProfile(
    ProfileUpdateRequest patch,
  );

  Future<Result<AccountErasureResponse, AppFailure>> deleteAccount();

  /// GDPR export — returns the raw decoded JSON body. UI layer is responsible
  /// for offering download / share / copy.
  Future<Result<Map<String, dynamic>, AppFailure>> exportData();
}
