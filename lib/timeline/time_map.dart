import 'dart:math' as math;

/// Maps times on the ORIGINAL (uncut) timeline to the CUT timeline.
///
/// v1 kept every time on the original timeline and only dropped the removed
/// ranges at export. v2 stores what the viewer sees, so migration shifts each
/// time left by the total length removed before it.
class TimeMap {
  /// Kept ranges on the original timeline: sorted, non-overlapping, [a, b).
  final List<(int, int)> kept;
  final List<int> _offsets; // cut-timeline position of each kept range start

  TimeMap._(this.kept, this._offsets);

  /// Everything kept: identity map over [0, totalMs).
  factory TimeMap.identity(int totalMs) =>
      TimeMap._([(0, math.max(0, totalMs))], [0]);

  /// From removed ranges ([[a, b], …], any order, may overlap) within
  /// [0, totalMs).
  factory TimeMap.fromRemoved(List<List<int>> removed, int totalMs) {
    final total = math.max(0, totalMs);
    final cuts = removed
        .where((r) => r.length == 2)
        .map((r) => (r[0].clamp(0, total), r[1].clamp(0, total)))
        .where((r) => r.$2 > r.$1)
        .toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));
    final kept = <(int, int)>[];
    var cursor = 0;
    for (final c in cuts) {
      if (c.$1 > cursor) kept.add((cursor, c.$1));
      cursor = math.max(cursor, c.$2);
    }
    if (cursor < total) kept.add((cursor, total));
    final offsets = <int>[];
    var acc = 0;
    for (final k in kept) {
      offsets.add(acc);
      acc += k.$2 - k.$1;
    }
    return TimeMap._(kept, offsets);
  }

  int get durationMs =>
      kept.isEmpty ? 0 : _offsets.last + (kept.last.$2 - kept.last.$1);

  /// Cut-timeline time of original [t], or null if [t] was removed.
  int? map(int t) {
    for (int i = 0; i < kept.length; i++) {
      final k = kept[i];
      if (t >= k.$1 && t < k.$2) return _offsets[i] + (t - k.$1);
    }
    if (kept.isNotEmpty && t == kept.last.$2) return durationMs; // the very end
    return null;
  }

  /// Like [map], but a removed time snaps to where the cut is (so ranges that
  /// span a cut just get shorter). Times before 0 → 0, after the end → end.
  int mapClamp(int t) {
    if (kept.isEmpty) return 0;
    if (t <= kept.first.$1) return 0;
    for (int i = 0; i < kept.length; i++) {
      final k = kept[i];
      if (t < k.$1) return _offsets[i]; // inside the cut before kept[i]
      if (t < k.$2) return _offsets[i] + (t - k.$1);
    }
    return durationMs;
  }

  /// Map a range; null when nothing of it is kept.
  (int, int)? mapRange(int a, int b) {
    final s = mapClamp(a), e = mapClamp(b);
    return e > s ? (s, e) : null;
  }
}
