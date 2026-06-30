import 'dart:ui';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/app/l10n/locale_cubit.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/profile/presentation/cubits/account_deletion_cubit.dart';
import 'package:intellipilot/features/profile/presentation/cubits/gdpr_export_cubit.dart';
import 'package:intellipilot/features/profile/presentation/cubits/profile_cubit.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_profile_repository.dart';

void main() {
  group('ProfileCubit', () {
    late FakeProfileRepository repo;
    late LocaleCubit locale;

    setUp(() {
      repo = FakeProfileRepository();
      locale = LocaleCubit(InMemoryKeyValueStorage());
    });
    tearDown(() => locale.close());

    blocTest<ProfileCubit, ProfileState>(
      'load() emits Loading then Loaded',
      build: () => ProfileCubit(repo: repo, locale: locale),
      act: (c) => c.load(),
      expect: () => [isA<ProfileLoading>(), isA<ProfileLoaded>()],
    );

    blocTest<ProfileCubit, ProfileState>(
      'load() emits LoadFailed on transport failure',
      build: () {
        repo.getProfileHandler = () async =>
            const Err<UserProfile, AppFailure>(NetworkFailure());
        return ProfileCubit(repo: repo, locale: locale);
      },
      act: (c) => c.load(),
      expect: () => [isA<ProfileLoading>(), isA<ProfileLoadFailed>()],
    );

    blocTest<ProfileCubit, ProfileState>(
      'save() updates the profile and persists savedAt',
      build: () => ProfileCubit(repo: repo, locale: locale),
      seed: () => ProfileLoaded(
        profile: UserProfile(
          id: 'u1',
          email: 'u@e.com',
          username: 'user1',
          fullName: '',
          lang: 'en',
          timezone: 'UTC',
          isActive: true,
          isSuperadmin: false,
          mustChangePassword: false,
          createdAt: DateTime(2026, 5, 27),
        ),
      ),
      act: (c) => c.save(fullName: 'Updated Name'),
      verify: (c) {
        expect(c.state, isA<ProfileLoaded>());
        final s = c.state as ProfileLoaded;
        expect(s.profile.fullName, 'Updated Name');
        expect(s.savedAt, isNotNull);
      },
    );

    blocTest<ProfileCubit, ProfileState>(
      "save() with new lang updates LocaleCubit's locale",
      build: () => ProfileCubit(repo: repo, locale: locale),
      seed: () => ProfileLoaded(
        profile: UserProfile(
          id: 'u1',
          email: 'u@e.com',
          username: 'user1',
          fullName: '',
          lang: 'en',
          timezone: 'UTC',
          isActive: true,
          isSuperadmin: false,
          mustChangePassword: false,
          createdAt: DateTime(2026, 5, 27),
        ),
      ),
      act: (c) => c.save(lang: 'de'),
      verify: (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(locale.state, const Locale('de'));
      },
    );

    blocTest<ProfileCubit, ProfileState>(
      'save() records lastError on transport failure',
      build: () {
        repo.updateProfileHandler = (_) async =>
            const Err<UserProfile, AppFailure>(NetworkFailure());
        return ProfileCubit(repo: repo, locale: locale);
      },
      seed: () => ProfileLoaded(
        profile: UserProfile(
          id: 'u1',
          email: 'u@e.com',
          username: 'user1',
          fullName: '',
          lang: 'en',
          timezone: 'UTC',
          isActive: true,
          isSuperadmin: false,
          mustChangePassword: false,
          createdAt: DateTime(2026, 5, 27),
        ),
      ),
      act: (c) => c.save(fullName: 'X'),
      verify: (c) {
        final s = c.state as ProfileLoaded;
        expect(s.lastError, isA<NetworkFailure>());
      },
    );
  });

  group('AccountDeletionCubit', () {
    late FakeProfileRepository repo;
    late FakeAuthRepository auth;
    late SessionBloc session;
    setUp(() {
      repo = FakeProfileRepository();
      auth = FakeAuthRepository();
      session = SessionBloc(repository: auth);
    });
    tearDown(() => session.close());

    blocTest<AccountDeletionCubit, AccountDeletionState>(
      'requires matching username; mismatch -> Failed(ValidationFailure)',
      build: () => AccountDeletionCubit(repo: repo, session: session),
      act: (c) => c.deleteAccount(
        typedConfirmation: 'wrong',
        expectedUsername: 'user1',
      ),
      expect: () => [
        predicate<AccountDeletionState>(
          (s) => s is AccountDeletionFailed && s.failure is ValidationFailure,
          'failed with ValidationFailure',
        ),
      ],
      verify: (_) => expect(repo.deleteCalls, 0),
    );

    blocTest<AccountDeletionCubit, AccountDeletionState>(
      'happy path: Running -> Scheduled, session logged out',
      build: () {
        // Seed the SessionBloc so we can verify the logout dispatch lands.
        session.add(
          const SessionEstablished(
            TokenResponse(
              accessToken: 'tok',
              tokenType: 'Bearer',
              expiresIn: 3600,
            ),
          ),
        );
        return AccountDeletionCubit(repo: repo, session: session);
      },
      act: (c) => c.deleteAccount(
        typedConfirmation: 'user1',
        expectedUsername: 'user1',
      ),
      expect: () => [
        isA<AccountDeletionRunning>(),
        isA<AccountDeletionScheduled>(),
      ],
      verify: (_) async {
        expect(repo.deleteCalls, 1);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(session.state, isA<SessionUnauthenticated>());
      },
    );

    blocTest<AccountDeletionCubit, AccountDeletionState>(
      'transport failure surfaces AccountDeletionFailed',
      build: () {
        repo.deleteAccountHandler = () async =>
            const Err<AccountErasureResponse, AppFailure>(ServerFailure());
        return AccountDeletionCubit(repo: repo, session: session);
      },
      act: (c) => c.deleteAccount(
        typedConfirmation: 'user1',
        expectedUsername: 'user1',
      ),
      expect: () => [
        isA<AccountDeletionRunning>(),
        isA<AccountDeletionFailed>(),
      ],
    );
  });

  group('GdprExportCubit', () {
    late FakeProfileRepository repo;
    setUp(() => repo = FakeProfileRepository());

    blocTest<GdprExportCubit, GdprExportState>(
      'happy path emits Running then Downloaded with the byte count',
      build: () => GdprExportCubit(
        repo: repo,
        downloader: RecordingDownloader(),
      ),
      act: (c) => c.run(),
      verify: (c) {
        expect(c.state, isA<GdprDownloaded>());
        final d = c.state as GdprDownloaded;
        expect(d.bytesCount, greaterThan(0));
        expect(d.viaClipboard, isFalse);
      },
    );

    blocTest<GdprExportCubit, GdprExportState>(
      'viaClipboard true when canDownload is false',
      build: () => GdprExportCubit(
        repo: repo,
        downloader: RecordingDownloader(supportsDownload: false),
      ),
      act: (c) => c.run(),
      verify: (c) {
        final d = c.state as GdprDownloaded;
        expect(d.viaClipboard, isTrue);
      },
    );

    blocTest<GdprExportCubit, GdprExportState>(
      'transport failure -> Failed',
      build: () {
        repo.exportDataHandler = () async =>
            const Err<Map<String, dynamic>, AppFailure>(
              ServerFailure(),
            );
        return GdprExportCubit(
          repo: repo,
          downloader: RecordingDownloader(),
        );
      },
      act: (c) => c.run(),
      expect: () => [isA<GdprRunning>(), isA<GdprFailed>()],
    );
  });
}
