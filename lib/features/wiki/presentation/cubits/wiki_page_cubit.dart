// `_repo` field kept private for clarity.
// ignore_for_file: prefer_initializing_formals

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:intellipilot/features/wiki/data/dtos/wiki_dtos.dart';
import 'package:intellipilot/features/wiki/domain/wiki_repository.dart';

sealed class WikiPageState extends Equatable {
  const WikiPageState();
  @override
  List<Object?> get props => [];
}

class WikiPageLoading extends WikiPageState {
  const WikiPageLoading();
}

class WikiPageFailed extends WikiPageState {
  const WikiPageFailed();
}

class WikiPageLoaded extends WikiPageState {
  const WikiPageLoaded({
    required this.page,
    this.editing = false,
    this.draftBody,
    this.draftTitle,
    this.busy = false,
    this.conflict = false,
  });

  final WikiPage page;
  final bool editing;

  /// Current values in the editor (separate from `page` so save-failure
  /// keeps the user's edits intact).
  final String? draftBody;
  final String? draftTitle;
  final bool busy;

  /// True when a PATCH returned 412 — the server changed under us.
  final bool conflict;

  WikiPageLoaded copyWith({
    WikiPage? page,
    bool? editing,
    String? draftBody,
    String? draftTitle,
    bool? busy,
    bool? conflict,
  }) => WikiPageLoaded(
    page: page ?? this.page,
    editing: editing ?? this.editing,
    draftBody: draftBody ?? this.draftBody,
    draftTitle: draftTitle ?? this.draftTitle,
    busy: busy ?? this.busy,
    conflict: conflict ?? this.conflict,
  );

  @override
  List<Object?> get props => [
    page,
    editing,
    draftBody,
    draftTitle,
    busy,
    conflict,
  ];
}

class WikiPageCubit extends Cubit<WikiPageState> {
  WikiPageCubit({
    required WikiRepository repo,
    required this.projectId,
    required this.pageId,
  }) : _repo = repo,
       super(const WikiPageLoading());

  final WikiRepository _repo;
  final String projectId;
  final String pageId;

  Future<void> load() async {
    if (!isClosed) emit(const WikiPageLoading());
    final res = await _repo.get(projectId, pageId);
    final p = res.valueOrNull;
    if (p == null) {
      if (!isClosed) emit(const WikiPageFailed());
      return;
    }
    if (!isClosed) emit(WikiPageLoaded(page: p));
  }

  void startEditing() {
    final s = state;
    if (s is! WikiPageLoaded) return;
    emit(
      s.copyWith(
        editing: true,
        draftBody: s.page.body,
        draftTitle: s.page.title,
        conflict: false,
      ),
    );
  }

  void cancelEditing() {
    final s = state;
    if (s is! WikiPageLoaded) return;
    emit(
      WikiPageLoaded(page: s.page),
    );
  }

  void setDraftBody(String body) {
    final s = state;
    if (s is! WikiPageLoaded) return;
    emit(s.copyWith(draftBody: body));
  }

  void setDraftTitle(String title) {
    final s = state;
    if (s is! WikiPageLoaded) return;
    emit(s.copyWith(draftTitle: title));
  }

  Future<bool> save() async {
    final s = state;
    if (s is! WikiPageLoaded || !s.editing || s.page.etag == null) {
      return false;
    }
    emit(s.copyWith(busy: true, conflict: false));
    final res = await _repo.update(
      projectId,
      pageId,
      body: UpdateWikiPageRequest(
        title: s.draftTitle ?? s.page.title,
        body: s.draftBody ?? s.page.body,
      ),
      etag: s.page.etag!,
    );
    final p = res.valueOrNull;
    if (p == null) {
      // Try to detect conflict by re-fetching: if the version moved on us,
      // surface the conflict banner so the user can choose to overwrite.
      final fresh = await _repo.get(projectId, pageId);
      final freshPage = fresh.valueOrNull;
      if (freshPage != null && freshPage.version != s.page.version) {
        if (!isClosed) {
          emit(s.copyWith(page: freshPage, busy: false, conflict: true));
        }
      } else {
        if (!isClosed) emit(s.copyWith(busy: false));
      }
      return false;
    }
    if (!isClosed) {
      emit(WikiPageLoaded(page: p));
    }
    return true;
  }

  /// Overwrite the page with the current draft, ignoring conflict — used by
  /// the "overwrite" option on the conflict banner. Requires the *new*
  /// (post-conflict) etag to land cleanly.
  Future<bool> overwrite() async {
    final s = state;
    if (s is! WikiPageLoaded || !s.editing || s.page.etag == null) {
      return false;
    }
    emit(s.copyWith(busy: true));
    final res = await _repo.update(
      projectId,
      pageId,
      body: UpdateWikiPageRequest(
        title: s.draftTitle ?? s.page.title,
        body: s.draftBody ?? s.page.body,
      ),
      etag: s.page.etag!,
    );
    final p = res.valueOrNull;
    if (p == null) {
      if (!isClosed) emit(s.copyWith(busy: false));
      return false;
    }
    if (!isClosed) emit(WikiPageLoaded(page: p));
    return true;
  }

  Future<bool> restoreRevision(int rev) async {
    final s = state;
    if (s is! WikiPageLoaded) return false;
    emit(s.copyWith(busy: true));
    final res = await _repo.restore(projectId, pageId, rev);
    final p = res.valueOrNull;
    if (p == null) {
      if (!isClosed) emit(s.copyWith(busy: false));
      return false;
    }
    if (!isClosed) emit(WikiPageLoaded(page: p));
    return true;
  }
}
