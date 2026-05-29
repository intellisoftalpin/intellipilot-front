// Underscore-prefixed fields are clearer than `{required this._repo}` in
// the public constructor — silence the lint at file scope.
// ignore_for_file: prefer_initializing_formals
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';

sealed class BacklogState extends Equatable {
  const BacklogState();
  @override
  List<Object?> get props => const [];
}

final class BacklogLoading extends BacklogState {
  const BacklogLoading();
}

final class BacklogLoaded extends BacklogState {
  const BacklogLoaded({
    required this.epics,
    required this.userStories,
    required this.statuses,
    required this.points,
    this.search = '',
    this.statusFilter,
    this.busy = false,
    this.lastError,
    this.staleData = false,
  });

  final List<Epic> epics;
  final List<UserStory> userStories;

  /// `us_status` taxonomy items.
  final List<TaxonomyItem> statuses;

  /// `point` taxonomy items.
  final List<TaxonomyItem> points;
  final String search;
  final String? statusFilter;
  final bool busy;
  final AppFailure? lastError;

  /// Set when a 409/412 conflict was returned — the UI shows a "data has
  /// changed, refresh" banner and the cubit auto-reloads.
  final bool staleData;

  BacklogLoaded copyWith({
    List<Epic>? epics,
    List<UserStory>? userStories,
    List<TaxonomyItem>? statuses,
    List<TaxonomyItem>? points,
    String? search,
    Object? statusFilter = _absent,
    bool? busy,
    AppFailure? lastError,
    bool? staleData,
  }) => BacklogLoaded(
    epics: epics ?? this.epics,
    userStories: userStories ?? this.userStories,
    statuses: statuses ?? this.statuses,
    points: points ?? this.points,
    search: search ?? this.search,
    statusFilter:
        statusFilter == _absent ? this.statusFilter : statusFilter as String?,
    busy: busy ?? this.busy,
    lastError: lastError,
    staleData: staleData ?? false,
  );

  static const _absent = Object();

  /// User stories matching the current search/status filters, grouped by
  /// `epicId` (null bucket goes first). Each list inside a group is sorted by
  /// the backend `order` ascending.
  Map<String?, List<UserStory>> get grouped {
    final filtered = userStories.where((us) {
      if (statusFilter != null && us.statusId != statusFilter) return false;
      if (search.trim().isEmpty) return true;
      final q = search.toLowerCase();
      return us.subject.toLowerCase().contains(q) ||
          us.description.toLowerCase().contains(q) ||
          'us-${us.reference}'.contains(q);
    }).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final byEpic = <String?, List<UserStory>>{null: []};
    for (final epic in epics) {
      byEpic[epic.id] = [];
    }
    for (final us in filtered) {
      byEpic.putIfAbsent(us.epicId, () => []).add(us);
    }
    return byEpic;
  }

  @override
  List<Object?> get props => [
    epics.map((e) => e.id).toList(),
    userStories.map((u) => u.id).toList(),
    statuses.map((s) => s.id).toList(),
    points.map((p) => p.id).toList(),
    search,
    statusFilter,
    busy,
    lastError,
    staleData,
  ];
}

