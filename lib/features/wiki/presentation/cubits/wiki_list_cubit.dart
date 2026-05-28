// `_repo` field kept private for clarity.
// ignore_for_file: prefer_initializing_formals

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:intellipilot/features/wiki/data/dtos/wiki_dtos.dart';
import 'package:intellipilot/features/wiki/domain/wiki_repository.dart';

sealed class WikiListState extends Equatable {
  const WikiListState();
  @override
  List<Object?> get props => [];
}

class WikiListLoading extends WikiListState {
  const WikiListLoading();
}

class WikiListFailed extends WikiListState {
  const WikiListFailed();
}

class WikiListLoaded extends WikiListState {
  const WikiListLoaded({
    required this.pages,
    this.search = '',
    this.busy = false,
  });
  final List<WikiPage> pages;
  final String search;
  final bool busy;

  WikiListLoaded copyWith({
    List<WikiPage>? pages,
    String? search,
    bool? busy,
  }) => WikiListLoaded(
    pages: pages ?? this.pages,
    search: search ?? this.search,
    busy: busy ?? this.busy,
  );

  List<WikiPage> get visible {
    if (search.isEmpty) return pages;
    final needle = search.toLowerCase();
    return pages
        .where(
          (p) =>
              p.title.toLowerCase().contains(needle) ||
              p.slug.toLowerCase().contains(needle),
        )
        .toList();
  }

  @override
  List<Object?> get props => [pages, search, busy];
}

class WikiListCubit extends Cubit<WikiListState> {
  WikiListCubit({required WikiRepository repo, required this.projectId})
    : _repo = repo,
      super(const WikiListLoading());

  final WikiRepository _repo;
  final String projectId;

  Future<void> load() async {
    if (!isClosed) emit(const WikiListLoading());
    final res = await _repo.list(projectId);
    final items = res.valueOrNull;
    if (items == null) {
      if (!isClosed) emit(const WikiListFailed());
      return;
    }
    if (!isClosed) emit(WikiListLoaded(pages: items));
  }

  void setSearch(String s) {
    final cur = state;
    if (cur is! WikiListLoaded) return;
    emit(cur.copyWith(search: s));
  }

  Future<WikiPage?> create(CreateWikiPageRequest body) async {
    final s = state;
    if (s is! WikiListLoaded) return null;
    emit(s.copyWith(busy: true));
    final res = await _repo.create(projectId, body);
    final p = res.valueOrNull;
    if (p == null) {
      if (!isClosed) emit(s.copyWith(busy: false));
      return null;
    }
    if (!isClosed) {
      emit(s.copyWith(pages: [...s.pages, p], busy: false));
    }
    return p;
  }

  Future<bool> delete(WikiPage page) async {
    final s = state;
    if (s is! WikiListLoaded || page.etag == null) return false;
    final res = await _repo.delete(projectId, page.id, etag: page.etag!);
    if (res.valueOrNull == null) return false;
    if (!isClosed) {
      emit(
        s.copyWith(pages: s.pages.where((p) => p.id != page.id).toList()),
      );
    }
    return true;
  }
}
