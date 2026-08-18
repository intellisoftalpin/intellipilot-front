import 'dart:async';
import 'dart:convert';

import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';

/// Everything the board needs to paint instantly from cache: the board +
/// its data (columns/lanes), the taxonomy used by cards and the filter bar,
/// and the delta-sync cursor to catch up from.
class BoardSnapshot {
  const BoardSnapshot({
    required this.cursor,
    required this.savedAt,
    required this.board,
    required this.data,
    required this.statuses,
    required this.types,
    required this.priorities,
    required this.sizes,
    required this.epics,
    required this.labels,
    required this.components,
    required this.releaseVersions,
    required this.milestones,
  });

  final String cursor;
  final DateTime savedAt;
  final Board board;
  final BoardData data;
  final List<TaxonomyItem> statuses;
  final List<TaxonomyItem> types;
  final List<TaxonomyItem> priorities;
  final List<TaxonomyItem> sizes;
  final List<Epic> epics;
  final List<Label> labels;
  final List<Component> components;
  final List<ReleaseVersionRef> releaseVersions;
  final List<Milestone> milestones;
}

/// Persistent per-board snapshots in the Hive `boards` box.
///
/// Blanket rules (cache must never break the board):
///  * every read is failure-tolerant — schema mismatch, corrupt JSON or any
///    parse error yields `null` (and drops the entry) so callers fall back
///    to a normal network load;
///  * keys embed the user id, and [clearAll] wipes everything on logout /
///    account switch so data never crosses users;
///  * entries beyond [maxEntries] are evicted oldest-first.
class BoardSnapshotCache {
  BoardSnapshotCache(this._storage);

  final KeyValueStorage _storage;

  /// Bump when the envelope or any serialized DTO shape changes.
  static const int schemaVersion = 2;

  /// Snapshot count cap across all users/boards on this device.
  static const int maxEntries = 10;

  /// Refuse to persist pathologically large boards (~2 MB of JSON).
  static const int maxBytes = 2 * 1024 * 1024;

  static const String _indexKey = 'snapindex';

  static String _key(String userId, String projectId, String boardId) =>
      'snap:$userId:$projectId:$boardId';

  BoardSnapshot? load(String userId, String projectId, String boardId) {
    final key = _key(userId, projectId, boardId);
    try {
      final raw = _storage.get<String>(key);
      if (raw == null) return null;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (j['schema'] != schemaVersion) {
        unawaited(_drop(key));
        return null;
      }
      List<T> parse<T>(String field, T Function(Map<String, dynamic>) f) => [
        for (final e in (j[field] as List<dynamic>? ?? const []))
          f(e as Map<String, dynamic>),
      ];
      return BoardSnapshot(
        cursor: j['cursor'] as String,
        savedAt: DateTime.parse(j['saved_at'] as String),
        board: Board.fromJson(j['board'] as Map<String, dynamic>),
        data: BoardData.fromJson(j['data'] as Map<String, dynamic>),
        statuses: parse('statuses', TaxonomyItem.fromJson),
        types: parse('types', TaxonomyItem.fromJson),
        priorities: parse('priorities', TaxonomyItem.fromJson),
        sizes: parse('sizes', TaxonomyItem.fromJson),
        epics: parse('epics', Epic.fromJson),
        labels: parse('labels', Label.fromJson),
        components: parse('components', Component.fromJson),
        releaseVersions: parse('release_versions', ReleaseVersionRef.fromJson),
        milestones: parse('milestones', Milestone.fromJson),
      );
    } on Object {
      unawaited(_drop(key));
      return null;
    }
  }

  Future<void> save(
    String userId,
    String projectId,
    String boardId,
    BoardSnapshot snap,
  ) async {
    final key = _key(userId, projectId, boardId);
    try {
      final encoded = jsonEncode({
        'schema': schemaVersion,
        'cursor': snap.cursor,
        'saved_at': snap.savedAt.toIso8601String(),
        'board': _boardJson(snap.board),
        'data': _dataJson(snap.data),
        'statuses': [for (final e in snap.statuses) _taxonomyJson(e)],
        'types': [for (final e in snap.types) _taxonomyJson(e)],
        'priorities': [for (final e in snap.priorities) _taxonomyJson(e)],
        'sizes': [for (final e in snap.sizes) _taxonomyJson(e)],
        'epics': [for (final e in snap.epics) _epicJson(e)],
        'labels': [for (final e in snap.labels) _labelJson(e)],
        'components': [for (final e in snap.components) _componentJson(e)],
        'release_versions': [
          for (final e in snap.releaseVersions) _releaseVersionJson(e),
        ],
        'milestones': [for (final e in snap.milestones) _milestoneJson(e)],
      });
      if (encoded.length > maxBytes) return;
      await _storage.set<String>(key, encoded);
      await _touchIndex(key);
    } on Object {
      // Persistence is best-effort; never let a cache write surface.
    }
  }

  Future<void> clearBoard(
    String userId,
    String projectId,
    String boardId,
  ) async {
    await _drop(_key(userId, projectId, boardId));
  }

  /// Wipe every snapshot (logout / account switch).
  Future<void> clearAll() async {
    final keys = _storage.get<List<dynamic>>(_indexKey) ?? const [];
    for (final k in keys) {
      await _storage.remove(k.toString());
    }
    await _storage.remove(_indexKey);
  }

  Future<void> _drop(String key) async {
    try {
      await _storage.remove(key);
      final keys = (_storage.get<List<dynamic>>(_indexKey) ?? const [])
          .map((e) => e.toString())
          .where((k) => k != key)
          .toList();
      await _storage.set<List<String>>(_indexKey, keys);
    } on Object {
      // Best-effort.
    }
  }

