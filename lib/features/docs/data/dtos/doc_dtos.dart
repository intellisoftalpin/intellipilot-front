/// Wire models for external documentation sources.
///
/// Mirrors `crates/core/src/docs.rs`. Every field the server may omit is
/// nullable here rather than defaulted, so "absent" and "empty" stay
/// distinguishable — the difference matters for `head_commit`, which is what
/// tells the UI a source has never finished its first sync.
library;

/// What a documentation source points at.
enum DocSourceKind {
  /// A git repository, browsed and (with a write key) edited in place.
  git,

  /// A plain URL shown in a frame. Read-only by construction — there is no
  /// repository behind it to push to.
  web;

  static DocSourceKind parse(String? raw) =>
      raw == 'web' ? DocSourceKind.web : DocSourceKind.git;

  bool get isWeb => this == DocSourceKind.web;
}

/// Lifecycle of a source's server-side cache.
enum DocCacheStatus {
  pending,
  syncing,
  ready,
  error;

  static DocCacheStatus parse(String? raw) => switch (raw) {
    'syncing' => DocCacheStatus.syncing,
    'ready' => DocCacheStatus.ready,
    'error' => DocCacheStatus.error,
    _ => DocCacheStatus.pending,
  };
}

class DocSource {
  const DocSource({
    required this.id,
    required this.projectId,
    required this.name,
    required this.kind,
    required this.webUrl,
    required this.docPath,
    required this.readOnly,
    required this.hidden,
    required this.order,
    required this.color,
    required this.emoji,
    required this.cacheStatus,
    required this.cacheBytes,
    required this.version,
    required this.createdAt,
    required this.modifiedAt,
    this.sshUrl,
    this.branch,
    this.sshKeyId,
    this.cacheError,
    this.headCommit,
    this.lastSyncedAt,
    this.lastAttemptAt,
    this.hostFingerprint,
  });

  factory DocSource.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final version = (json['version'] as num?)?.toInt() ?? 1;
    return DocSource(
      id: id,
      projectId: json['project_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      kind: DocSourceKind.parse(json['kind'] as String?),
      sshUrl: json['ssh_url'] as String?,
      webUrl: json['web_url'] as String? ?? '',
      branch: json['branch'] as String?,
      docPath: json['doc_path'] as String? ?? '',
      sshKeyId: json['ssh_key_id'] as String?,
      readOnly: json['read_only'] as bool? ?? false,
      hidden: json['hidden'] as bool? ?? false,
      order: (json['order'] as num?)?.toDouble() ?? 0,
      color: json['color'] as String? ?? '',
      emoji: json['emoji'] as String? ?? '',
      cacheStatus: DocCacheStatus.parse(json['cache_status'] as String?),
      cacheError: json['cache_error'] as String?,
      headCommit: json['head_commit'] as String?,
      cacheBytes: (json['cache_bytes'] as num?)?.toInt() ?? 0,
      lastSyncedAt: _date(json['last_synced_at']),
      lastAttemptAt: _date(json['last_attempt_at']),
      hostFingerprint: json['host_fingerprint'] as String?,
      version: version,
      createdAt: _date(json['created_at']) ?? DateTime.now(),
      modifiedAt: _date(json['modified_at']) ?? DateTime.now(),
    );
  }

  final String id;
  final String projectId;

  /// The user-set title. This is what the rail, the overview tile, the
  /// breadcrumb and (for a web link) the open-in-new-tab label all show.
  final String name;
  final DocSourceKind kind;

  /// Null for a web link, which has no repository.
  final String? sshUrl;

  /// For a git source, the browse base on the host. For a web link, the page
  /// itself. Always set.
  final String webUrl;

  /// Null for a web link.
  final String? branch;

  /// Subtree shared with readers; empty means the whole repository, and
  /// always empty for a web link.
  final String docPath;
  final String? sshKeyId;

  /// Pinned never-editable, independently of who holds a write key. Always
  /// true for a web link.
  final bool readOnly;

  /// Withdrawn from navigation while keeping its configuration. Only visible
  /// to callers who can manage sources, so a non-manager never sees one.
  final bool hidden;
  final double order;
  final String color;
  final String emoji;
  final DocCacheStatus cacheStatus;
  final String? cacheError;
  final String? headCommit;
  final int cacheBytes;
  final DateTime? lastSyncedAt;
  final DateTime? lastAttemptAt;
  final String? hostFingerprint;
  final int version;
  final DateTime createdAt;
  final DateTime modifiedAt;

  /// `"id:version"`, the `If-Match` value a PATCH must present.
  String get etag => '"$id:$version"';

