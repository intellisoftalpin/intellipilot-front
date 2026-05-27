import 'package:reactive_forms/reactive_forms.dart';

/// Validators that mirror backend `garde` rules so the UI rejects invalid
/// input *before* a round-trip. Server stays authoritative — we never assume
/// validity here.
///
/// `Validators.pattern`/`maxLength` produce runtime instances, so these lists
/// are `final` rather than `const`.
abstract final class AuthValidators {
  /// Email: backend uses `#[garde(email, length(max = 254))]`. Reactive forms
  /// ships an RFC-aligned email validator that is close enough for client UX.
  static final List<Validator<dynamic>> email = [
    Validators.required,
    Validators.email,
    Validators.maxLength(254),
  ];

  /// Username: `^[a-zA-Z0-9_.-]+$`, length 3..64.
  static final List<Validator<dynamic>> username = [
    Validators.required,
    Validators.minLength(3),
    Validators.maxLength(64),
    Validators.pattern(r'^[a-zA-Z0-9_.-]+$'),
  ];

  /// Password (client-side floor of 8 characters; backend reruns zxcvbn).
  static final List<Validator<dynamic>> password = [
    Validators.required,
    Validators.minLength(8),
    Validators.maxLength(1024),
  ];

  /// Permissive single-field length cap (used for full_name).
  static final List<Validator<dynamic>> fullName = [
    Validators.maxLength(256),
  ];

  /// Reset token: 1..512 chars. Trim whitespace at the call site.
  static final List<Validator<dynamic>> resetToken = [
    Validators.required,
    Validators.minLength(1),
    Validators.maxLength(512),
  ];
}