  /// Move [key] to the front of the LRU index and evict beyond [maxEntries].
  Future<void> _touchIndex(String key) async {
    final keys = (_storage.get<List<dynamic>>(_indexKey) ?? const [])
        .map((e) => e.toString())
        .where((k) => k != key)
        .toList();
    keys.insert(0, key);
    while (keys.length > maxEntries) {
      await _storage.remove(keys.removeLast());
    }
    await _storage.set<List<String>>(_indexKey, keys);
  }

  // -- wire-format serializers (mirror the DTO `fromJson` factories, so the
  //    snapshot round-trips through the exact same parsing code as the API) --

  static Map<String, dynamic> _boardJson(Board b) => {
    'id': b.id,
    'project_id': b.projectId,
    'owner_id': b.ownerId,
    'visibility': b.visibility,
    'name': b.name,
    'key': b.key,
    'color': b.color,
    'config': b.config,
    'order': b.order,
  };

  static Map<String, dynamic> _dataJson(BoardData d) => {
    'group': d.group,
    'columns': [for (final c in d.columns) _columnJson(c)],
    'lanes': [
      for (final l in d.lanes)
        {
          'key': l.key,
          'total': l.total,
          'columns': [for (final c in l.columns) _columnJson(c)],
        },
    ],
  };

  static Map<String, dynamic> _columnJson(BoardColumnData c) => {
    'status_id': c.statusId,
    'total': c.total,
    'cards': [for (final i in c.cards) issueJson(i)],
  };

  /// Public: the reconciler also uses it to clone an [Issue] with edits.
  static Map<String, dynamic> issueJson(Issue i) => {
    'id': i.id,
    'project_id': i.projectId,
    'ref': i.reference,
    'subject': i.subject,
    'description': i.description,
    'status_id': i.statusId,
    'type_id': i.typeId,
    'priority_id': i.priorityId,
    'size_id': i.sizeId,
    'epic_id': i.epicId,
    'parent_id': i.parentId,
    'milestone_id': i.milestoneId,
    'owner_id': i.ownerId,
    'assigned_to': i.assignedTo,
    'qa_assignee_id': i.qaAssigneeId,
    'reviewer_id': i.reviewerId,
    'category': i.category,
    'customer_ids': i.customerIds,
    'start_date': i.startDate,
    'due_date': i.dueDate,
    'resolution': i.resolution,
    'resolved_at': i.resolvedAt,
    'release_version_id': i.releaseVersionId,
    'component_versions': [
      for (final cv in i.componentVersions)
        {
          'component_id': cv.componentId,
          'release_version_id': cv.releaseVersionId,
        },
    ],
    'release_text': i.releaseText,
    'labels': i.labels,
    'components': i.components,
    'watchers': i.watchers,
    'order': i.order,
    'version': i.version,
    'created_at': i.createdAt.toIso8601String(),
    'modified_at': i.modifiedAt.toIso8601String(),
  };

  static Map<String, dynamic> _epicJson(Epic e) => {
    'id': e.id,
    'project_id': e.projectId,
    'ref': e.reference,
    'subject': e.subject,
    'description': e.description,
    'color': e.color,
    'order': e.order,
    'version': e.version,
    'status_id': e.statusId,
    'owner_id': e.ownerId,
    'assigned_to': e.assignedTo,
    'milestone_id': e.milestoneId,
    'start_date': e.startDate,
    'end_date': e.endDate,
    'cover_image_kind': e.coverImageKind,
    'cover_image_updated_at': e.coverImageUpdatedAt,
    'task_total': e.taskTotal,
    'task_closed': e.taskClosed,
    'created_at': e.createdAt.toIso8601String(),
    'modified_at': e.modifiedAt.toIso8601String(),
  };

  static Map<String, dynamic> _taxonomyJson(TaxonomyItem t) => {
    'id': t.id,
    'project_id': t.projectId,
    'kind': t.kind.wire,
    'name': t.name,
    'slug': t.slug,
    'color': t.color,
    'emoji': t.emoji,
    'order': t.order,
    'is_closed': t.isClosed,
    'counts_as_done': t.countsAsDone,
    'is_new': t.isNew,
    'value': t.value,
    'created_at': t.createdAt.toIso8601String(),
  };

  static Map<String, dynamic> _labelJson(Label l) => {
    'id': l.id,
    'project_id': l.projectId,
    'name': l.name,
    'color': l.color,
    'created_at': l.createdAt.toIso8601String(),
  };

  static Map<String, dynamic> _componentJson(Component c) => {
    'id': c.id,
    'project_id': c.projectId,
    'name': c.name,
    'color': c.color,
    'created_at': c.createdAt.toIso8601String(),
  };

  static Map<String, dynamic> _releaseVersionJson(ReleaseVersionRef v) => {
    'id': v.id,
    'release_id': v.releaseId,
    'release_name': v.releaseName,
    'release_color': v.releaseColor,
    'version': v.version,
    'status': v.status,
  };

  static Map<String, dynamic> _milestoneJson(Milestone m) => {
    'id': m.id,
    'project_id': m.projectId,
    'name': m.name,
    'slug': m.slug,
    'start_date': m.startDate?.toIso8601String(),
    'end_date': m.endDate?.toIso8601String(),
    'closed': m.closed,
    'closed_at': m.closedAt?.toIso8601String(),
    'order': m.order,
    'version': m.version,
    'created_at': m.createdAt.toIso8601String(),
    'modified_at': m.modifiedAt.toIso8601String(),
  };
}
