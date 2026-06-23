// Keep field names readable in the public constructor.
// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/l10n/locale_cubit.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';

sealed class ProfileState extends Equatable {
  const ProfileState();
  @override
  List<Object?> get props => const [];
}

final class ProfileLoading extends ProfileState {
  const ProfileLoading();
}

final class ProfileLoaded extends ProfileState {
  const ProfileLoaded({
    required this.profile,
    this.saving = false,
    this.savedAt,
    this.lastError,
  });
  final UserProfile profile;
  final bool saving;
  final DateTime? savedAt;
  final AppFailure? lastError;

  ProfileLoaded copyWith({
    UserProfile? profile,
    bool? saving,
    DateTime? savedAt,
    AppFailure? lastError,
  }) => ProfileLoaded(
    profile: profile ?? this.profile,
    saving: saving ?? this.saving,
    savedAt: savedAt,
    lastError: lastError,
  );

  @override
  List<Object?> get props => [profile.id, saving, savedAt, lastError];
}

final class ProfileLoadFailed extends ProfileState {
  const ProfileLoadFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class ProfileCubit extends Cubit<ProfileState> {
  ProfileCubit({required ProfileRepository repo, required LocaleCubit locale})
    : _repo = repo,
      _locale = locale,
      super(const ProfileLoading());

  final ProfileRepository _repo;
  final LocaleCubit _locale;

  Future<void> load() async {
    emit(const ProfileLoading());
    try {
      final res = await _repo.getProfile();
      res.when(
        ok: (p) => emit(ProfileLoaded(profile: p)),
        err: (f) => emit(ProfileLoadFailed(f)),
      );
    } on Object catch (e) {
      emit(ProfileLoadFailed(UnknownFailure(cause: e)));
    }
  }

  Future<void> save({
    String? fullName,
    String? lang,
    String? timezone,
    String? motto,
    String? moodEmoji,
    String? moodText,
  }) async {
    final current = state;
    if (current is! ProfileLoaded) return;
    emit(current.copyWith(saving: true, lastError: null));

    final res = await _repo.updateProfile(
      ProfileUpdateRequest(
        fullName: fullName,
        lang: lang,
        timezone: timezone,
        motto: motto,
        moodEmoji: moodEmoji,
        moodText: moodText,
      ),
    );
    res.when(
      ok: (updated) {
        // Reflect the new lang in the app's live locale so the UI changes
        // without waiting for the next cold-start fetch.
        if (lang != null && lang != current.profile.lang) {
          unawaited(_locale.setLocale(Locale(lang)));
        }
        emit(ProfileLoaded(profile: updated, savedAt: DateTime.now()));
      },
      err: (f) => emit(current.copyWith(saving: false, lastError: f)),
    );
  }

  Future<void> uploadAvatar({
    required String filename,
    required Uint8List bytes,
    String? contentType,
  }) async {
    final current = state;
    if (current is! ProfileLoaded) return;
    emit(current.copyWith(saving: true, lastError: null));
    final res = await _repo.uploadAvatar(
      filename: filename,
      bytes: bytes,
      contentType: contentType,
    );
    res.when(
      ok: (updated) =>
          emit(ProfileLoaded(profile: updated, savedAt: DateTime.now())),
      err: (f) => emit(current.copyWith(saving: false, lastError: f)),
    );
  }

  Future<void> setEmojiAvatar(String emoji) async {
    final current = state;
    if (current is! ProfileLoaded) return;
    emit(current.copyWith(saving: true, lastError: null));
    final res = await _repo.setEmojiAvatar(emoji);
    res.when(
      ok: (updated) =>
          emit(ProfileLoaded(profile: updated, savedAt: DateTime.now())),
      err: (f) => emit(current.copyWith(saving: false, lastError: f)),
    );
  }

  Future<void> resetAvatar() async {
    final current = state;
    if (current is! ProfileLoaded) return;
    emit(current.copyWith(saving: true, lastError: null));
    final res = await _repo.deleteAvatar();
    if (res.isErr) {
      emit(current.copyWith(saving: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }
}
