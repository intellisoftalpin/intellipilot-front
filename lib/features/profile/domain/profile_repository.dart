import 'dart:typed_data';

import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';

abstract interface class ProfileRepository {
  Future<Result<UserProfile, AppFailure>> getProfile();

  Future<Result<UserProfile, AppFailure>> updateProfile(
    ProfileUpdateRequest patch,
  );

  /// Upload an avatar image (PNG/JPEG/GIF/WebP, ≤2 MiB). Returns the refreshed
  /// profile (with the new `avatar_updated_at`).
  Future<Result<UserProfile, AppFailure>> uploadAvatar({
    required String filename,
    required Uint8List bytes,
    String? contentType,
  });

  /// Set the avatar to an emoji.
  Future<Result<UserProfile, AppFailure>> setEmojiAvatar(String emoji);

  /// Reset the avatar to the default (initials).
  Future<Result<Unit, AppFailure>> deleteAvatar();

  /// Change the current user's password (local accounts only). On success the
  /// backend revokes every session, so the caller must send the user back to
  /// the login screen. LDAP accounts are rejected by the backend (409).
  Future<Result<Unit, AppFailure>> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  Future<Result<AccountErasureResponse, AppFailure>> deleteAccount();

  /// GDPR export — returns the raw decoded JSON body. UI layer is responsible
  /// for offering download / share / copy.
  Future<Result<Map<String, dynamic>, AppFailure>> exportData();
}
