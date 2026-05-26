import 'package:dio/dio.dart';

/// Provider for the current access token. Wired to `SessionBloc` at runtime;
/// returns null when the user is unauthenticated.
typedef AccessTokenProvider = String? Function();

/// Attaches `Authorization: Bearer <access>` when a token is available.
///
/// The Phase 2 work will extend this with the refresh-on-401 flow described
/// in `docs/ARCHITECTURE.md` §9. For Phase 1 we only attach; we don't refresh.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._tokenProvider);
  final AccessTokenProvider _tokenProvider;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _tokenProvider();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}
