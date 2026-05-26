import 'package:dio/dio.dart';

/// Attaches an `If-Match` header from `options.extra['etag']` on PATCH/PUT
/// requests so the backend can perform optimistic concurrency control.
class EtagInterceptor extends Interceptor {
  const EtagInterceptor();

  static const String header = 'If-Match';
  static const String etagExtra = 'etag';

  static const _gatedMethods = {'PATCH', 'PUT', 'DELETE'};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!_gatedMethods.contains(options.method.toUpperCase())) {
      handler.next(options);
      return;
    }
    final etag = options.extra[etagExtra];
    if (etag is String && etag.isNotEmpty) {
      options.headers.putIfAbsent(header, () => etag);
    }
    handler.next(options);
  }
}
