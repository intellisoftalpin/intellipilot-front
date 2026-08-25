import 'package:intellipilot/core/work_items/work_item_filter.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';

/// Swimlane grouping dimensions for a board. `null` is the flat single-board
/// layout. [filterKey] is the matching [WorkItemFilter] dimension key — the
/// group dimension must never also be a filter, so the board strips it.
enum BoardGroupBy {
  component('component', 'component'),
  assignee('assignee', 'assignee'),
  epic('epic', 'epic'),
  priority('priority', 'priority'),

  /// The My Issues board: lanes are the caller's roles on the issue. Not
  /// offered in the board settings dialog — it belongs to the dedicated My
  /// Issues page, whose board is synthetic.
  myRole('my_role', 'my_role');

  const BoardGroupBy(this.wire, this.filterKey);
  final String wire;
  final String filterKey;

  static BoardGroupBy? fromWire(String? wire) {
    if (wire == null) return null;
    for (final g in BoardGroupBy.values) {
      if (g.wire == wire) return g;
    }
    return null;
  }
}

/// The SPA-owned board `config` blob. Round-trips through
/// `createBoard`/`updateBoard`/`getBoard` unchanged.
///
/// Shape:
/// ```json
/// { "columns": {"visible":[statusId...], "order":[statusId...]},
///   "group": "component"|"assignee"|"epic"|"priority"|null,
///   "filters": { ...WorkItemFilter.toJson() subset },   // LOCKED filters
///   "column_limit": 50,
///   "closed_within_days": 14,        // optional
///   "card_fields": ["assignee","labels","priority","size","due"] } // optional
/// ```
class BoardConfig {
  const BoardConfig({
    this.columnOrder = const [],
    this.visibleColumnIds = const [],
    this.group,
    this.filters = const WorkItemFilter(),
    this.columnLimit = 50,
    this.closedWithinDays,
    this.cardFields,
  });

  factory BoardConfig.fromMap(Map<String, dynamic> map) {
    final columns = map['columns'];
    var order = const <String>[];
    var visible = const <String>[];
    if (columns is Map<String, dynamic>) {
      order = (columns['order'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList();
      visible = (columns['visible'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList();
    }
    final filtersRaw = map['filters'];
    return BoardConfig(
      columnOrder: order,
      visibleColumnIds: visible,
      group: BoardGroupBy.fromWire(map['group'] as String?),
      filters: filtersRaw is Map<String, dynamic>
          ? WorkItemFilter.fromJson(filtersRaw)
          : const WorkItemFilter(),
      columnLimit: (map['column_limit'] as num?)?.toInt() ?? 50,
      closedWithinDays: (map['closed_within_days'] as num?)?.toInt(),
      cardFields: (map['card_fields'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
    );
  }

  /// A sensible default config for a brand-new board: every status visible in
  /// the taxonomy default order, flat, no locked filters.
  factory BoardConfig.defaults(List<TaxonomyItem> statuses) {
    final order = defaultColumnOrder(statuses);
    return BoardConfig(columnOrder: order, visibleColumnIds: order);
  }

  /// The full ordering of status ids (a superset that may include hidden ones).
  final List<String> columnOrder;

  /// The subset of [columnOrder] that should render, in order.
  final List<String> visibleColumnIds;
  final BoardGroupBy? group;

  /// The board's LOCKED filters. Locked dimensions win over a user's ad-hoc
  /// transient filters and cannot be edited on the board.
  final WorkItemFilter filters;
  final int columnLimit;
  final int? closedWithinDays;
  final List<String>? cardFields;

  /// Status ids hidden from the board (in [columnOrder] but not visible).
  Set<String> get hiddenColumnIds => {
    for (final id in columnOrder)
      if (!visibleColumnIds.contains(id)) id,
  };

  /// The locked filter dimension keys (intersection with the bar's dimensions).
  Set<String> get lockedDimensions => {
    for (final key in filters.toJson().keys)
      if (_barDimensions.contains(key)) key,
  };

  static const _barDimensions = {
    'status',
    'type',
    'priority',
    'size',
    'assignee',
    'epic',
    'milestone',
    'label',
    'component',
    'category',
    'overdue',
  };

  Map<String, dynamic> toMap() => {
    'columns': {'visible': visibleColumnIds, 'order': columnOrder},
    'group': group?.wire,
    'filters': filters.toJson(),
    'column_limit': columnLimit,
    if (closedWithinDays != null) 'closed_within_days': closedWithinDays,
    if (cardFields != null) 'card_fields': cardFields,
  };

  BoardConfig copyWith({
    List<String>? columnOrder,
    List<String>? visibleColumnIds,
    Object? group = _keep,
    WorkItemFilter? filters,
    int? columnLimit,
    Object? closedWithinDays = _keep,
    Object? cardFields = _keep,
  }) => BoardConfig(
    columnOrder: columnOrder ?? this.columnOrder,
    visibleColumnIds: visibleColumnIds ?? this.visibleColumnIds,
    group: group == _keep ? this.group : group as BoardGroupBy?,
    filters: filters ?? this.filters,
    columnLimit: columnLimit ?? this.columnLimit,
    closedWithinDays: closedWithinDays == _keep
        ? this.closedWithinDays
        : closedWithinDays as int?,
    cardFields: cardFields == _keep
        ? this.cardFields
        : cardFields as List<String>?,
  );

  static const _keep = Object();

  /// The default column ordering for [statuses]: the `is_new` status first, the
  /// `is_closed` statuses last, the rest by their taxonomy `order` in between.
  static List<String> defaultColumnOrder(List<TaxonomyItem> statuses) {
    final sorted = [...statuses]
      ..sort((a, b) {
        int rank(TaxonomyItem s) {
          if (s.isNew ?? false) return 0;
          if (s.isClosed ?? false) return 2;
          return 1;
        }

        final ra = rank(a);
        final rb = rank(b);
        if (ra != rb) return ra.compareTo(rb);
        return a.order.compareTo(b.order);
      });
    return [for (final s in sorted) s.id];
  }
}
