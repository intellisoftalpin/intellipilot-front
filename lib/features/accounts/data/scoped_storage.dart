// `_inner` / `_scope` are intentionally private fields.
// ignore_for_file: prefer_initializing_formals

import 'package:intellipilot/core/storage/hive_boxes.dart';

/// A [KeyValueStorage] that silently namespaces every key by the active
/// account.
///
/// This is a decorator rather than a change to each key builder on purpose.
/// Six different places persist per-user state — the board snapshot cache, the
/// work-item filter store, the My Issues column layout, the rail expanded flag,
/// the boards-section flag, the swimlane collapse set — and all of them key by
/// `(userId, projectId)` with no notion of *which server*. Editing each one
/// would mean six chances to miss a site, and a missed site is exactly the
/// cross-account bleed this exists to prevent. Wrapping the storage instead
/// makes the guarantee structural: a new cache added later is namespaced
/// without its author having to know that accounts exist.
///
/// [scope] is resolved on every call, not captured, so switching accounts takes
/// effect immediately without rebuilding the dependency graph.
class ScopedKeyValueStorage implements KeyValueStorage {
  ScopedKeyValueStorage({
    required KeyValueStorage inner,
    required String Function() scope,
  }) : _inner = inner,
       _scope = scope;

  final KeyValueStorage _inner;
  final String Function() _scope;

  /// Keys are prefixed `acct:<scope>/`. When no account is active the prefix is
  /// `acct:-/`, which keeps pre-account data from being read back under an
  /// account and vice versa.
  String _k(String key) {
    final s = _scope();
    return 'acct:${s.isEmpty ? '-' : s}/$key';
  }

  @override
  T? get<T>(String key) => _inner.get<T>(_k(key));

  @override
  Future<void> set<T>(String key, T value) => _inner.set<T>(_k(key), value);

  @override
  Future<void> remove(String key) => _inner.remove(_k(key));

  /// Clears the **entire underlying box**, not just this scope.
  ///
  /// The interface offers no key enumeration, so a scope-only clear is not
  /// expressible here. Nothing calls this on a scoped box — per-account
  /// eviction goes through the caches' own index-based clears (e.g.
  /// `BoardSnapshotCache.clearAll`, whose index key is itself scoped) — and
  /// this override exists only to satisfy the interface honestly rather than
  /// pretending to be narrower than it is.
  @override
  Future<void> clear() => _inner.clear();
}
