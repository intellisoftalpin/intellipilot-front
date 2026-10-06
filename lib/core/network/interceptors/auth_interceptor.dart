import 'package:dio/dio.dart';
import 'package:intellipilot/core/network/interceptors/refresh_interceptor.dart';

/// Provider for the current access token. Wired to `SessionBloc` at runtime;
/// returns null when the user is unauthenticated.
typedef AccessTokenProvider = String? Function();

/// Provider for an access token that is renewed first when the one held has
/// expired. Wired to `SessionBloc.freshAccessToken`.
typedef FreshAccessTokenProvider = Future<String?> Function();

/// Attaches `Authorization: Bearer <access>` when a token is available.
///
/// With a [FreshAccessTokenProvider], a request whose token has expired waits
/// for the renewal instead of going out with it: after a background tab or a
/// sleeping device resumes, that spares the request a 401 and a retry. Session
/// endpoints never wait — the renewal request itself would wait on itself.
/// Requests still run side by side; only the token lookup can wait.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._tokenProvider, [this._fresh]);
  final AccessTokenProvider _tokenProvider;
  final FreshAccessTokenProvider? _fresh;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final fresh = _fresh;
    String? token;
    if (fresh == null || isAuthEndpoint(options.path)) {
      token = _tokenProvider();
    } else {
      try {
        token = await fresh();
      } on Object {
        token = _tokenProvider();
      }
    }
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}
