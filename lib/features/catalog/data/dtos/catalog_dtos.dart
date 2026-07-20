import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';

/// Taxonomy kinds the backend exposes. Wire format is snake_case;
/// this enum keeps the strings identical so we round-trip without mapping.
enum TaxonomyKind {
  issueStatus('issue_status'),
  issueType('issue_type'),
  priority('priority'),
  size('size');

  const TaxonomyKind(this.wire);
  final String wire;

  /// Kinds that carry an `is_closed` flag (the status kind).
  bool get hasClosed => this == TaxonomyKind.issueStatus;

  /// Kinds that carry an `is_new` flag — the default landing column; at most
  /// one status per project carries it (the status kind).
  bool get hasNew => this == TaxonomyKind.issueStatus;

  /// Kinds that carry a numeric `value` (size only — the ordinal 1..6 that
  /// drives the scaled size badge).
  bool get hasValue => this == TaxonomyKind.size;

  /// Kinds that carry an identifying emoji (issue type and priority), shown as
  /// a small glyph on their chips.
  bool get hasEmoji =>
      this == TaxonomyKind.issueType || this == TaxonomyKind.priority;

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
    this.emoji = '',
    this.isClosed,
    this.isNew,
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
      emoji: (json['emoji'] as String?) ?? '',
      order: (json['order'] as num?)?.toDouble() ?? 0.0,
      isClosed: json['is_closed'] as bool?,
      isNew: json['is_new'] as bool?,
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
  final String emoji;
  final double order;
  final bool? isClosed;

  /// The "new" (default) status flag — status kind only; at most one per project.
  final bool? isNew;
  final double? value;
  final DateTime createdAt;
}

class CreateTaxonomyItemRequest {
  const CreateTaxonomyItemRequest({
    required this.name,
    required this.slug,
    this.color = '',
    this.emoji = '',
    this.isClosed,
    this.isNew,
    this.value,
  });

  final String name;
  final String slug;
  final String color;
  final String emoji;
  final bool? isClosed;
  final bool? isNew;
  final double? value;

  Map<String, dynamic> toJson() => {
    'name': name,
    'slug': slug,
    'color': color,
    'emoji': emoji,
    if (isClosed != null) 'is_closed': isClosed,
    if (isNew != null) 'is_new': isNew,
    if (value != null) 'value': value,
  };
}

class UpdateTaxonomyItemRequest {
  const UpdateTaxonomyItemRequest({
    this.name,
    this.color,
    this.emoji,
    this.isClosed,
    this.isNew,
    this.value,
  });

  final String? name;
  final String? color;
  final String? emoji;
  final bool? isClosed;
  final bool? isNew;
  final double? value;

