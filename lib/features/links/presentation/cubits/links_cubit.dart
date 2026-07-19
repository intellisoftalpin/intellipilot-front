// Underscore-prefixed fields are clearer than `{required this._repo}` in
// the public constructor.
// ignore_for_file: prefer_initializing_formals
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/links/data/dtos/link_dtos.dart';
import 'package:intellipilot/features/links/domain/links_repository.dart';

sealed class LinksState extends Equatable {
  const LinksState();
  @override
  List<Object?> get props => const [];
}

final class LinksLoading extends LinksState {
  const LinksLoading();
}

/// Loaded with the resolved + un-resolved partitions. `links` is the raw
/// list from the repository; the UI groups it by display label.
final class LinksLoaded extends LinksState {
  const LinksLoaded({
    required this.links,
    this.busy = false,
    this.lastError,
  });

  final List<EntityLink> links;
  final bool busy;
  final AppFailure? lastError;

  LinksLoaded copyWith({
    List<EntityLink>? links,
    bool? busy,
    AppFailure? lastError,
  }) => LinksLoaded(
    links: links ?? this.links,
    busy: busy ?? this.busy,
    lastError: lastError,
  );

  @override
  List<Object?> get props => [
    links.map((l) => l.id).toList(),
    busy,
    lastError,
  ];
}

final class LinksFailed extends LinksState {
  const LinksFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class LinksCubit extends Cubit<LinksState> {
  LinksCubit({
    required LinksRepository repo,
    required this.projectId,
    required this.kind,
    required this.entityId,
  }) : _repo = repo,
       super(const LinksLoading());

  final LinksRepository _repo;
  final String projectId;
  final EntityKind kind;
  final String entityId;

  Future<void> load() async {
    emit(const LinksLoading());
    final res = await _repo.listFor(projectId, kind, entityId);
    res.when(
      ok: (list) => emit(LinksLoaded(links: list)),
      err: (f) {
        // The backend may not yet expose /links. Surface as an empty list
        // instead of a hard failure so the panel stays usable.
        if (f is NotFoundFailure) {
          emit(const LinksLoaded(links: []));
        } else {
          emit(LinksFailed(f));
        }
      },
    );
  }

  Future<bool> add({
    required EntityKind targetKind,
    required String targetId,
    required LinkType type,
  }) async {
    final s = state;
    if (s is! LinksLoaded) return false;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.create(
      projectId,
      CreateLinkRequest(
        sourceKind: kind,
        sourceId: entityId,
        targetKind: targetKind,
        targetId: targetId,
        type: type,
      ),
    );
    final ok = res.isOk;
    if (ok) {
      await load();
    } else {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
    }
    return ok;
  }

  Future<void> delete(String linkId) async {
    final s = state;
    if (s is! LinksLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.delete(projectId, entityId, linkId);
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }
}
