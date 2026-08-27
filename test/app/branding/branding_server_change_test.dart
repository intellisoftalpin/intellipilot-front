import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/app/branding/branding_cubit.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/network/server_endpoint.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';

import '../../helpers/fake_auth_repository.dart';

AuthConfig _config({String? name, String? message, bool icon = false}) =>
    AuthConfig(
      openRegistration: false,
      passwordResetEnabled: true,
      appName: name,
      appMessage: message,
      hasCustomIcon: icon,
      appIconUpdatedAt: '2026-01-01T00:00:00Z',
    );

void main() {
  test('branding follows the server the app is pointed at', () async {
    // The bug: branding is app-lifetime state loaded once at startup, so after
    // pointing at a second server the login screen still showed the first
    // server's name, motto and logo — a claim about who you are signing in to.
    final storage = InMemoryKeyValueStorage();
    final endpoint = ServerEndpoint(storage: storage, compileTimeBase: '');
    ServerEndpoint.active = endpoint;
    addTearDown(() => ServerEndpoint.active = null);
    await endpoint.save('https://one.example.com');

    var current = _config(name: 'Acme Pilot', message: 'Ship it', icon: true);
    final cubit = BrandingCubit(
      FakeAuthRepository(authConfigHandler: () async => Ok(current)),
      ApiConfig.fromEnvironment(),
    );

    await cubit.load();
    expect(cubit.state.appName, 'Acme Pilot');
    expect(cubit.state.appMessage, 'Ship it');
    expect(cubit.state.iconUrl, startsWith('https://one.example.com/'));

    // Now the second server: different identity, no custom icon.
    await endpoint.save('https://two.example.com');
    current = _config(name: 'Globex Tracker');
    cubit.reset();
    await cubit.load();

    expect(cubit.state.appName, 'Globex Tracker');
    expect(cubit.state.appMessage, isNull);
    expect(cubit.state.iconUrl, isNull);
  });

  test(
    'an unreachable server shows the bundled default, not the last one',
    () async {
      // `load` deliberately keeps the current state on failure. That is only safe
      // because the server change resets first — otherwise a server that cannot
      // be reached would keep wearing the previous one's identity.
      final storage = InMemoryKeyValueStorage();
      final endpoint = ServerEndpoint(storage: storage, compileTimeBase: '');
      ServerEndpoint.active = endpoint;
      addTearDown(() => ServerEndpoint.active = null);
      await endpoint.save('https://one.example.com');

      var reachable = true;
      final cubit = BrandingCubit(
        FakeAuthRepository(
          authConfigHandler: () async => reachable
              ? Ok(_config(name: 'Acme Pilot', message: 'Ship it'))
              : const Err(NetworkFailure()),
        ),
        ApiConfig.fromEnvironment(),
      );

      await cubit.load();
      expect(cubit.state.appName, 'Acme Pilot');

      reachable = false;
      cubit.reset();
      await cubit.load();

      expect(cubit.state.appName, isNull);
      expect(cubit.state.appMessage, isNull);
    },
  );
}
