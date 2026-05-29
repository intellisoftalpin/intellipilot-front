import 'package:dio/dio.dart';
import 'package:intellipilot/app/build_info.dart';

/// Stamps every outgoing request with `X-Client-Version` so the backend
/// can correlate API errors with the frontend build that triggered them.
/// Value comes from [BuildInfo.clientIdentifier], which folds in the
/// version, build number, and flavor.
class ClientVersionInterceptor extends Interceptor {
  const ClientVersionInterceptor();

  static const String header = 'X-Client-Version';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers.putIfAbsent(header, () => BuildInfo.clientIdentifier);
    handler.next(options);
  }
}
