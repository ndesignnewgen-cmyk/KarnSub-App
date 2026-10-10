import 'dart:math' as math;

import 'timeline_model.dart';

/// How to hand the edited main track to the existing exporter, which renders
/// ONE video file and drops `removedRanges` (on that file's own clock).
///
///  * single source, clips in increasing order (cut/trim/split one video —
///    the common case): the source file + removed ranges, no extra work;
///  * anything else (several files, or one file re-ordered/repeated): the
///    pieces' files are concatenated natively ([mergePaths], one entry per
///    piece, in timeline order) and the trims become removed ranges on the
///    merged file.
///
/// [toOriginal] / [toOriginalEnd] map TIMELINE ms onto the file's clock.
class ExportPlan {
  final String? singleSource;
  final List<String> mergePaths;
  final List<({int start, int end, int origStart})> _pieces;
  final List<List<int>> removed;
  final int originalMs;

  /// Set after the merge (or = [singleSource]).
  String? videoPath;

  ExportPlan._(this.singleSource, this.mergePaths, this._pieces, this.removed, this.originalMs)
      : videoPath = singleSource;

  bool get needsMerge => mergePaths.isNotEmpty;

  /// File time of a timeline START (a time on a cut belongs to the next piece).
  int toOriginal(int ms) {
    for (final p in _pieces) {
      if (ms < p.end) return p.origStart + math.max(0, ms - p.start);
    }
    final last = _pieces.last;
    return last.origStart + (last.end - last.start);
  }

  /// File time of a timeline END (a time on a cut belongs to the piece before).
  int toOriginalEnd(int ms) {
    for (final p in _pieces) {
      if (ms <= p.end) return p.origStart + math.max(0, ms - p.start);
    }
    final last = _pieces.last;
    return last.origStart + (last.end - last.start);
  }

  /// Build the plan. [sourceMs] gives each source file's full length (needed
  /// for the removed tails); a missing entry falls back to the piece's end.
  static ExportPlan? of(ProjectTimeline t, Map<String, int> sourceMs) {
    final clips = t.mainTrack?.elements.whereType<VideoElement>().toList() ?? const [];
    if (clips.isEmpty) return null;

    int full(VideoElement c) => math.max(sourceMs[c.src] ?? c.sourceMs ?? c.trimOutMs, c.trimOutMs);

    final single = clips.every((c) => c.src == clips.first.src) &&
        [for (var i = 1; i < clips.length; i++) clips[i].trimInMs >= clips[i - 1].trimOutMs]
            .every((ok) => ok);

    if (single) {
      final total = full(clips.first);
      final removed = <List<int>>[];
      var cursor = 0;
      final pieces = <({int start, int end, int origStart})>[];
      for (final c in clips) {
        if (c.trimInMs > cursor) removed.add([cursor, c.trimInMs]);
        pieces.add((start: c.startMs, end: c.endMs, origStart: c.trimInMs));
        cursor = c.trimOutMs;
      }
      if (total > cursor) removed.add([cursor, total]);
      return ExportPlan._(clips.first.src, const [], pieces, removed, total);
    }

    // Concatenate each piece's whole file, in timeline order.
    final removed = <List<int>>[];
    final pieces = <({int start, int end, int origStart})>[];
    var offset = 0;
    for (final c in clips) {
      final f = full(c);
      if (c.trimInMs > 0) removed.add([offset, offset + c.trimInMs]);
      if (f > c.trimOutMs) removed.add([offset + c.trimOutMs, offset + f]);
      pieces.add((start: c.startMs, end: c.endMs, origStart: offset + c.trimInMs));
      offset += f;
    }
    return ExportPlan._(null, [for (final c in clips) c.src], pieces, removed, offset);
  }
}