  /// Has this source ever produced servable content? A failed refresh keeps
  /// the previous commit, so an error alone does not make it unreadable.
  ///
  /// A web link is always "ready": the browser fetches the page live, so
  /// there is no cache to wait for.
  bool get hasContent =>
      kind.isWeb || (headCommit != null && headCommit!.isNotEmpty);

  /// Whether this source is browsed through the API (a git tree) rather than
  /// embedded directly.
  bool get isBrowsable => kind == DocSourceKind.git;

  DocSource copyWith({String? name, double? order, bool? hidden}) => DocSource(
    id: id,
    projectId: projectId,
    name: name ?? this.name,
    kind: kind,
    sshUrl: sshUrl,
    webUrl: webUrl,
    branch: branch,
    docPath: docPath,
    sshKeyId: sshKeyId,
    readOnly: readOnly,
    hidden: hidden ?? this.hidden,
    order: order ?? this.order,
    color: color,
    emoji: emoji,
    cacheStatus: cacheStatus,
    cacheError: cacheError,
    headCommit: headCommit,
    cacheBytes: cacheBytes,
    lastSyncedAt: lastSyncedAt,
    lastAttemptAt: lastAttemptAt,
    hostFingerprint: hostFingerprint,
    version: version,
    createdAt: createdAt,
    modifiedAt: modifiedAt,
  );
}

/// Kind of a node in the documentation tree.
enum DocEntryKind { dir, doc }

class DocEntry {
  const DocEntry({
    required this.path,
    required this.name,
    required this.kind,
    required this.children,
    this.size,
  });

