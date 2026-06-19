// Underscore-prefixed fields are clearer than `{required this._repo}` in
// the public constructor — silence the lint at file scope.
// ignore_for_file: prefer_initializing_formals
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';

sealed class ComponentsState extends Equatable {
  const ComponentsState();
  @override
  List<Object?> get props => const [];
}

final class ComponentsLoading extends ComponentsState {
  const ComponentsLoading();
}

final class ComponentsLoaded extends ComponentsState {
  const ComponentsLoaded({
    required this.components,
    this.busy = false,
    this.lastError,
  });
  final List<Component> components;
  final bool busy;
  final AppFailure? lastError;

  ComponentsLoaded copyWith({
    List<Component>? components,
    bool? busy,
    AppFailure? lastError,
  }) => ComponentsLoaded(
    components: components ?? this.components,
    busy: busy ?? this.busy,
    lastError: lastError,
  );

  @override
  List<Object?> get props =>
      [components.map((c) => c.id).toList(), busy, lastError];
}

final class ComponentsLoadFailed extends ComponentsState {
  const ComponentsLoadFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class ComponentsCubit extends Cubit<ComponentsState> {
  ComponentsCubit({required CatalogRepository repo, required this.projectId})
    : _repo = repo,
      super(const ComponentsLoading());

  final CatalogRepository _repo;
  final String projectId;

  Future<void> load() async {
    emit(const ComponentsLoading());
    final res = await _repo.listComponents(projectId);
    res.when(
      ok: (c) => emit(ComponentsLoaded(components: c)),
      err: (f) => emit(ComponentsLoadFailed(f)),
    );
  }

  Future<void> create({required String name, required String color}) async {
    final s = state;
    if (s is! ComponentsLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.createComponent(
      projectId,
      CreateComponentRequest(name: name, color: color),
    );
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }

  Future<void> update(
    String componentId, {
    String? name,
    String? color,
  }) async {
    final s = state;
    if (s is! ComponentsLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.updateComponent(
      projectId,
      componentId,
      UpdateComponentRequest(name: name, color: color),
    );
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }

  Future<void> delete(String componentId) async {
    final s = state;
    if (s is! ComponentsLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.deleteComponent(projectId, componentId);
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }
}
