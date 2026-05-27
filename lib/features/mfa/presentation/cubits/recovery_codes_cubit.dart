import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/mfa/domain/mfa_repository.dart';

sealed class RecoveryCodesState extends Equatable {
  const RecoveryCodesState();
  @override
  List<Object?> get props => const [];
}

final class RecoveryIdle extends RecoveryCodesState {
  const RecoveryIdle();
}

final class RecoveryRegenerating extends RecoveryCodesState {
  const RecoveryRegenerating();
}

final class RecoveryRevealed extends RecoveryCodesState {
  const RecoveryRevealed(this.codes);
  final List<String> codes;
  @override
  List<Object?> get props => [codes];
}

final class RecoveryFailed extends RecoveryCodesState {
  const RecoveryFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class RecoveryCodesCubit extends Cubit<RecoveryCodesState> {
  RecoveryCodesCubit(this._repo) : super(const RecoveryIdle());
  final MfaRepository _repo;

  Future<void> regenerate() async {
    emit(const RecoveryRegenerating());
    final res = await _repo.regenerateRecoveryCodes();
    res.when(
      ok: (r) => emit(RecoveryRevealed(r.codes)),
      err: (f) => emit(RecoveryFailed(f)),
    );
  }
}