final class BacklogLoadFailed extends BacklogState {
  const BacklogLoadFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class BacklogCubit extends Cubit<BacklogState> {
  BacklogCubit({
    required BacklogRepository repo,
    required CatalogRepository catalog,
    required this.projectId,
  }) : _repo = repo,
       _catalog = catalog,
       super(const BacklogLoading());

  final BacklogRepository _repo;
  final CatalogRepository _catalog;
  final String projectId;

  Future<void> load() async {
    emit(const BacklogLoading());
    final epicsRes = await _repo.listEpics(projectId);
    final usRes = await _repo.listUserStories(projectId);
    final statusesRes =
        await _catalog.listTaxonomy(projectId, TaxonomyKind.usStatus);
    final pointsRes =
        await _catalog.listTaxonomy(projectId, TaxonomyKind.point);

    final fail = epicsRes.failureOrNull ??
        usRes.failureOrNull ??
        statusesRes.failureOrNull ??
        pointsRes.failureOrNull;
    if (fail != null) {
      emit(BacklogLoadFailed(fail));
      return;
    }
    emit(
      BacklogLoaded(
        epics: epicsRes.valueOrNull!,
        userStories: usRes.valueOrNull!,
        statuses: statusesRes.valueOrNull!,
        points: pointsRes.valueOrNull!,
      ),
    );
  }

  void setSearch(String q) {
    final s = state;
    if (s is BacklogLoaded) emit(s.copyWith(search: q, lastError: null));
  }

  void setStatusFilter(String? id) {
    final s = state;
    if (s is BacklogLoaded) {
      emit(s.copyWith(statusFilter: id, lastError: null));
    }
  }

  Future<void> createEpic(CreateEpicRequest body) async {
    final s = state;
    if (s is! BacklogLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.createEpic(projectId, body);
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }

  Future<void> createUserStory(CreateUserStoryRequest body) async {
    final s = state;
    if (s is! BacklogLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.createUserStory(projectId, body);
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }

  /// Quick status toggle from a US row. Loads the latest ETag via GET so the
  /// PATCH carries the correct `If-Match`.
  Future<void> setUserStoryStatus(String userStoryId, String? statusId) async {
    final s = state;
    if (s is! BacklogLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final got = await _repo.getUserStory(projectId, userStoryId);
    final fresh = got.valueOrNull;
    if (fresh == null) {
      emit(s.copyWith(busy: false, lastError: got.failureOrNull));
      return;
    }
    final res = await _repo.updateUserStory(
      projectId,
      userStoryId,
      body: UpdateUserStoryRequest(statusId: statusId),
      etag: fresh.etag ?? '',
    );
    if (res.isErr) {
      final f = res.failureOrNull;
      final stale = f is ConflictFailure;
      emit(s.copyWith(busy: false, lastError: f, staleData: stale));
      if (stale) await load();
      return;
    }
    await load();
  }

  /// Drag-and-drop on the backlog page: re-parent a user story under a
  /// different epic (or the unparented bucket when `epicId` is null).
  /// Optimistic — patches the local list before the PATCH round-trips,
  /// then `load()` reconciles. On 409 rolls back via the standard
  /// stale-data path.
  Future<void> moveUserStoryToEpic(String storyId, String? epicId) async {
    final s = state;
    if (s is! BacklogLoaded) return;
    final idx = s.userStories.indexWhere((u) => u.id == storyId);
    if (idx < 0) return;
    final current = s.userStories[idx];
    if (current.epicId == epicId) return;
    final patched = UserStory(
      id: current.id,
      projectId: current.projectId,
      reference: current.reference,
      subject: current.subject,
      description: current.description,
      order: current.order,
      version: current.version,
      createdAt: current.createdAt,
      modifiedAt: current.modifiedAt,
      statusId: current.statusId,
      epicId: epicId,
      milestoneId: current.milestoneId,
      pointsId: current.pointsId,
      ownerId: current.ownerId,
      assignedTo: current.assignedTo,
      etag: current.etag,
    );
    final updated = List<UserStory>.of(s.userStories)..[idx] = patched;
    emit(s.copyWith(userStories: updated, busy: true, lastError: null));

    final got = await _repo.getUserStory(projectId, storyId);
    final fresh = got.valueOrNull;
    if (fresh == null) {
      emit(s.copyWith(busy: false, lastError: got.failureOrNull));
      await load();
      return;
    }
    final res = await _repo.updateUserStory(
      projectId,
      storyId,
      body: UpdateUserStoryRequest(epicId: epicId),
      etag: fresh.etag ?? '',
    );
    if (res.isErr) {
      final f = res.failureOrNull;
      final stale = f is ConflictFailure;
      emit(s.copyWith(busy: false, lastError: f, staleData: stale));
      await load();
      return;
    }
    await load();
  }

  /// Optimistic reorder. On 409/412, rolls back via `load()` and surfaces
  /// `staleData: true` so the UI can show a banner.
  Future<void> reorderUserStory(String movedId, int newIndex) async {
    final s = state;
    if (s is! BacklogLoaded) return;
    final list = List.of(s.userStories);
    final oldIndex = list.indexWhere((u) => u.id == movedId);
    if (oldIndex < 0 || oldIndex == newIndex) return;

    final moved = list.removeAt(oldIndex);
    final insertAt = newIndex > oldIndex ? newIndex - 1 : newIndex;
    list.insert(insertAt, moved);
    emit(s.copyWith(userStories: list, busy: true, lastError: null));

    String? beforeId;
    String? afterId;
    final pos = list.indexWhere((u) => u.id == movedId);
    if (pos > 0) afterId = list[pos - 1].id;
    if (pos < list.length - 1) beforeId = list[pos + 1].id;

    final res = await _repo.moveUserStory(
      projectId,
      movedId,
      ReorderRequest(beforeId: beforeId, afterId: afterId),
    );
    if (res.isErr) {
      final stale = res.failureOrNull is ConflictFailure;
      emit(s.copyWith(busy: false, staleData: stale));
      await load();
      return;
    }
    await load();
  }

  Future<void> reorderEpic(String movedId, int newIndex) async {
    final s = state;
    if (s is! BacklogLoaded) return;
    final list = List.of(s.epics);
    final oldIndex = list.indexWhere((e) => e.id == movedId);
    if (oldIndex < 0 || oldIndex == newIndex) return;
    final moved = list.removeAt(oldIndex);
    final insertAt = newIndex > oldIndex ? newIndex - 1 : newIndex;
    list.insert(insertAt, moved);
    emit(s.copyWith(epics: list, busy: true, lastError: null));

    String? beforeId;
    String? afterId;
    final pos = list.indexWhere((e) => e.id == movedId);
    if (pos > 0) afterId = list[pos - 1].id;
    if (pos < list.length - 1) beforeId = list[pos + 1].id;

    final res = await _repo.moveEpic(
      projectId,
      movedId,
      ReorderRequest(beforeId: beforeId, afterId: afterId),
    );
    if (res.isErr) {
      final stale = res.failureOrNull is ConflictFailure;
      emit(s.copyWith(busy: false, staleData: stale));
      await load();
      return;
    }
    await load();
  }

  Future<void> deleteUserStory(String id) async {
    final s = state;
    if (s is! BacklogLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final got = await _repo.getUserStory(projectId, id);
    final fresh = got.valueOrNull;
    if (fresh == null) {
      emit(s.copyWith(busy: false, lastError: got.failureOrNull));
      return;
    }
    final res = await _repo.deleteUserStory(
      projectId,
      id,
      etag: fresh.etag ?? '',
    );
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }

  Future<void> deleteEpic(String id) async {
    final s = state;
    if (s is! BacklogLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final got = await _repo.getEpic(projectId, id);
    final fresh = got.valueOrNull;
    if (fresh == null) {
      emit(s.copyWith(busy: false, lastError: got.failureOrNull));
      return;
    }
    final res = await _repo.deleteEpic(projectId, id, etag: fresh.etag ?? '');
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }

  Future<void> updateUserStory(
    String id,
    UpdateUserStoryRequest body,
  ) async {
    final s = state;
    if (s is! BacklogLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final got = await _repo.getUserStory(projectId, id);
    final fresh = got.valueOrNull;
    if (fresh == null) {
      emit(s.copyWith(busy: false, lastError: got.failureOrNull));
      return;
    }
    final res = await _repo.updateUserStory(
      projectId,
      id,
      body: body,
      etag: fresh.etag ?? '',
    );
    if (res.isErr) {
      final stale = res.failureOrNull is ConflictFailure;
      emit(s.copyWith(busy: false, lastError: res.failureOrNull, staleData: stale));
      if (stale) await load();
      return;
    }
    await load();
  }

  Future<void> updateEpic(String id, UpdateEpicRequest body) async {
    final s = state;
    if (s is! BacklogLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final got = await _repo.getEpic(projectId, id);
    final fresh = got.valueOrNull;
    if (fresh == null) {
      emit(s.copyWith(busy: false, lastError: got.failureOrNull));
      return;
    }
    final res = await _repo.updateEpic(
      projectId,
      id,
      body: body,
      etag: fresh.etag ?? '',
    );
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }

  Future<void> bulkCreateUserStories(List<String> subjects, {
    String? epicId,
  }) async {
    final s = state;
    if (s is! BacklogLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final items = [
      for (final subj in subjects)
        if (subj.trim().isNotEmpty)
          BulkCreateUserStoryItem(subject: subj.trim(), epicId: epicId),
    ];
    if (items.isEmpty) {
      emit(s.copyWith(busy: false));
      return;
    }
    final res = await _repo.bulkCreateUserStories(
      projectId,
      BulkCreateUserStoriesRequest(items),
    );
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }
}
