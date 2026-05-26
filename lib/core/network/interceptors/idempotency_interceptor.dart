import 'package:dio/dio.dart';
import 'package:intellipilot/core/utils/uuid_gen.dart';

/// Adds an `Idempotency-Key` header to mutating requests when the caller
/// hasn't supplied one. The caller may opt out per-request by setting
/// `options.extra['idempotency_skip'] = true` (e.g. for endpoints that don't
/// support replay-safe semantics).
///
/// The header value is taken from `options.extra['idempotency_key']` when
/// the caller pre-generated one (useful for retry-on-network-error flows
/// where we want the *same* key on retry).
class IdempotencyInterceptor extends Interceptor {
  IdempotencyInterceptor(this._uuid);
  final UuidGen _uuid;

  static const String header = 'Idempotency-Key';
  static const String _skipExtra = 'idempotency_skip';
  static const String _keyExtra = 'idempotency_key';

  static const _mutatingMethods = {'POST', 'PATCH', 'PUT', 'DELETE'};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.extra[_skipExtra] == true) {
      handler.next(options);
      return;
    }
    if (!_mutatingMethods.contains(options.method.toUpperCase())) {
      handler.next(options);
      return;
    }
    final pre = options.extra[_keyExtra];
    final key = pre is String && pre.isNotEmpty ? pre : _uuid.v4();
    options.headers.putIfAbsent(header, () => key);
    handler.next(options);
  }
}
