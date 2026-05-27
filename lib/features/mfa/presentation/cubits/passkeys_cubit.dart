import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/mfa/data/dtos/mfa_dtos.dart';
import 'package:intellipilot/features/mfa/data/passkey_service.dart';
import 'package:intellipilot/features/mfa/domain/mfa_repository.dart';

sealed class PasskeysState extends Equatable {
  const PasskeysState();
  @override
  List<Object?> get props => const [];
}

final class PasskeysLoading extends PasskeysState {
  const PasskeysLoading();
}

final class PasskeysLoaded extends PasskeysState {
  const PasskeysLoaded({
    required this.items,
    this.lastError,
    this.busy = false,
  });
  final List<PasskeyListItem> items;
  final AppFailure? lastError;
  final bool busy;

  PasskeysLoaded copyWith({
    List<PasskeyListItem>? items,
    AppFailure? lastError,
    bool? busy,
  }) => PasskeysLoaded(
    items: items ?? this.items,
    lastError: lastError,
    busy: busy ?? this.busy,
  );

  @override
  List<Object?> get props => [items.map((e) => e.id).toList(), lastError, busy];
}

final class PasskeysLoadFailed extends PasskeysState {
  const PasskeysLoadFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

// Underscore-prefixed fields are clearer than `{required this._repo}` here;
// silence the lint at file scope.
// ignore_for_file: prefer_initializing_formals
class PasskeysCubit extends Cubit<PasskeysState> {
  PasskeysCubit({
    required MfaRepository repo,
    required PasskeyService passkeys,
  }) : _repo = repo,
       _passkeys = passkeys,
       super(const PasskeysLoading());

  final MfaRepository _repo;
  final PasskeyService _passkeys;

  bool get isSupported => _passkeys.isSupported;

  Future<void> load() async {
    emit(const PasskeysLoading());
    final res = await _repo.listPasskeys();
    res.when(
      ok: (items) => emit(PasskeysLoaded(items: items)),
      err: (f) => emit(PasskeysLoadFailed(f)),
    );
  }

  Future<void> add({String? nickname}) async {
    final current = state;
    if (current is! PasskeysLoaded) return;
    if (!_passkeys.isSupported) {
      emit(current.copyWith(lastError: const UnknownFailure()));
      return;
    }
    emit(current.copyWith(busy: true));

    final start = await _repo.startPasskeyRegistration();
    final fail = start.failureOrNull;
    if (fail != null) {
      emit(current.copyWith(lastError: fail, busy: false));
      return;
    }
    final ceremony = start.valueOrNull!;

    Map<String, dynamic> credential;
    try {
      credential = await _passkeys.register(ceremony.options);
    } on PasskeyCeremonyError catch (e) {
      emit(current.copyWith(lastError: UnknownFailure(cause: e), busy: false));
      return;
    }

    final finish = await _repo.finishPasskeyRegistration(
      stateId: ceremony.stateId,
      credential: credential,
      nickname: nickname,
    );
    await finish.when(
      ok: (_) async => load(),
      err: (f) async => emit(current.copyWith(lastError: f, busy: false)),
    );
  }

  Future<void> remove(String id) async {
    final current = state;
    if (current is! PasskeysLoaded) return;
    emit(current.copyWith(busy: true));
    final res = await _repo.deletePasskey(id);
    await res.when(
      ok: (_) async => load(),
      err: (f) async => emit(current.copyWith(lastError: f, busy: false)),
    );
  }
}
