// `_repo` is intentionally kept as a private field for clarity.
// ignore_for_file: prefer_initializing_formals

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/docs/data/dtos/doc_dtos.dart';
import 'package:intellipilot/features/docs/domain/docs_repository.dart';

/// Why the viewer could not show something.
enum DocViewError {
  /// The source has not finished its first synchronisation. Retryable.
  notReady,

  /// The configured folder does not exist in the repository.
  pathMissing,

  /// The document changed on the server since the editor opened it.
  conflict,

  /// The git host refused the push (protected branch, hook, …).
  rejected,
  notFound,
  generic,
}

sealed class DocViewState extends Equatable {
  const DocViewState();
  @override
  List<Object?> get props => [];
}

class DocViewLoading extends DocViewState {
  const DocViewLoading();
}

class DocViewFailed extends DocViewState {
  const DocViewFailed(this.error, {this.detail});
  final DocViewError error;
  final String? detail;
  @override
  List<Object?> get props => [error, detail];
}

class DocViewLoaded extends DocViewState {
  const DocViewLoaded({
    required this.source,
    required this.tree,
    this.content,
    this.editing = false,
    this.draft = '',
    this.busy = false,
    this.error,
    this.errorDetail,
  });

  final DocSource source;
  final DocTree tree;

  /// Null while the reader is on the folder listing rather than a document.
  final DocContent? content;

  final bool editing;
  final String draft;
  final bool busy;

  /// A non-fatal problem to surface as a banner, leaving content on screen.
  final DocViewError? error;
  final String? errorDetail;

  bool get dirty => editing && content != null && draft != content!.body;

  DocViewLoaded copyWith({
    DocSource? source,
    DocTree? tree,
    DocContent? content,
    bool clearContent = false,
    bool? editing,
    String? draft,
    bool? busy,
    DocViewError? error,
    String? errorDetail,
    bool clearError = false,
  }) => DocViewLoaded(
    source: source ?? this.source,
    tree: tree ?? this.tree,
    content: clearContent ? null : (content ?? this.content),
    editing: editing ?? this.editing,
    draft: draft ?? this.draft,
    busy: busy ?? this.busy,
    error: clearError ? null : (error ?? this.error),
    errorDetail: clearError ? null : (errorDetail ?? this.errorDetail),
  );

  @override
  List<Object?> get props => [
    source,
    tree.commit,
    content?.path,
    content?.blobOid,
    editing,
    draft,
    busy,
    error,
    errorDetail,
  ];
}

class DocViewCubit extends Cubit<DocViewState> {
  DocViewCubit({
    required DocsRepository repo,
    required this.projectId,
    required this.sourceId,
  }) : _repo = repo,
       super(const DocViewLoading());

  final DocsRepository _repo;
  final String projectId;
  final String sourceId;

  /// Load the source, its tree, and a document. When [path] is null the
  /// source's homepage is opened, falling back to the folder listing.
  Future<void> load({String? path}) async {
    if (!isClosed) emit(const DocViewLoading());

    final sourceRes = await _repo.getSource(projectId, sourceId);
    final source = sourceRes.valueOrNull;
    if (source == null) {
      if (!isClosed) emit(const DocViewFailed(DocViewError.notFound));
      return;
    }

    // A web link is served by the browser, not by us: there is no tree to
    // fetch and no document to open, so the viewer goes straight to ready.
    if (source.kind.isWeb) {
      if (!isClosed) {
        emit(
          DocViewLoaded(
            source: source,
            tree: DocTree(sourceId: sourceId, commit: '', entries: const []),
          ),
        );
      }
      return;
    }

    final treeRes = await _repo.tree(projectId, sourceId);
    final tree = treeRes.valueOrNull;
    if (tree == null) {
      if (!isClosed) {
        emit(DocViewFailed(_classify(treeRes.failureOrNull)));
      }
      return;
    }

    final target = path ?? tree.entryPath;
    if (target == null) {
      // No homepage and no requested document: the listing is the landing
      // page, which beats an empty screen.
      if (!isClosed) emit(DocViewLoaded(source: source, tree: tree));
      return;
    }
    final docRes = await _repo.doc(projectId, sourceId, target);
    final content = docRes.valueOrNull;
    if (!isClosed) {
      emit(
        DocViewLoaded(
          source: source,
          tree: tree,
          content: content,
          draft: content?.body ?? '',
          error: content == null ? _classify(docRes.failureOrNull) : null,
        ),
      );
    }
  }

