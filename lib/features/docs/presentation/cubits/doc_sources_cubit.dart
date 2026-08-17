// `_repo` is intentionally kept as a private field for clarity.
// ignore_for_file: prefer_initializing_formals

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:intellipilot/features/docs/data/dtos/doc_dtos.dart';
import 'package:intellipilot/features/docs/domain/docs_repository.dart';

/// The documentation sources of one project.
///
/// Shared by the navigation rail, the wiki overview and the settings tab, so
/// the list is fetched once per screen rather than once per widget that cares.
sealed class DocSourcesState extends Equatable {
  const DocSourcesState();
  @override
  List<Object?> get props => [];
}

class DocSourcesLoading extends DocSourcesState {
  const DocSourcesLoading();
}

class DocSourcesFailed extends DocSourcesState {
  const DocSourcesFailed();
}

class DocSourcesLoaded extends DocSourcesState {
  const DocSourcesLoaded({required this.sources, this.busy = false});

  final List<DocSource> sources;
  final bool busy;

  DocSourcesLoaded copyWith({List<DocSource>? sources, bool? busy}) =>
      DocSourcesLoaded(
        sources: sources ?? this.sources,
        busy: busy ?? this.busy,
      );

  DocSource? byId(String id) {
    for (final s in sources) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  List<Object?> get props => [sources, busy];
}

class DocSourcesCubit extends Cubit<DocSourcesState> {
  DocSourcesCubit({required DocsRepository repo, required this.projectId})
    : _repo = repo,
      super(const DocSourcesLoading());

  final DocsRepository _repo;
  final String projectId;

  Future<void> load() async {
    final res = await _repo.listSources(projectId);
    final items = res.valueOrNull;
    if (isClosed) return;
    emit(
      items == null
          ? const DocSourcesFailed()
          : DocSourcesLoaded(sources: items),
    );
  }

  Future<DocSource?> create(CreateDocSourceRequest body) async {
    final s = state;
    if (s is! DocSourcesLoaded) return null;
    emit(s.copyWith(busy: true));
    final res = await _repo.createSource(projectId, body);
    final created = res.valueOrNull;
    if (isClosed) return created;
    emit(
      created == null
          ? s.copyWith(busy: false)
          : s.copyWith(sources: [...s.sources, created], busy: false),
    );
    return created;
  }

  Future<bool> update(DocSource source, UpdateDocSourceRequest body) async {
    final s = state;
    if (s is! DocSourcesLoaded) return false;
    emit(s.copyWith(busy: true));
    final res = await _repo.updateSource(
      projectId,
      source.id,
      body: body,
      etag: source.etag,
    );
    final updated = res.valueOrNull;
    if (isClosed) return updated != null;
    if (updated == null) {
      emit(s.copyWith(busy: false));
      return false;
    }
    emit(
      s.copyWith(
        sources: s.sources
            .map((x) => x.id == updated.id ? updated : x)
            .toList(),
        busy: false,
      ),
    );
    return true;
  }

  Future<bool> delete(String sourceId) async {
    final s = state;
    if (s is! DocSourcesLoaded) return false;
    emit(s.copyWith(busy: true));
    final res = await _repo.deleteSource(projectId, sourceId);
    if (isClosed) return res.isOk;
    if (res.isErr) {
      emit(s.copyWith(busy: false));
      return false;
    }
    emit(
      s.copyWith(
        sources: s.sources.where((x) => x.id != sourceId).toList(),
        busy: false,
      ),
    );
    return true;
  }

  /// Move [source] to sit between its new neighbours, using the midpoint
  /// ordering the rest of the app uses so a reorder touches one row.
  Future<bool> reorder(DocSource source, double order) =>
      update(source, UpdateDocSourceRequest(order: order));

  /// Ask the server to refresh a source. Returns false when the refresh
  /// failed; the previously cached content stays readable either way.
  Future<bool> sync(String sourceId) async {
    final s = state;
    if (s is! DocSourcesLoaded) return false;
    final res = await _repo.sync(projectId, sourceId);
    final updated = res.valueOrNull;
    if (isClosed) return updated != null;
    if (updated == null) return false;
    emit(
      s.copyWith(
        sources: s.sources
            .map((x) => x.id == updated.id ? updated : x)
            .toList(),
      ),
    );
    return true;
  }
}
