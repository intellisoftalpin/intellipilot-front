/// Taxonomy kinds the backend exposes. Wire format is snake_case;
/// this enum keeps the strings identical so we round-trip without mapping.
enum TaxonomyKind {
  issueStatus('issue_status'),
  issueType('issue_type'),
  priority('priority'),
  severity('severity'),
  point('point');

  const TaxonomyKind(this.wire);
  final String wire;

  /// Kinds that carry an `is_closed` flag (the status kind).
  bool get hasClosed => this == TaxonomyKind.issueStatus;

  /// Kinds that carry a numeric `value` (points only).
  bool get hasValue => this == TaxonomyKind.point;

  static TaxonomyKind fromWire(String wire) {
    for (final k in TaxonomyKind.values) {
      if (k.wire == wire) return k;
    }
    return TaxonomyKind.issueStatus;
  }
}

class TaxonomyItem {
  const TaxonomyItem({
    required this.id,
    required this.projectId,
    required this.kind,
    required this.name,
    required this.slug,
    required this.color,
    required this.order,
    required this.createdAt,
    this.isClosed,
    this.value,
  });

  factory TaxonomyItem.fromJson(Map<String, dynamic> json) {
    return TaxonomyItem(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      kind: TaxonomyKind.fromWire(json['kind'] as String? ?? 'us_status'),
      name: json['name'] as String,
      slug: json['slug'] as String,
      color: (json['color'] as String?) ?? '',
      order: (json['order'] as num?)?.toDouble() ?? 0.0,
      isClosed: json['is_closed'] as bool?,
      value: (json['value'] as num?)?.toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String projectId;
  final TaxonomyKind kind;
  final String name;
  final String slug;
  final String color;
  final double order;
  final bool? isClosed;
  final double? value;
  final DateTime createdAt;
}

class CreateTaxonomyItemRequest {
  const CreateTaxonomyItemRequest({
    required this.name,
    required this.slug,
    this.color = '',
    this.isClosed,
    this.value,
  });

  final String name;
  final String slug;
  final String color;
  final bool? isClosed;
  final double? value;

  Map<String, dynamic> toJson() => {
    'name': name,
    'slug': slug,
    'color': color,
    if (isClosed != null) 'is_closed': isClosed,
    if (value != null) 'value': value,
  };
}

class UpdateTaxonomyItemRequest {
  const UpdateTaxonomyItemRequest({
    this.name,
    this.color,
    this.isClosed,
    this.value,
  });

  final String? name;
  final String? color;
  final bool? isClosed;
  final double? value;

  Map<String, dynamic> toJson() => {
    if (name != null) 'name': name,
    if (color != null) 'color': color,
    if (isClosed != null) 'is_closed': isClosed,
    if (value != null) 'value': value,
  };
}

class MoveTaxonomyItemRequest {
  const MoveTaxonomyItemRequest({this.beforeId, this.afterId});
  final String? beforeId;
  final String? afterId;

  Map<String, dynamic> toJson() => {
    if (beforeId != null) 'before_id': beforeId,
    if (afterId != null) 'after_id': afterId,
  };
}

// ---- labels ----

class Label {
  const Label({
    required this.id,
    required this.projectId,
    required this.name,
    required this.color,
    required this.createdAt,
  });

  factory Label.fromJson(Map<String, dynamic> json) {
    return Label(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      name: json['name'] as String,
      color: (json['color'] as String?) ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String projectId;
  final String name;
  final String color;
  final DateTime createdAt;
}

class CreateLabelRequest {
  const CreateLabelRequest({required this.name, this.color = ''});
  final String name;
  final String color;
  Map<String, dynamic> toJson() => {'name': name, 'color': color};
}

class UpdateLabelRequest {
  const UpdateLabelRequest({this.name, this.color});
  final String? name;
  final String? color;
  Map<String, dynamic> toJson() => {
    if (name != null) 'name': name,
    if (color != null) 'color': color,
  };
}

// ---- components ----

class Component {
  const Component({
    required this.id,
    required this.projectId,
    required this.name,
    required this.color,
    required this.createdAt,
    this.gitRepository,
  });

  factory Component.fromJson(Map<String, dynamic> json) {
    return Component(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      name: json['name'] as String,
      color: (json['color'] as String?) ?? '',
      gitRepository: json['git_repository'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String projectId;
  final String name;
  final String color;
  final String? gitRepository;
  final DateTime createdAt;
}

class CreateComponentRequest {
  const CreateComponentRequest({
    required this.name,
    this.color = '',
    this.gitRepository,
  });
  final String name;
  final String color;
  final String? gitRepository;
  Map<String, dynamic> toJson() => {
    'name': name,
    'color': color,
    if (gitRepository != null) 'git_repository': gitRepository,
  };
}

class UpdateComponentRequest {
  const UpdateComponentRequest({
    this.name,
    this.color,
    this.gitRepository = const _Absent(),
  });
  final String? name;
  final String? color;

  /// `_Absent` keeps the field out of the JSON entirely; pass `null`
  /// explicitly to clear the link on the backend.
  final Object? gitRepository;

  Map<String, dynamic> toJson() => {
    if (name != null) 'name': name,
    if (color != null) 'color': color,
    if (gitRepository is! _Absent) 'git_repository': gitRepository,
  };
}

class _Absent {
  const _Absent();
}

/// Default swatch palette — same hex values the backend seeds its built-in
/// taxonomies with so picker selections round-trip without normalisation.
abstract final class ColorPalette {
  static const swatches = <String>[
    '#999999',
    '#ff8a84',
    '#ffcc00',
    '#9dce0a',
    '#669900',
    '#0079bc',
    '#5c3566',
    '#cc0000',
    '#ff7518',
    '#34495e',
  ];
}
