// Underscore-prefixed fields are clearer than `{required this._repo}` in
// the public constructor — silence the lint at file scope.
// ignore_for_file: prefer_initializing_formals
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';

sealed class TaxonomyState extends Equatable {
  const TaxonomyState();
  @override
  List<Object?> get props => const [];
}

final class TaxonomyLoading extends TaxonomyState {
  const TaxonomyLoading();
}

final class TaxonomyLoaded extends TaxonomyState {
  const TaxonomyLoaded({
    required this.items,
    this.busy = false,
    this.lastError,
  });
  final List<TaxonomyItem> items;
  final bool busy;
  final AppFailure? lastError;

  TaxonomyLoaded copyWith({
    List<TaxonomyItem>? items,
    bool? busy,
    AppFailure? lastError,
  }) => TaxonomyLoaded(
    items: items ?? this.items,
    busy: busy ?? this.busy,
    lastError: lastError,
  );

  @override
  List<Object?> get props => [items.map((i) => i.id).toList(), busy, lastError];
}

final class TaxonomyLoadFailed extends TaxonomyState {
  const TaxonomyLoadFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class TaxonomyCubit extends Cubit<TaxonomyState> {
  TaxonomyCubit({
    required CatalogRepository repo,
    required this.projectId,
    required this.kind,
  }) : _repo = repo,
       super(const TaxonomyLoading());

  final CatalogRepository _repo;
  final String projectId;
  final TaxonomyKind kind;

  Future<void> load() async {
    emit(const TaxonomyLoading());
    final res = await _repo.listTaxonomy(projectId, kind);
    res.when(
      ok: (items) => emit(TaxonomyLoaded(items: items)),
      err: (f) => emit(TaxonomyLoadFailed(f)),
    );
  }

  Future<void> create(CreateTaxonomyItemRequest body) async {
    final s = state;
    if (s is! TaxonomyLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.createTaxonomyItem(projectId, kind, body);
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }

  Future<void> update(String itemId, UpdateTaxonomyItemRequest body) async {
    final s = state;
    if (s is! TaxonomyLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.updateTaxonomyItem(projectId, kind, itemId, body);
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }

  Future<void> delete(String itemId) async {
    final s = state;
    if (s is! TaxonomyLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.deleteTaxonomyItem(projectId, kind, itemId);
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }

  /// Reorder by moving [movedId] to [newIndex] in the current list and
  /// dispatching a single `move` call with the appropriate before/after id.
  /// Optimistically updates the list ordering before the round-trip.
  Future<void> reorder(String movedId, int newIndex) async {
    final s = state;
    if (s is! TaxonomyLoaded) return;
    final list = List.of(s.items);
    final oldIndex = list.indexWhere((i) => i.id == movedId);
    if (oldIndex < 0 || oldIndex == newIndex) return;

    final moved = list.removeAt(oldIndex);
    final insertAt = newIndex > oldIndex ? newIndex - 1 : newIndex;
    list.insert(insertAt, moved);
    emit(s.copyWith(items: list, busy: true, lastError: null));

    // Compute neighbour anchors in the new order.
    String? beforeId;
    String? afterId;
    final movedPos = list.indexWhere((i) => i.id == movedId);
    if (movedPos > 0) afterId = list[movedPos - 1].id;
    if (movedPos < list.length - 1) beforeId = list[movedPos + 1].id;

    final res = await _repo.moveTaxonomyItem(
      projectId,
      kind,
      movedId,
      MoveTaxonomyItemRequest(beforeId: beforeId, afterId: afterId),
    );
    if (res.isErr) {
      // Roll back via a fresh fetch — server is the truth.
      await load();
      return;
    }
    await load();
  }
}
