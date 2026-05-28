/// A wiki page. `etag` is populated from the response header so callers can
/// round-trip it as `If-Match` for conflict detection on PATCH/DELETE.
class WikiPage {
  const WikiPage({
    required this.id,
    required this.projectId,
    required this.slug,
    required this.title,
    required this.body,
    required this.bodyHtml,
    required this.version,
    required this.createdAt,
    required this.modifiedAt,
    this.editorId,
    this.etag,
  });

  factory WikiPage.fromJson(Map<String, dynamic> json, {String? etag}) =>
      WikiPage(
        id: json['id'] as String,
        projectId: json['project_id'] as String,
        slug: (json['slug'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
        body: (json['body'] as String?) ?? '',
        bodyHtml: (json['body_html'] as String?) ?? '',
        version: (json['version'] as num?)?.toInt() ?? 0,
        editorId: json['editor_id'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        modifiedAt: DateTime.parse(json['modified_at'] as String),
        etag: etag,
      );

  final String id;
  final String projectId;
  final String slug;
  final String title;
  final String body;
  final String bodyHtml;
  final int version;
  final String? editorId;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final String? etag;
}

/// One revision of a wiki page. `body` is only present when a single
/// revision is fetched; listings omit it to keep the payload small.
class WikiRevision {
  const WikiRevision({
    required this.id,
    required this.pageId,
    required this.rev,
    required this.title,
    required this.createdAt,
    this.body,
    this.editorId,
  });

  factory WikiRevision.fromJson(Map<String, dynamic> json) => WikiRevision(
    id: json['id'] as String,
    pageId: json['page_id'] as String,
    rev: (json['rev'] as num?)?.toInt() ?? 0,
    title: (json['title'] as String?) ?? '',
    body: json['body'] as String?,
    editorId: json['editor_id'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final String id;
  final String pageId;
  final int rev;
  final String title;
  final String? body;
  final String? editorId;
  final DateTime createdAt;
}

/// Server response of `GET /…/revisions/{from}/diff?to=`. The `diff` field
/// holds a unified-diff text the UI renders inline with +/-/context line
/// shading.
class WikiDiff {
  const WikiDiff({required this.from, required this.diff, this.to});

  factory WikiDiff.fromJson(Map<String, dynamic> json) => WikiDiff(
    from: (json['from'] as num?)?.toInt() ?? 0,
    to: (json['to'] as num?)?.toInt(),
    diff: (json['diff'] as String?) ?? '',
  );

  final int from;
  final int? to;
  final String diff;
}

class CreateWikiPageRequest {
  const CreateWikiPageRequest({
    required this.title,
    this.slug,
    this.body = '',
  });
  final String title;
  final String? slug;
  final String body;

  Map<String, dynamic> toJson() => {
    'title': title,
    if (slug != null && slug!.isNotEmpty) 'slug': slug,
    'body': body,
  };
}

class UpdateWikiPageRequest {
  const UpdateWikiPageRequest({this.title, this.body});
  final String? title;
  final String? body;

  Map<String, dynamic> toJson() => {
    if (title != null) 'title': title,
    if (body != null) 'body': body,
  };
}
