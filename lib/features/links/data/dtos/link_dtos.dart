import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';

/// Jira-standard link types between any two backlog entities. Directional
/// kinds get rendered as their inverse on the target side (`A blocks B` →
/// `B is blocked by A`). `relates` is symmetric — no inverse pair.
enum LinkType {
  blocks('blocks'),
  relates('relates'),
  duplicates('duplicates'),
  clones('clones'),
  causes('causes');

  const LinkType(this.wire);

  /// String token used over the wire. Stable across versions.
  final String wire;

  static LinkType? fromWire(String wire) {
    for (final t in LinkType.values) {
      if (t.wire == wire) return t;
    }
    return null;
  }

  /// True for kinds that read the same in both directions (`relates`).
  bool get isSymmetric => this == LinkType.relates;
}

/// One stored link. The record is single-sided: the inverse side is
/// derived at read time by swapping (source, target) and rendering the
/// inverse label (`blocks` → `is blocked by` etc.).
class EntityLink {
  const EntityLink({
    required this.id,
    required this.projectId,
    required this.sourceKind,
    required this.sourceId,
    required this.targetKind,
    required this.targetId,
    required this.type,
    required this.createdAt,
  });

  factory EntityLink.fromJson(Map<String, dynamic> json) {
    final type = LinkType.fromWire(json['type'] as String);
    if (type == null) {
      throw FormatException('Unknown link type: ${json['type']}');
    }
    final srcKind = EntityKind.fromWire(json['source_kind'] as String);
    final tgtKind = EntityKind.fromWire(json['target_kind'] as String);
    if (srcKind == null || tgtKind == null) {
      throw FormatException(
        'Unknown entity kinds: ${json['source_kind']} / ${json['target_kind']}',
      );
    }
    return EntityLink(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      sourceKind: srcKind,
      sourceId: json['source_id'] as String,
      targetKind: tgtKind,
      targetId: json['target_id'] as String,
      type: type,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String projectId;
  final EntityKind sourceKind;
  final String sourceId;
  final EntityKind targetKind;
  final String targetId;
  final LinkType type;
  final DateTime createdAt;
}

/// Request body for `POST /projects/:id/links`.
class CreateLinkRequest {
  const CreateLinkRequest({
    required this.sourceKind,
    required this.sourceId,
    required this.targetKind,
    required this.targetId,
    required this.type,
  });

  final EntityKind sourceKind;
  final String sourceId;
  final EntityKind targetKind;
  final String targetId;
  final LinkType type;

  Map<String, dynamic> toJson() => {
        'source_kind': sourceKind.wire,
        'source_id': sourceId,
        'target_kind': targetKind.wire,
        'target_id': targetId,
        'type': type.wire,
      };
}
