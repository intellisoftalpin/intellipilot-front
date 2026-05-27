// Underscore-prefixed fields are clearer than `{required this._repo}` in
// the public constructor — silence the lint at file scope.
// ignore_for_file: prefer_initializing_formals
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';

sealed class LabelsState extends Equatable {
  const LabelsState();
  @override
  List<Object?> get props => const [];
}

final class LabelsLoading extends LabelsState {
  const LabelsLoading();
}

final class LabelsLoaded extends LabelsState {
  const LabelsLoaded({
    required this.labels,
    this.busy = false,
    this.lastError,
  });
  final List<Label> labels;
  final bool busy;
  final AppFailure? lastError;

  LabelsLoaded copyWith({
    List<Label>? labels,
    bool? busy,
    AppFailure? lastError,
  }) => LabelsLoaded(
    labels: labels ?? this.labels,
    busy: busy ?? this.busy,
    lastError: lastError,
  );

  @override
  List<Object?> get props =>
      [labels.map((l) => l.id).toList(), busy, lastError];
}

final class LabelsLoadFailed extends LabelsState {
  const LabelsLoadFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class LabelsCubit extends Cubit<LabelsState> {
  LabelsCubit({required CatalogRepository repo, required this.projectId})
    : _repo = repo,
      super(const LabelsLoading());

  final CatalogRepository _repo;
  final String projectId;

  Future<void> load() async {
    emit(const LabelsLoading());
    final res = await _repo.listLabels(projectId);
    res.when(
      ok: (l) => emit(LabelsLoaded(labels: l)),
      err: (f) => emit(LabelsLoadFailed(f)),
    );
  }

  Future<void> create({required String name, required String color}) async {
    final s = state;
    if (s is! LabelsLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.createLabel(
      projectId,
      CreateLabelRequest(name: name, color: color),
    );
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }

  Future<void> update(
    String labelId, {
    String? name,
    String? color,
  }) async {
    final s = state;
    if (s is! LabelsLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.updateLabel(
      projectId,
      labelId,
      UpdateLabelRequest(name: name, color: color),
    );
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }

  Future<void> delete(String labelId) async {
    final s = state;
    if (s is! LabelsLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.deleteLabel(projectId, labelId);
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }
}
