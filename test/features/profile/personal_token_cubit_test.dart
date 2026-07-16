import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/features/profile/presentation/cubits/personal_token_cubit.dart';

import '../../helpers/fake_profile_repository.dart';

void main() {
  group('PersonalTokenCubit', () {
    late FakeProfileRepository repo;

    setUp(() => repo = FakeProfileRepository());

    blocTest<PersonalTokenCubit, PersonalTokenState>(
      'load() with no token emits Loaded(null)',
      build: () => PersonalTokenCubit(repo),
      act: (c) => c.load(),
      expect: () => [
        isA<PersonalTokenLoading>(),
        isA<PersonalTokenLoaded>().having((s) => s.token, 'token', isNull),
      ],
    );

    blocTest<PersonalTokenCubit, PersonalTokenState>(
      'create() returns the one-time secret and loads the token',
      build: () => PersonalTokenCubit(repo),
      act: (c) async {
        final r = await c.create();
        expect(r?.secret, startsWith('ippt_'));
      },
      expect: () => [
        isA<PersonalTokenLoaded>().having((s) => s.token, 'token', isNotNull),
      ],
    );

    blocTest<PersonalTokenCubit, PersonalTokenState>(
      'disable then enable round-trips the disabled flag',
      build: () => PersonalTokenCubit(repo),
      act: (c) async {
        await c.create();
        await c.setDisabled(disabled: true);
        await c.setDisabled(disabled: false);
      },
      skip: 1, // the create() emission
      expect: () => [
        isA<PersonalTokenLoaded>().having((s) => s.busy, 'busy', isTrue),
        isA<PersonalTokenLoading>(),
        isA<PersonalTokenLoaded>().having(
          (s) => s.token?.isDisabled,
          'disabled',
          isTrue,
        ),
        isA<PersonalTokenLoaded>().having((s) => s.busy, 'busy', isTrue),
        isA<PersonalTokenLoading>(),
        isA<PersonalTokenLoaded>().having(
          (s) => s.token?.isDisabled,
          'disabled',
          isFalse,
        ),
      ],
    );

    blocTest<PersonalTokenCubit, PersonalTokenState>(
      'delete() ends with no token',
      build: () => PersonalTokenCubit(repo),
      act: (c) async {
        await c.create();
        await c.delete();
      },
      verify: (c) {
        final s = c.state;
        expect(s, isA<PersonalTokenLoaded>());
        expect((s as PersonalTokenLoaded).token, isNull);
      },
    );
  });
}
