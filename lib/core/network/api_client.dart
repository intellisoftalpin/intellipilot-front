import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/error/failure_mapper.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/network/interceptors/auth_interceptor.dart';
import 'package:intellipilot/core/network/interceptors/client_version_interceptor.dart';
import 'package:intellipilot/core/network/interceptors/etag_interceptor.dart';
import 'package:intellipilot/core/network/interceptors/idempotency_interceptor.dart';
import 'package:intellipilot/core/network/interceptors/logging_interceptor.dart';
import 'package:intellipilot/core/network/interceptors/problem_json_interceptor.dart';
import 'package:intellipilot/core/network/interceptors/refresh_interceptor.dart';
import 'package:intellipilot/core/network/interceptors/request_id_interceptor.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/core/utils/uuid_gen.dart';
import 'package:logger/logger.dart';

/// Thin wrapper around [Dio] that composes the IntelliPilot interceptor
/// pipeline and exposes a small, repository-friendly call surface.
class ApiClient {
  ApiClient({
    required ApiConfig config,
    required UuidGen uuidGen,
    required AccessTokenProvider tokenProvider,
    Logger? logger,
    Dio? dio,
    CookieManager? cookieManager,
    RefreshHook? refreshHook,
  }) : _config = config,
       _dio = dio ?? Dio() {
    _dio
      ..options.baseUrl = config.baseUrl
      ..options.connectTimeout = config.connectTimeout
      ..options.receiveTimeout = config.receiveTimeout
      ..options.sendTimeout = config.sendTimeout
      ..options.responseType = ResponseType.json
      ..options.extra['withCredentials'] = config.withCredentials
      ..options.headers.addAll({
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      });

    if (cookieManager != null) {
      _dio.interceptors.add(cookieManager);
    }
    _dio.interceptors
      ..add(RequestIdInterceptor(uuidGen))
      ..add(const ClientVersionInterceptor())
      ..add(AuthInterceptor(tokenProvider))
      ..add(IdempotencyInterceptor(uuidGen))
      ..add(const EtagInterceptor());
    if (refreshHook != null) {
      _dio.interceptors.add(RefreshInterceptor(refreshHook, dio: _dio));
    }
    _dio.interceptors.add(const ProblemJsonInterceptor());

    if (config.enableRequestLogging) {
      _dio.interceptors.add(HttpLoggingInterceptor(logger ?? Logger()));
    }
  }

  final ApiConfig _config;
  final Dio _dio;

  ApiConfig get config => _config;
  Dio get dio => _dio;

  /// Convenience GET that returns a typed [Result] rather than throwing.
  Future<Result<Response<dynamic>, AppFailure>> get(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        path,
        queryParameters: query,
        cancelToken: cancelToken,
      );
      return Ok(response);
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  /// Convenience POST. Pass [idempotencyKey] to make retries safe.
  Future<Result<Response<dynamic>, AppFailure>> post(
    String path, {
    Object? body,
    String? idempotencyKey,
    String? etag,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        path,
        data: body,
        cancelToken: cancelToken,
        options: Options(
          extra: <String, dynamic>{
            IdempotencyInterceptor.header.toLowerCase(): ?idempotencyKey,
            'idempotency_key': ?idempotencyKey,
            EtagInterceptor.etagExtra: ?etag,
          },
        ),
      );
      return Ok(response);
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }
}
