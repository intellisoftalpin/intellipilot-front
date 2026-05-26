/// A pragmatic Result type for layer-to-layer transport.
///
/// Repositories return `Result<T, AppFailure>` rather than throwing, so
/// failure types are visible at the call site and pattern matching covers
/// every branch. Exceptions remain confined to the HTTP layer.
sealed class Result<T, F> {
  const Result();

  /// Run [onOk] if this is an [Ok], otherwise [onErr].
  R when<R>({
    required R Function(T value) ok,
    required R Function(F failure) err,
  }) {
    final self = this;
    if (self is Ok<T, F>) return ok(self.value);
    if (self is Err<T, F>) return err(self.failure);
    throw StateError('Unreachable Result subtype: $self');
  }

  bool get isOk => this is Ok<T, F>;
  bool get isErr => this is Err<T, F>;

  T? get valueOrNull => this is Ok<T, F> ? (this as Ok<T, F>).value : null;
  F? get failureOrNull =>
      this is Err<T, F> ? (this as Err<T, F>).failure : null;
}

final class Ok<T, F> extends Result<T, F> {
  const Ok(this.value);
  final T value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Ok<T, F> && other.value == value);

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Ok($value)';
}

final class Err<T, F> extends Result<T, F> {
  const Err(this.failure);
  final F failure;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Err<T, F> && other.failure == failure);

  @override
  int get hashCode => failure.hashCode;

  @override
  String toString() => 'Err($failure)';
}

/// Marker type used when a method has no meaningful success value.
final class Unit {
  const Unit._();
  static const Unit instance = Unit._();
}