  factory DocEntry.fromJson(Map<String, dynamic> json) {
    final rawChildren = json['children'] as List<dynamic>? ?? const [];
    return DocEntry(
      path: json['path'] as String? ?? '',
      name: json['name'] as String? ?? '',
      kind: (json['kind'] as String?) == 'dir'
          ? DocEntryKind.dir
          : DocEntryKind.doc,
      size: (json['size'] as num?)?.toInt(),
      children: rawChildren
          .map((e) => DocEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Path relative to the shared folder — never to the repository root, so
  /// the layout above it is not even implied.
  final String path;
  final String name;
  final DocEntryKind kind;
  final int? size;
  final List<DocEntry> children;

  bool get isDir => kind == DocEntryKind.dir;
}

class DocTree {
  const DocTree({
    required this.sourceId,
    required this.commit,
    required this.entries,
    this.entryPath,
  });

  factory DocTree.fromJson(Map<String, dynamic> json) {
    final raw = json['entries'] as List<dynamic>? ?? const [];
    return DocTree(
      sourceId: json['source_id'] as String? ?? '',
      commit: json['commit'] as String? ?? '',
      entries: raw
          .map((e) => DocEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      entryPath: json['entry_path'] as String?,
    );
  }

  final String sourceId;
  final String commit;
  final List<DocEntry> entries;

  /// Homepage of this source, or null when it has no obvious entry point and
  /// the reader should be shown the folder listing.
  final String? entryPath;

  bool get isEmpty => entries.isEmpty;

  /// Depth-first list of every document, used for prev/next and search.
  List<DocEntry> get documents {
    final out = <DocEntry>[];
    void walk(List<DocEntry> level) {
      for (final e in level) {
        if (e.isDir) {
          walk(e.children);
        } else {
          out.add(e);
        }
      }
    }

    walk(entries);
    return out;
  }
}

class DocCommitInfo {
  const DocCommitInfo({
    required this.sha,
    required this.authorName,
    required this.message,
    required this.committedAt,
  });

  factory DocCommitInfo.fromJson(Map<String, dynamic> json) => DocCommitInfo(
    sha: json['sha'] as String? ?? '',
    authorName: json['author_name'] as String? ?? '',
    message: json['message'] as String? ?? '',
    committedAt: _date(json['committed_at']) ?? DateTime.now(),
  );

  final String sha;
  final String authorName;
  final String message;
  final DateTime committedAt;

  String get shortSha => sha.length > 7 ? sha.substring(0, 7) : sha;
}

class DocContent {
  const DocContent({
    required this.sourceId,
    required this.path,
    required this.body,
    required this.blobOid,
    required this.commit,
    required this.canEdit,
    this.lastCommit,
  });

  factory DocContent.fromJson(Map<String, dynamic> json) {
    final last = json['last_commit'] as Map<String, dynamic>?;
    return DocContent(
      sourceId: json['source_id'] as String? ?? '',
      path: json['path'] as String? ?? '',
      body: json['body'] as String? ?? '',
      blobOid: json['blob_oid'] as String? ?? '',
      commit: json['commit'] as String? ?? '',
      canEdit: json['can_edit'] as bool? ?? false,
      lastCommit: last == null ? null : DocCommitInfo.fromJson(last),
    );
  }

  final String sourceId;
  final String path;
  final String body;

  /// Blob OID, presented as `If-Match` when saving.
  final String blobOid;
  final String commit;

  /// True only when the source is writable, the caller holds
  /// `doc_source.modify`, and they have registered a personal write key.
  final bool canEdit;
  final DocCommitInfo? lastCommit;

  String get etag => '"$blobOid"';

  /// Final path segment, for titles and breadcrumbs.
  String get fileName => path.split('/').last;
}

/// A user's write key for one project. The private half never crosses the
/// wire, so there is no field for it here.
class DocUserKey {
  const DocUserKey({
    required this.id,
    required this.keyType,
    required this.publicKey,
    required this.fingerprint,
    required this.origin,
    required this.createdAt,
  });

  factory DocUserKey.fromJson(Map<String, dynamic> json) => DocUserKey(
    id: json['id'] as String? ?? '',
    keyType: json['key_type'] as String? ?? '',
    publicKey: json['public_key'] as String? ?? '',
    fingerprint: json['fingerprint'] as String? ?? '',
    origin: json['origin'] as String? ?? 'generated',
    createdAt: _date(json['created_at']) ?? DateTime.now(),
  );

  final String id;
  final String keyType;

  /// Register this with the git host so pushes authenticate as its owner.
  final String publicKey;
  final String fingerprint;

  /// `generated` or `imported`.
  final String origin;
  final DateTime createdAt;

  bool get isImported => origin == 'imported';
}

class CreateDocSourceRequest {
  /// A git repository: needs a URL, a branch and a key.
  const CreateDocSourceRequest({
    required this.name,
    required String this.sshUrl,
    required this.webUrl,
    required String this.branch,
    this.docPath = '',
    this.sshKeyId,
    this.newKeyName,
    this.readOnly = false,
    this.color = '',
    this.emoji = '',
  }) : kind = DocSourceKind.git;

  /// A web link: a title and a URL, nothing else. Always read-only — there is
  /// no repository behind it to write to.
  const CreateDocSourceRequest.web({
    required this.name,
    required this.webUrl,
    this.color = '',
    this.emoji = '',
  }) : kind = DocSourceKind.web,
       sshUrl = null,
       branch = null,
       docPath = '',
       sshKeyId = null,
       newKeyName = null,
       readOnly = true;

  /// The user-set title shown wherever this source appears.
  final String name;
  final DocSourceKind kind;
  final String? sshUrl;
  final String webUrl;
  final String? branch;
  final String docPath;

  /// Reuse an existing project deploy key…
  final String? sshKeyId;

  /// …or have one generated inline under this name.
  final String? newKeyName;
  final bool readOnly;
  final String color;
  final String emoji;

  /// Only the fields belonging to this kind are sent: the server rejects a
  /// request that mixes them, rather than quietly ignoring the strays.
  Map<String, dynamic> toJson() => {
    'name': name,
    'kind': kind.name,
    'web_url': webUrl,
    if (kind == DocSourceKind.git) ...{
      'ssh_url': sshUrl,
      'branch': branch,
      'doc_path': docPath,
      if (sshKeyId != null) 'ssh_key_id': sshKeyId,
      if (sshKeyId == null && newKeyName != null)
        'new_key': {'name': newKeyName, 'read_only': true},
      'read_only': readOnly,
    },
    if (color.isNotEmpty) 'color': color,
    if (emoji.isNotEmpty) 'emoji': emoji,
  };
}

/// A partial edit. Only the fields present are sent, so a PATCH never
/// overwrites something the form did not touch.
class UpdateDocSourceRequest {
  const UpdateDocSourceRequest({
    this.name,
    this.webUrl,
    this.branch,
    this.docPath,
    this.sshKeyId,
    this.readOnly,
    this.hidden,
    this.order,
    this.color,
    this.emoji,
  });

  final String? name;
  final String? webUrl;
  final String? branch;
  final String? docPath;
  final String? sshKeyId;
  final bool? readOnly;

  /// Withdraw the source from navigation, or put it back.
  final bool? hidden;
  final double? order;
  final String? color;
  final String? emoji;

  Map<String, dynamic> toJson() => {
    if (name != null) 'name': name,
    if (webUrl != null) 'web_url': webUrl,
    if (branch != null) 'branch': branch,
    if (docPath != null) 'doc_path': docPath,
    if (sshKeyId != null) 'ssh_key_id': sshKeyId,
    if (readOnly != null) 'read_only': readOnly,
    if (hidden != null) 'hidden': hidden,
    if (order != null) 'order': order,
    if (color != null) 'color': color,
    if (emoji != null) 'emoji': emoji,
  };
}

DateTime? _date(Object? raw) =>
    raw is String && raw.isNotEmpty ? DateTime.tryParse(raw) : null;
