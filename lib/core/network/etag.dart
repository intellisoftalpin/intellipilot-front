/// The backend's strong ETag is deterministic: `"<id>:<version>"`. We
/// reconstruct it from the response *body* rather than trusting the `ETag`
/// response header, because reverse proxies (e.g. nginx when it gzips JSON)
/// silently weaken a strong ETag to `W/"..."` — which then fails the strong
/// `If-Match` comparison the API performs, yielding 412 on every update. The
/// body is never altered in transit, so the reconstructed token round-trips
/// correctly through any proxy. Falls back to [headerEtag] only when id or
/// version are absent from the body.
String? canonicalEtag(Map<String, dynamic> json, String? headerEtag) {
  final id = json['id'];
  final version = json['version'];
  if (id is String && version is num) return '"$id:${version.toInt()}"';
  return headerEtag;
}
