/// RFC 9457 Problem+JSON document returned by the backend on non-2xx
/// responses. The backend always populates `type`, `title`, and `status`;
/// `detail`, `instance`, and `errors` are optional.
class Problem {
  const Problem({
    required this.type,
    required this.title,
    required this.status,
    this.detail,
    this.instance,
    this.requestId,
    this.errors = const <FieldError>[],
    this.retryAfter,
  });

  factory Problem.fromJson(Map<String, dynamic> json) {
    final rawErrors = json['errors'];
    final fieldErrors = <FieldError>[];
    if (rawErrors is List) {
      for (final e in rawErrors) {
        if (e is Map<String, dynamic>) {
          fieldErrors.add(FieldError.fromJson(e));
        }
      }
    }
    final retryAfterRaw = json['retry_after'];
    Duration? retryAfter;
    if (retryAfterRaw is num) {
      retryAfter = Duration(seconds: retryAfterRaw.toInt());
    } else if (retryAfterRaw is String) {
      final parsed = int.tryParse(retryAfterRaw);
      if (parsed != null) retryAfter = Duration(seconds: parsed);
    }
    return Problem(
      type: (json['type'] as String?) ?? 'about:blank',
      title: (json['title'] as String?) ?? 'Error',
      status: (json['status'] as num?)?.toInt() ?? 0,
      detail: json['detail'] as String?,
      instance: json['instance'] as String?,
      requestId: json['request_id'] as String?,
      errors: fieldErrors,
      retryAfter: retryAfter,
    );
  }

  /// Best-effort fallback when the body isn't valid Problem+JSON.
  factory Problem.fallback({required int status, String? body}) {
    return Problem(
      type: 'about:blank',
      title: body == null || body.isEmpty ? 'HTTP $status' : body,
      status: status,
    );
  }

  final String type;
  final String title;
  final int status;
  final String? detail;
  final String? instance;
  final String? requestId;
  final List<FieldError> errors;
  final Duration? retryAfter;

  @override
  String toString() => 'Problem($status $type — $title)';
}

/// One entry in `errors[]`. Codes mirror backend `garde` constraint names:
/// `required`, `length`, `pattern`, `email`, …
class FieldError {
  const FieldError({required this.field, required this.code, this.message});

  factory FieldError.fromJson(Map<String, dynamic> json) => FieldError(
    field: (json['field'] as String?) ?? '',
    code: (json['code'] as String?) ?? 'invalid',
    message: json['message'] as String?,
  );

  final String field;
  final String code;
  final String? message;

  @override
  String toString() =>
      'FieldError($field: $code${message == null ? '' : ' — $message'})';
}
