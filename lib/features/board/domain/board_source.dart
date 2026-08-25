// `_catalog` / `_storage` are intentionally private fields for clarity.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/features/board/domain/board_config.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';

/// Where a board page gets its [Board] definition, and where a change to that
/// definition is persisted.
///
/// Real boards live on the server ([RemoteBoardSource]). The My Issues board
/// is synthetic — fixed lanes, no server row — and keeps its column layout in
/// local storage ([LocalBoardSource]).
abstract interface class BoardSource {
  /// Identifies the board for the snapshot cache and for `board.changed`
  /// events. Synthetic boards use a reserved non-UUID id.
  String get boardId;

  /// Whether the definition can change underneath us — i.e. whether a
  /// `board.changed` event or a revalidation fetch is meaningful.
  bool get isRemote;

  Future<Result<Board, AppFailure>> load();

  /// Record that the user opened this board. A no-op for synthetic boards.
  Future<void> markOpened();

  /// Persist a changed config (column order/visibility, column limit).
  Future<Result<Board, AppFailure>> saveConfig(BoardConfig config);
}

/// A first-class board stored on the server.
class RemoteBoardSource implements BoardSource {
  RemoteBoardSource({
    required CatalogRepository catalog,
    required this.projectId,
    required this.boardId,
  }) : _catalog = catalog;

  final CatalogRepository _catalog;
  final String projectId;

  @override
  final String boardId;

  @override
  bool get isRemote => true;

  @override
  Future<Result<Board, AppFailure>> load() =>
      _catalog.getBoard(projectId, boardId);

  @override
  Future<void> markOpened() => _catalog.setLastOpenedBoard(projectId, boardId);

  @override
  Future<Result<Board, AppFailure>> saveConfig(BoardConfig config) async {
    final current = await _catalog.getBoard(projectId, boardId);
    final board = current.valueOrNull;
    if (board == null) return current;
    return _catalog.updateBoard(
      projectId,
      boardId,
      name: board.name,
      color: board.color,
      config: config.toMap(),
    );
  }
}

/// The synthetic My Issues board.
///
/// There is no server row: the group is always [BoardGroupBy.myRole], the
/// lanes are fixed, and only the column layout is user-configurable — kept
/// per (user, project) in local storage. Everything else about the board page
/// (snapshot cache, delta sync, live events, drag-to-move) works unchanged,
/// because [boardId] is just an opaque cache key to those layers.
class LocalBoardSource implements BoardSource {
  LocalBoardSource({
    required KeyValueStorage storage,
    required this.projectId,
    required this.userId,
    required this.name,
    this.boardId = myIssuesBoardId,
  }) : _storage = storage;

  /// Reserved board id for the My Issues board. Deliberately not a UUID, so it
  /// can never collide with a real board or match a `board.changed` event.
  static const myIssuesBoardId = 'my-issues';

  final KeyValueStorage _storage;
  final String projectId;
  final String userId;

  /// Display name, already localised by the caller.
  final String name;

  @override
  final String boardId;

  @override
  bool get isRemote => false;

  String get _key => 'boardcfg:$boardId:$userId:$projectId';

  BoardConfig _storedConfig() {
    final raw = _storage.get<String>(_key);
    if (raw == null || raw.isEmpty) return const BoardConfig();
    try {
      return BoardConfig.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return const BoardConfig();
    }
  }

  Board _board(BoardConfig config) => Board(
    id: boardId,
    projectId: projectId,
    visibility: 'personal',
    name: name,
    key: boardId,
    color: '',
    // The grouping is not the user's to change, so it is forced on every read
    // regardless of what the stored blob says.
    config: config.copyWith(group: BoardGroupBy.myRole).toMap(),
    order: 0,
    ownerId: userId,
  );

  @override
  Future<Result<Board, AppFailure>> load() async => Ok(_board(_storedConfig()));

  @override
  Future<void> markOpened() async {}

  @override
  Future<Result<Board, AppFailure>> saveConfig(BoardConfig config) async {
    final forced = config.copyWith(group: BoardGroupBy.myRole);
    await _storage.set<String>(_key, jsonEncode(forced.toMap()));
    return Ok(_board(forced));
  }
}
