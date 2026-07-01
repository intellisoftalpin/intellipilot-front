/// One row from `GET /api/v1/search`. Field names mirror the backend JSON.
class SearchResult {
  const SearchResult({
    required this.entityType,
    required this.entityId,
    required this.projectId,
    required this.title,
    required this.snippet,
    required this.rank,
    this.ref,
  });

  factory SearchResult.fromJson(Map<String, dynamic> j) => SearchResult(
    entityType: j['entity_type'] as String? ?? '',
    entityId: j['entity_id'] as String? ?? '',
    projectId: j['project_id'] as String? ?? '',
    ref: (j['ref'] as num?)?.toInt(),
    title: j['title'] as String? ?? '',
    snippet: j['snippet'] as String? ?? '',
    rank: (j['rank'] as num?)?.toDouble() ?? 0,
  );

  /// `issue` | `epic` | `wiki` | `comment`.
  final String entityType;
  final String entityId;
  final String projectId;
  final int? ref;
  final String title;

  /// HTML fragment with `<mark>` highlights around the match.
  final String snippet;
  final double rank;
}

/// Envelope returned by the search endpoint.
class SearchResponse {
  const SearchResponse({required this.results, required this.fuzzy});

  factory SearchResponse.fromJson(Map<String, dynamic> j) => SearchResponse(
    results: (j['results'] as List<dynamic>? ?? const [])
        .map((e) => SearchResult.fromJson(e as Map<String, dynamic>))
        .toList(),
    fuzzy: j['fuzzy'] as bool? ?? false,
  );

  final List<SearchResult> results;

  /// True when the backend fell back to a fuzzy match (no exact hits).
  final bool fuzzy;
}