  /// Open another document without refetching the tree.
  Future<void> open(String path) async {
    final s = state;
    if (s is! DocViewLoaded) {
      await load(path: path);
      return;
    }
    if (s.content?.path == path && !s.editing) return;
    emit(s.copyWith(busy: true, clearError: true));
    final res = await _repo.doc(projectId, sourceId, path);
    final content = res.valueOrNull;
    if (isClosed) return;
    emit(
      s.copyWith(
        content: content,
        clearContent: content == null,
        draft: content?.body ?? '',
        editing: false,
        busy: false,
        error: content == null ? _classify(res.failureOrNull) : null,
      ),
    );
  }

  /// Show the folder listing rather than a document.
  void showTree() {
    final s = state;
    if (s is! DocViewLoaded) return;
    emit(s.copyWith(clearContent: true, editing: false, clearError: true));
  }

  void startEditing() {
    final s = state;
    if (s is! DocViewLoaded || s.content == null || !s.content!.canEdit) return;
    emit(s.copyWith(editing: true, draft: s.content!.body, clearError: true));
  }

  void cancelEditing() {
    final s = state;
    if (s is! DocViewLoaded) return;
    emit(
      s.copyWith(
        editing: false,
        draft: s.content?.body ?? '',
        clearError: true,
      ),
    );
  }

  void updateDraft(String value) {
    final s = state;
    if (s is! DocViewLoaded || !s.editing) return;
    emit(s.copyWith(draft: value));
  }

  /// Commit and push the draft. Returns false on any failure, leaving the
  /// editor open with the user's text intact so nothing is lost.
  Future<bool> save({String? message}) async {
    final s = state;
    final content = s is DocViewLoaded ? s.content : null;
    if (s is! DocViewLoaded || content == null) return false;
    emit(s.copyWith(busy: true, clearError: true));
    final res = await _repo.saveDoc(
      projectId,
      sourceId,
      path: content.path,
      content: s.draft,
      etag: content.etag,
      message: message,
    );
    final saved = res.valueOrNull;
    if (isClosed) return saved != null;
    if (saved == null) {
      emit(
        s.copyWith(
          busy: false,
          error: _classify(res.failureOrNull),
          errorDetail: res.failureOrNull?.serverMessage,
        ),
      );
      return false;
    }
    emit(
      s.copyWith(
        content: saved,
        draft: saved.body,
        editing: false,
        busy: false,
        clearError: true,
      ),
    );
    return true;
  }

  /// Refresh from the git remote, then reload the current document so the
  /// reader sees what the refresh brought in.
  Future<bool> sync() async {
    final s = state;
    if (s is! DocViewLoaded) return false;
    emit(s.copyWith(busy: true, clearError: true));
    final res = await _repo.sync(projectId, sourceId);
    if (isClosed) return res.isOk;
    if (res.isErr) {
      emit(
        s.copyWith(
          busy: false,
          error: DocViewError.generic,
          errorDetail: res.failureOrNull?.serverMessage,
        ),
      );
      return false;
    }
    await load(path: s.content?.path);
    return true;
  }

  static DocViewError _classify(AppFailure? failure) =>
      switch (problemCode(failure)) {
        'doc_source_not_ready' => DocViewError.notReady,
        'doc_path_missing' => DocViewError.pathMissing,
        'precondition_failed' => DocViewError.conflict,
        'doc_push_rejected' => DocViewError.rejected,
        'not_found' => DocViewError.notFound,
        _ => DocViewError.generic,
      };
}

/// The backend's stable error code, taken from the problem `type` URI
/// (`https://intellipilot.dev/problems/<code>`). The shared [Problem] model
/// keeps the URI rather than a separate field, so the code is recovered here
/// instead of widening it.
String? problemCode(AppFailure? failure) {
  final type = failure?.problem?.type;
  if (type == null || type.isEmpty) return null;
  final slash = type.lastIndexOf('/');
  return slash == -1 ? type : type.substring(slash + 1);
}
