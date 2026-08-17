// `_repo` is intentionally kept as a private field for clarity.
// ignore_for_file: prefer_initializing_formals

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/docs/data/dtos/doc_dtos.dart';
import 'package:intellipilot/features/docs/domain/docs_repository.dart';

/// The caller's own write key for one project.
///
/// A key is what makes an edit attributable: the commit is authored as the
/// user and pushed with their credential. There is deliberately no way to
/// manage anyone else's.
class DocKeyState extends Equatable {
  const DocKeyState({
    this.key,
    this.loading = true,
    this.busy = false,
    this.error,
  });

  /// Null when the user has not registered one.
  final DocUserKey? key;
  final bool loading;
  final bool busy;

  /// Server-provided reason the last attempt failed, e.g. an unusable key.
  final String? error;

  bool get hasKey => key != null;

  DocKeyState copyWith({
    DocUserKey? key,
    bool clearKey = false,
    bool? loading,
    bool? busy,
    String? error,
    bool clearError = false,
  }) => DocKeyState(
    key: clearKey ? null : (key ?? this.key),
    loading: loading ?? this.loading,
    busy: busy ?? this.busy,
    error: clearError ? null : (error ?? this.error),
  );

  @override
  List<Object?> get props => [key?.fingerprint, loading, busy, error];
}

class DocKeyCubit extends Cubit<DocKeyState> {
  DocKeyCubit({required DocsRepository repo, required this.projectId})
    : _repo = repo,
      super(const DocKeyState());

  final DocsRepository _repo;
  final String projectId;

  Future<void> load() async {
    final res = await _repo.myKey(projectId);
    if (isClosed) return;
    emit(
      res.when(
        ok: (k) => DocKeyState(key: k, loading: false),
        err: (_) => const DocKeyState(loading: false),
      ),
    );
  }

  /// Generate a keypair, or adopt [privateKey] when the user supplies one.
  /// Either way only the public half ever comes back.
  Future<bool> register({String? privateKey}) async {
    emit(state.copyWith(busy: true, clearError: true));
    final res = await _repo.registerMyKey(projectId, privateKey: privateKey);
    if (isClosed) return res.isOk;
    return res.when(
      ok: (k) {
        emit(DocKeyState(key: k, loading: false));
        return true;
      },
      err: (f) {
        emit(state.copyWith(busy: false, error: f.serverMessage));
        return false;
      },
    );
  }

  Future<bool> remove() async {
    emit(state.copyWith(busy: true, clearError: true));
    final res = await _repo.deleteMyKey(projectId);
    if (isClosed) return res.isOk;
    if (res.isErr) {
      emit(state.copyWith(busy: false));
      return false;
    }
    emit(const DocKeyState(loading: false));
    return true;
  }
}
