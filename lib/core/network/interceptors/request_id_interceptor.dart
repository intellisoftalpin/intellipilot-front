import 'package:dio/dio.dart';
import 'package:intellipilot/core/utils/uuid_gen.dart';

/// Stamps every outgoing request with an `X-Request-Id` header so logs and
/// crash reports can be correlated with backend trace IDs.
class RequestIdInterceptor extends Interceptor {
  RequestIdInterceptor(this._uuid);
  final UuidGen _uuid;

  static const String header = 'X-Request-Id';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers.putIfAbsent(header, _uuid.v4);
    handler.next(options);
  }
}