  Map<String, dynamic> toJson() => {
    if (name != null) 'name': name,
    if (color != null) 'color': color,
    if (emoji != null) 'emoji': emoji,
    if (isClosed != null) 'is_closed': isClosed,
    if (isNew != null) 'is_new': isNew,
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
  });

  factory Component.fromJson(Map<String, dynamic> json) {
    return Component(
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

class CreateComponentRequest {
  const CreateComponentRequest({required this.name, this.color = ''});
  final String name;
  final String color;
  Map<String, dynamic> toJson() => {'name': name, 'color': color};
}

class UpdateComponentRequest {
  const UpdateComponentRequest({this.name, this.color});
  final String? name;
  final String? color;

  Map<String, dynamic> toJson() => {
    if (name != null) 'name': name,
    if (color != null) 'color': color,
  };
}

// ---- git: SSH keys, repositories, component links ----

class SshKey {
  const SshKey({
    required this.id,
    required this.projectId,
    required this.name,
    required this.readOnly,
    required this.keyType,
    required this.publicKey,
    required this.fingerprint,
    required this.usedByRepoCount,
    required this.createdAt,
  });

  factory SshKey.fromJson(Map<String, dynamic> json) {
    return SshKey(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      name: json['name'] as String,
      readOnly: json['read_only'] as bool? ?? true,
      keyType: json['key_type'] as String? ?? 'ed25519',
      publicKey: json['public_key'] as String? ?? '',
      fingerprint: json['fingerprint'] as String? ?? '',
      usedByRepoCount: (json['used_by_repo_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String projectId;
  final String name;
  final bool readOnly;
  final String keyType;
  final String publicKey;
  final String fingerprint;
  final int usedByRepoCount;
  final DateTime createdAt;
}

class CreateSshKeyRequest {
  const CreateSshKeyRequest({required this.name, this.readOnly = true});
  final String name;
  final bool readOnly;
  Map<String, dynamic> toJson() => {'name': name, 'read_only': readOnly};
}

class UpdateSshKeyRequest {
  const UpdateSshKeyRequest({this.name, this.readOnly});
  final String? name;
  final bool? readOnly;
  Map<String, dynamic> toJson() => {
    if (name != null) 'name': name,
    if (readOnly != null) 'read_only': readOnly,
  };
}

class Repository {
  const Repository({
    required this.id,
    required this.projectId,
    required this.name,
    required this.sshUrl,
    required this.createdAt,
    this.sshKeyId,
    this.defaultBranch,
    this.hostFingerprint,
  });

  factory Repository.fromJson(Map<String, dynamic> json) {
    return Repository(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      name: json['name'] as String,
      sshUrl: json['ssh_url'] as String,
      sshKeyId: json['ssh_key_id'] as String?,
      defaultBranch: json['default_branch'] as String?,
      hostFingerprint: json['host_fingerprint'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String projectId;
  final String name;
  final String sshUrl;
  final String? sshKeyId;
  final String? defaultBranch;
  final String? hostFingerprint;
  final DateTime createdAt;

  bool get hasKey => sshKeyId != null;
}

class CreateRepositoryRequest {
  const CreateRepositoryRequest({
    required this.name,
    required this.sshUrl,
    this.sshKeyId,
    this.newKey,
    this.defaultBranch,
  });
  final String name;
  final String sshUrl;
  final String? sshKeyId;
  final CreateSshKeyRequest? newKey;
  final String? defaultBranch;

  Map<String, dynamic> toJson() => {
    'name': name,
    'ssh_url': sshUrl,
    if (sshKeyId != null) 'ssh_key_id': sshKeyId,
    if (newKey != null) 'new_key': newKey!.toJson(),
    if (defaultBranch != null) 'default_branch': defaultBranch,
  };
}

class UpdateRepositoryRequest {
  const UpdateRepositoryRequest({
    this.name,
    this.sshUrl,
    this.sshKeyId = const _Absent(),
    this.defaultBranch = const _Absent(),
  });
  final String? name;
  final String? sshUrl;

  /// `_Absent` omits the field; `null` clears it on the backend.
  final Object? sshKeyId;
  final Object? defaultBranch;

  Map<String, dynamic> toJson() => {
    if (name != null) 'name': name,
    if (sshUrl != null) 'ssh_url': sshUrl,
    if (sshKeyId is! _Absent) 'ssh_key_id': sshKeyId,
    if (defaultBranch is! _Absent) 'default_branch': defaultBranch,
  };
}

class RemoteBranches {
  const RemoteBranches({
    required this.branches,
    this.defaultBranch,
    this.hostFingerprint,
  });

  factory RemoteBranches.fromJson(Map<String, dynamic> json) {
    return RemoteBranches(
      branches: (json['branches'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(),
      defaultBranch: json['default_branch'] as String?,
      hostFingerprint: json['host_fingerprint'] as String?,
    );
  }

  final List<String> branches;
  final String? defaultBranch;
  final String? hostFingerprint;
}

class ComponentRepositoryLink {
  const ComponentRepositoryLink({
    required this.componentId,
    required this.repositoryId,
    required this.repositoryName,
    required this.sshUrl,
    required this.branch,
    required this.createdAt,
  });

  factory ComponentRepositoryLink.fromJson(Map<String, dynamic> json) {
    return ComponentRepositoryLink(
      componentId: json['component_id'] as String,
      repositoryId: json['repository_id'] as String,
      repositoryName: json['repository_name'] as String,
      sshUrl: json['ssh_url'] as String,
      branch: json['branch'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String componentId;
  final String repositoryId;
  final String repositoryName;
  final String sshUrl;
  final String branch;
  final DateTime createdAt;
}

// ---- customers ----

class Customer {
  const Customer({
    required this.id,
    required this.projectId,
    required this.name,
    required this.createdAt,
    this.companyName,
    this.contactEmail,
    this.phone,
    this.notes,
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      name: json['name'] as String,
      companyName: json['company_name'] as String?,
      contactEmail: json['contact_email'] as String?,
      phone: json['phone'] as String?,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String projectId;
  final String name;
  final String? companyName;
  final String? contactEmail;
  final String? phone;
  final String? notes;
  final DateTime createdAt;
}

class CreateCustomerRequest {
  const CreateCustomerRequest({
    required this.name,
    this.companyName,
    this.contactEmail,
    this.phone,
    this.notes,
  });
  final String name;
  final String? companyName;
  final String? contactEmail;
  final String? phone;
  final String? notes;

  Map<String, dynamic> toJson() => {
    'name': name,
    if (companyName != null) 'company_name': companyName,
    if (contactEmail != null) 'contact_email': contactEmail,
    if (phone != null) 'phone': phone,
    if (notes != null) 'notes': notes,
  };
}

class UpdateCustomerRequest {
  const UpdateCustomerRequest({
    this.name,
    this.companyName,
    this.contactEmail,
    this.phone,
    this.notes,
  });
  final String? name;
  final String? companyName;
  final String? contactEmail;
  final String? phone;
  final String? notes;

  Map<String, dynamic> toJson() => {
    if (name != null) 'name': name,
    if (companyName != null) 'company_name': companyName,
    if (contactEmail != null) 'contact_email': contactEmail,
    if (phone != null) 'phone': phone,
    if (notes != null) 'notes': notes,
  };
}

// ---- releases + versions ----

class Release {
  const Release({
    required this.id,
    required this.projectId,
    required this.name,
    required this.color,
    required this.createdAt,
    this.description,
  });

  factory Release.fromJson(Map<String, dynamic> json) {
    return Release(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      color: (json['color'] as String?) ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String projectId;
  final String name;
  final String? description;
  final String color;
  final DateTime createdAt;
}

class CreateReleaseRequest {
  const CreateReleaseRequest({
    required this.name,
    this.description,
    this.color = '',
  });
  final String name;
  final String? description;
  final String color;
  Map<String, dynamic> toJson() => {
    'name': name,
    if (description != null) 'description': description,
    'color': color,
  };
}

class UpdateReleaseRequest {
  const UpdateReleaseRequest({this.name, this.description, this.color});
  final String? name;
  final String? description;
  final String? color;
  Map<String, dynamic> toJson() => {
    if (name != null) 'name': name,
    if (description != null) 'description': description,
    if (color != null) 'color': color,
  };
}

class ReleaseVersion {
  const ReleaseVersion({
    required this.id,
    required this.releaseId,
    required this.version,
    required this.status,
    required this.notes,
    required this.createdAt,
    this.targetDate,
    this.releasedAt,
    this.repositoryId,
    this.gitTag,
  });

  factory ReleaseVersion.fromJson(Map<String, dynamic> json) {
    return ReleaseVersion(
      id: json['id'] as String,
      releaseId: json['release_id'] as String,
      version: json['version'] as String,
      status: (json['status'] as String?) ?? 'planned',
      notes: (json['notes'] as String?) ?? '',
      targetDate: json['target_date'] as String?,
      releasedAt: json['released_at'] as String?,
      repositoryId: json['repository_id'] as String?,
      gitTag: json['git_tag'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String releaseId;
  final String version;

  /// One of `planned`, `in_progress`, `released`.
  final String status;
  final String notes;
  final String? targetDate;
  final String? releasedAt;
  final String? repositoryId;
  final String? gitTag;
  final DateTime createdAt;
}

class CreateReleaseVersionRequest {
  const CreateReleaseVersionRequest({
    required this.version,
    this.status = 'planned',
    this.targetDate,
    this.releasedAt,
    this.notes,
    this.repositoryId,
    this.gitTag,
  });
  final String version;
  final String status;
  final String? targetDate;
  final String? releasedAt;
  final String? notes;
  final String? repositoryId;
  final String? gitTag;

  Map<String, dynamic> toJson() => {
    'version': version,
    'status': status,
    if (targetDate != null) 'target_date': targetDate,
    if (releasedAt != null) 'released_at': releasedAt,
    if (notes != null) 'notes': notes,
    if (repositoryId != null) 'repository_id': repositoryId,
    if (gitTag != null) 'git_tag': gitTag,
  };
}

class UpdateReleaseVersionRequest {
  const UpdateReleaseVersionRequest({
    this.version,
    this.status,
    this.targetDate = const _Absent(),
    this.releasedAt = const _Absent(),
    this.notes,
    this.repositoryId = const _Absent(),
    this.gitTag = const _Absent(),
  });
  final String? version;
  final String? status;

  /// `_Absent` omits the field; `null` clears it on the backend.
  final Object? targetDate;
  final Object? releasedAt;
  final String? notes;
  final Object? repositoryId;
  final Object? gitTag;

  Map<String, dynamic> toJson() => {
    if (version != null) 'version': version,
    if (status != null) 'status': status,
    if (targetDate is! _Absent) 'target_date': targetDate,
    if (releasedAt is! _Absent) 'released_at': releasedAt,
    if (notes != null) 'notes': notes,
    if (repositoryId is! _Absent) 'repository_id': repositoryId,
    if (gitTag is! _Absent) 'git_tag': gitTag,
  };
}

/// A release version paired with its release name — used by the issue
/// fix-version picker (`release-versions/for-components`).
class ReleaseVersionRef {
  const ReleaseVersionRef({
    required this.id,
    required this.releaseId,
    required this.releaseName,
    required this.releaseColor,
    required this.version,
    required this.status,
  });

  factory ReleaseVersionRef.fromJson(Map<String, dynamic> json) {
    return ReleaseVersionRef(
      id: json['id'] as String,
      releaseId: json['release_id'] as String,
      releaseName: (json['release_name'] as String?) ?? '',
      releaseColor: (json['release_color'] as String?) ?? '',
      version: json['version'] as String,
      status: (json['status'] as String?) ?? 'planned',
    );
  }

  final String id;
  final String releaseId;
  final String releaseName;
  final String releaseColor;
  final String version;
  final String status;

  String get label => releaseName.isEmpty ? version : '$releaseName $version';
}

// ---- component <-> release links ----

class ComponentReleaseLink {
  const ComponentReleaseLink({
    required this.componentId,
    required this.releaseId,
    required this.releaseName,
    required this.createdAt,
  });

  factory ComponentReleaseLink.fromJson(Map<String, dynamic> json) {
    return ComponentReleaseLink(
      componentId: json['component_id'] as String,
      releaseId: json['release_id'] as String,
      releaseName: (json['release_name'] as String?) ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String componentId;
  final String releaseId;
  final String releaseName;
  final DateTime createdAt;
}

// ---- issue relationships ----

class IssueLink {
  const IssueLink({
    required this.id,
    required this.otherIssueId,
    required this.otherRef,
    required this.otherSubject,
    required this.linkType,
    required this.direction,
    required this.createdAt,
  });

  factory IssueLink.fromJson(Map<String, dynamic> json) {
    return IssueLink(
      id: json['id'] as String,
      otherIssueId: json['other_issue_id'] as String,
      otherRef: (json['other_ref'] as num?)?.toInt() ?? 0,
      otherSubject: (json['other_subject'] as String?) ?? '',
      linkType: (json['link_type'] as String?) ?? 'relates',
      direction: (json['direction'] as String?) ?? 'outgoing',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String otherIssueId;
  final int otherRef;
  final String otherSubject;

  /// One of `blocks`, `relates`, `duplicates`.
  final String linkType;

  /// `outgoing` or `incoming` — drives inverse-label rendering.
  final String direction;
  final DateTime createdAt;

  /// Human label for the relationship, rendering the inverse for the
  /// incoming direction (is-blocked-by / duplicated-by).
  String get relationLabel => switch ((linkType, direction)) {
    ('blocks', 'incoming') => 'is blocked by',
    ('blocks', _) => 'blocks',
    ('duplicates', 'incoming') => 'is duplicated by',
    ('duplicates', _) => 'duplicates',
    ('relates', _) => 'relates to',
    _ => linkType,
  };
}

/// Fixed issue category enum (single-select, nullable). Wire is snake_case.
enum IssueCategory {
  customerRequest('customer_request', 'Customer request'),
  compliance('compliance', 'Compliance'),
  security('security', 'Security'),
  roadmap('roadmap', 'Roadmap'),
  technicalDebt('technical_debt', 'Technical debt'),
  operational('operational', 'Operational'),
  researchDiscovery('research_discovery', 'Research / Discovery'),
  other('other', 'Other');

  const IssueCategory(this.wire, this.label);
  final String wire;
  final String label;

  static IssueCategory? fromWire(String? wire) {
    if (wire == null) return null;
    for (final c in IssueCategory.values) {
      if (c.wire == wire) return c;
    }
    return null;
  }
}

/// Fixed resolution enum (nullable). Wire is snake_case.
enum IssueResolution {
  fixed('fixed', 'Fixed'),
  wontDo('wont_do', "Won't do"),
  duplicate('duplicate', 'Duplicate'),
  cannotReproduce('cannot_reproduce', 'Cannot reproduce');

  const IssueResolution(this.wire, this.label);
  final String wire;
  final String label;

  static IssueResolution? fromWire(String? wire) {
    if (wire == null) return null;
    for (final r in IssueResolution.values) {
      if (r.wire == wire) return r;
    }
    return null;
  }
}

/// Issue relationship link type (the create direction). Wire is snake_case.
enum IssueLinkType {
  blocks('blocks', 'Blocks'),
  relates('relates', 'Relates to'),
  duplicates('duplicates', 'Duplicates');

  const IssueLinkType(this.wire, this.label);
  final String wire;
  final String label;
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

/// A per-user saved kanban board state. [config] is an opaque blob the board
/// cubit owns (visible columns, order, filter, grouping).
/// A first-class kanban board (personal or shared). `config` is opaque
/// SPA-owned state: visible columns + order, swimlane group, locked filters,
/// and display options.
class Board {
  const Board({
    required this.id,
    required this.projectId,
    required this.visibility,
    required this.name,
    required this.color,
    required this.config,
    required this.order,
    this.key = '',
    this.ownerId,
  });

  factory Board.fromJson(Map<String, dynamic> json) => Board(
    id: json['id'] as String,
    projectId: json['project_id'] as String,
    ownerId: json['owner_id'] as String?,
    visibility: (json['visibility'] as String?) ?? 'personal',
    name: json['name'] as String,
    key: (json['key'] as String?) ?? '',
    color: (json['color'] as String?) ?? '',
    config: (json['config'] as Map<String, dynamic>?) ?? const {},
    order: (json['order'] as num?)?.toDouble() ?? 0.0,
  );

  final String id;
  final String projectId;
  final String? ownerId;
  final String visibility;
  final String name;

  /// Short lowercase slug, unique per project — the board's URL segment.
  final String key;
  final String color;
  final Map<String, dynamic> config;
  final double order;

  bool get isShared => visibility == 'shared';
}

/// One board column (status bucket): total matching count + a capped card slice.
class BoardColumnData {
  const BoardColumnData({
    required this.total,
    required this.cards,
    this.statusId,
  });

  factory BoardColumnData.fromJson(Map<String, dynamic> json) =>
      BoardColumnData(
        statusId: json['status_id'] as String?,
        total: (json['total'] as num?)?.toInt() ?? 0,
        cards: (json['cards'] as List<dynamic>? ?? const [])
            .map((e) => Issue.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final String? statusId;
  final int total;
  final List<Issue> cards;

  bool get hasMore => total > cards.length;
}

/// One swimlane (group value) with its per-column buckets.
class BoardLaneData {
  const BoardLaneData({
    required this.key,
    required this.total,
    required this.columns,
  });

  factory BoardLaneData.fromJson(Map<String, dynamic> json) => BoardLaneData(
    key: (json['key'] as String?) ?? 'none',
    total: (json['total'] as num?)?.toInt() ?? 0,
    columns: (json['columns'] as List<dynamic>? ?? const [])
        .map((e) => BoardColumnData.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  final String key;
  final int total;
  final List<BoardColumnData> columns;
}

/// The per-column board payload — flat `columns` or, when grouped, `lanes`.
class BoardData {
  const BoardData({
    this.group,
    this.columns = const [],
    this.lanes = const [],
    this.cursor = '',
  });

  factory BoardData.fromJson(Map<String, dynamic> json) => BoardData(
    group: json['group'] as String?,
    columns: (json['columns'] as List<dynamic>? ?? const [])
        .map((e) => BoardColumnData.fromJson(e as Map<String, dynamic>))
        .toList(),
    lanes: (json['lanes'] as List<dynamic>? ?? const [])
        .map((e) => BoardLaneData.fromJson(e as Map<String, dynamic>))
        .toList(),
    cursor: (json['cursor'] as String?) ?? '',
  );

  final String? group;
  final List<BoardColumnData> columns;
  final List<BoardLaneData> lanes;

  /// Delta-sync cursor stamped by the server when this payload was read;
  /// empty on older backends.
  final String cursor;

  bool get isGrouped => group != null;
}
