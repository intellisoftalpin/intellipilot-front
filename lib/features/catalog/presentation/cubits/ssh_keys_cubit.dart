// Underscore-prefixed fields read clearer than initializing formals in the
// public constructor — silence the lint at file scope.
// ignore_for_file: prefer_initializing_formals
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';

sealed class SshKeysState extends Equatable {
  const SshKeysState();
  @override
  List<Object?> get props => const [];
}

final class SshKeysLoading extends SshKeysState {
  const SshKeysLoading();
}

final class SshKeysLoaded extends SshKeysState {
  const SshKeysLoaded({required this.keys, this.busy = false, this.lastError});
  final List<SshKey> keys;
  final bool busy;
  final AppFailure? lastError;

  SshKeysLoaded copyWith({
    List<SshKey>? keys,
    bool? busy,
    AppFailure? lastError,
  }) => SshKeysLoaded(
    keys: keys ?? this.keys,
    busy: busy ?? this.busy,
    lastError: lastError,
  );

  @override
  List<Object?> get props => [keys.map((k) => k.id).toList(), busy, lastError];
}

final class SshKeysLoadFailed extends SshKeysState {
  const SshKeysLoadFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class SshKeysCubit extends Cubit<SshKeysState> {
  SshKeysCubit({required CatalogRepository repo, required this.projectId})
    : _repo = repo,
      super(const SshKeysLoading());

  final CatalogRepository _repo;
  final String projectId;

  Future<void> load() async {
    emit(const SshKeysLoading());
    final res = await _repo.listSshKeys(projectId);
    res.when(
      ok: (k) => emit(SshKeysLoaded(keys: k)),
      err: (f) => emit(SshKeysLoadFailed(f)),
    );
  }

  /// Generate a new key; returns the created key (with its public key) so the
  /// caller can show the deploy-key dialog, or null on failure.
  Future<SshKey?> create({required String name, required bool readOnly}) async {
    final s = state;
    if (s is! SshKeysLoaded) return null;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.createSshKey(
      projectId,
      CreateSshKeyRequest(name: name, readOnly: readOnly),
    );
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return null;
    }
    await load();
    return res.valueOrNull;
  }

  Future<void> update(String keyId, {String? name, bool? readOnly}) async {
    final s = state;
    if (s is! SshKeysLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.updateSshKey(
      projectId,
      keyId,
      UpdateSshKeyRequest(name: name, readOnly: readOnly),
    );
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }

  Future<void> delete(String keyId) async {
    final s = state;
    if (s is! SshKeysLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.deleteSshKey(projectId, keyId);
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }
}
