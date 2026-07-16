import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/profile/data/dtos/personal_token_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';

sealed class PersonalTokenState extends Equatable {
  const PersonalTokenState();
  @override
  List<Object?> get props => [];
}

class PersonalTokenLoading extends PersonalTokenState {
  const PersonalTokenLoading();
}

/// `token == null` means the user has no personal token yet.
class PersonalTokenLoaded extends PersonalTokenState {
  const PersonalTokenLoaded(this.token, {this.busy = false, this.lastError});
  final PersonalTokenDto? token;
  final bool busy;
  final AppFailure? lastError;

  @override
  List<Object?> get props => [token?.id, token?.disabledAt, busy, lastError];
}

class PersonalTokenFailed extends PersonalTokenState {
  const PersonalTokenFailed(this.failure);
  final AppFailure failure;

  @override
  List<Object?> get props => [failure];
}

/// Personal app token lifecycle. Create/reset return the one-time secret to
/// the caller (for the copy dialog) and refresh the masked view; the other
/// actions just refresh.
class PersonalTokenCubit extends Cubit<PersonalTokenState> {
  PersonalTokenCubit(this._repo) : super(const PersonalTokenLoading());

  final ProfileRepository _repo;

  Future<void> load() async {
    emit(const PersonalTokenLoading());
    try {
      final res = await _repo.getPersonalToken();
      res.when(
        ok: (token) => emit(PersonalTokenLoaded(token)),
        err: (f) => emit(PersonalTokenFailed(f)),
      );
    } on Object catch (e) {
      emit(PersonalTokenFailed(UnknownFailure(cause: e)));
    }
  }

  Future<PersonalTokenSecretResult?> create() =>
      _mint(_repo.createPersonalToken);

  Future<PersonalTokenSecretResult?> reset() => _mint(_repo.resetPersonalToken);

  Future<PersonalTokenSecretResult?> _mint(
    Future<Result<PersonalTokenSecretResult, AppFailure>> Function() call,
  ) async {
    final prev = state;
    if (prev is PersonalTokenLoaded) {
      emit(PersonalTokenLoaded(prev.token, busy: true));
    }
    final res = await call();
    return res.when(
      ok: (r) {
        emit(PersonalTokenLoaded(r.token));
        return r;
      },
      err: (f) {
        _surface(prev, f);
        return null;
      },
    );
  }

  Future<void> setDisabled({required bool disabled}) => _act(
    disabled ? _repo.disablePersonalToken : _repo.enablePersonalToken,
  );

  Future<void> delete() => _act(_repo.deletePersonalToken);

  Future<void> _act(
    Future<Result<Unit, AppFailure>> Function() call,
  ) async {
    final prev = state;
    if (prev is PersonalTokenLoaded) {
      emit(PersonalTokenLoaded(prev.token, busy: true));
    }
    final res = await call();
    await res.when(ok: (_) => load(), err: (f) async => _surface(prev, f));
  }

  void _surface(PersonalTokenState prev, AppFailure failure) {
    if (prev is PersonalTokenLoaded) {
      emit(PersonalTokenLoaded(prev.token, lastError: failure));
    } else {
      emit(PersonalTokenFailed(failure));
    }
  }
}
