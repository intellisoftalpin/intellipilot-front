import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/mfa/data/dtos/mfa_dtos.dart';
import 'package:intellipilot/features/mfa/domain/mfa_repository.dart';

sealed class TotpSetupState extends Equatable {
  const TotpSetupState();
  @override
  List<Object?> get props => const [];
}

final class TotpIdle extends TotpSetupState {
  const TotpIdle();
}

final class TotpStarting extends TotpSetupState {
  const TotpStarting();
}

final class TotpAwaitingCode extends TotpSetupState {
  const TotpAwaitingCode(this.start);
  final TotpStartResponse start;
  @override
  List<Object?> get props => [start.secretBase32, start.provisioningUri];
}

final class TotpConfirming extends TotpSetupState {
  const TotpConfirming(this.start);
  final TotpStartResponse start;
  @override
  List<Object?> get props => [start.secretBase32];
}

final class TotpEnabled extends TotpSetupState {
  const TotpEnabled(this.recoveryCodes);
  final List<String> recoveryCodes;
  @override
  List<Object?> get props => [recoveryCodes];
}

final class TotpFailed extends TotpSetupState {
  const TotpFailed({required this.failure, this.start});
  final AppFailure failure;
  final TotpStartResponse? start;
  @override
  List<Object?> get props => [failure, start?.secretBase32];
}

class TotpSetupCubit extends Cubit<TotpSetupState> {
  TotpSetupCubit(this._repo) : super(const TotpIdle());
  final MfaRepository _repo;

  Future<void> start() async {
    emit(const TotpStarting());
    final res = await _repo.startTotp();
    res.when(
      ok: (start) => emit(TotpAwaitingCode(start)),
      err: (f) => emit(TotpFailed(failure: f)),
    );
  }

  Future<void> confirm(String code) async {
    final s = state;
    if (s is! TotpAwaitingCode && s is! TotpFailed) return;
    final start = s is TotpAwaitingCode ? s.start : (s as TotpFailed).start;
    if (start == null) return;
    emit(TotpConfirming(start));
    final res = await _repo.confirmTotp(code);
    res.when(
      ok: (r) => emit(TotpEnabled(r.codes)),
      err: (f) => emit(TotpFailed(failure: f, start: start)),
    );
  }
}
