import 'package:intellipilot/core/error/problem.dart';

/// Typed failures surfaced across layers. UI maps these to localized strings
/// and decides whether to show an inline form error, a full-screen error
/// view, or a transient snackbar.
sealed class AppFailure {
  const AppFailure({this.problem, this.cause});

  /// Original Problem+JSON from the backend, when available.
  final Problem? problem;

  /// Underlying cause (DioException, FormatException, etc.) for debugging.
  final Object? cause;

  String get debugLabel;

  @override
  String toString() => 'AppFailure.$debugLabel(problem: $problem)';
}

extension AppFailureMessage on AppFailure {
  /// The backend's human-readable reason (Problem `detail`, else `title`),
  /// when present — e.g. "could not write the icon image to storage". UI code
  /// should fall back to a localized string when this is null.
  String? get serverMessage {
    final d = problem?.detail;
    if (d != null && d.isNotEmpty) return d;
    final tt = problem?.title;
    if (tt != null && tt.isNotEmpty) return tt;
    return null;
  }
}

final class NetworkFailure extends AppFailure {
  const NetworkFailure({super.cause}) : super(problem: null);
  @override
  String get debugLabel => 'network';
}

final class UnauthorizedFailure extends AppFailure {
  const UnauthorizedFailure({super.problem, super.cause});
  @override
  String get debugLabel => 'unauthorized';
}

final class ForbiddenFailure extends AppFailure {
  const ForbiddenFailure({super.problem, super.cause});
  @override
  String get debugLabel => 'forbidden';
}

final class NotFoundFailure extends AppFailure {
  const NotFoundFailure({super.problem, super.cause});
  @override
  String get debugLabel => 'notFound';
}

final class ValidationFailure extends AppFailure {
  const ValidationFailure({
    required this.fieldErrors,
    super.problem,
    super.cause,
  });
  final List<FieldError> fieldErrors;
  @override
  String get debugLabel => 'validation(${fieldErrors.length} fields)';
}

final class ConflictFailure extends AppFailure {
  const ConflictFailure({super.problem, super.cause});
  @override
  String get debugLabel => 'conflict';
}

final class RateLimitedFailure extends AppFailure {
  const RateLimitedFailure({this.retryAfter, super.problem, super.cause});
  final Duration? retryAfter;
  @override
  String get debugLabel => 'rateLimited(retryAfter: $retryAfter)';
}

final class ServerFailure extends AppFailure {
  const ServerFailure({super.problem, super.cause});
  @override
  String get debugLabel => 'server';
}

final class UnknownFailure extends AppFailure {
  const UnknownFailure({super.problem, super.cause});
  @override
  String get debugLabel => 'unknown';
}
