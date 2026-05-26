import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/app/session/session_bloc.dart';

void main() {
  group('SessionBloc (Phase 1 skeleton)', () {
    test('starts in SessionUnknown', () {
      expect(SessionBloc().state, const SessionUnknown());
    });

    blocTest<SessionBloc, SessionState>(
      'SessionRestored → SessionUnauthenticated',
      build: SessionBloc.new,
      act: (b) => b.add(const SessionRestored()),
      expect: () => [const SessionUnauthenticated()],
    );

    blocTest<SessionBloc, SessionState>(
      'SessionLoggedOut → SessionUnauthenticated',
      build: SessionBloc.new,
      seed: () => const SessionAuthenticated(accessToken: 't'),
      act: (b) => b.add(const SessionLoggedOut()),
      expect: () => [const SessionUnauthenticated()],
    );

    test('currentAccessToken is null while unauthenticated', () {
      expect(SessionBloc().currentAccessToken, isNull);
    });

    test('SessionAuthenticated carries the access token', () {
      const s = SessionAuthenticated(accessToken: 'abc');
      expect(s.accessToken, 'abc');
      expect(s.props, const ['abc']);
    });
  });
}
