import 'dart:convert';

import '../models/subtitle_style_model.dart';
import '../services/storage_service.dart';
import 'export_plan.dart';
import 'migrate_v1.dart';
import 'project_v1.dart';
import 'timeline_model.dart';

/// Keys that don't change what the video looks like.
const _ignoredForFingerprint = {
  'timelineV2', 'timelineV2Base', 'name', 'thumbnailPath', 'createdAt',
};

/// Stable fingerprint (FNV-1a 64) of a project's v1 content.
String v1Fingerprint(SubtitleProject p) {
  final j = StorageService.projectToJson(p)
    ..removeWhere((k, _) => _ignoredForFingerprint.contains(k));
  final s = jsonEncode(j);
  // FNV offset basis 0xcbf29ce484222325 as a signed 64-bit int (Dart ints
  // wrap at 64 bits on the VM, which is exactly FNV's modulo 2^64).
  var h = -3750763034362895579;
  for (final c in s.codeUnits) {
    h ^= c;
    h *= 0x100000001b3;
  }
  return h.toUnsigned(64).toRadixString(16);
}

/// The v2 timeline for [p]: the saved one when it still matches the v1 data,
/// otherwise a fresh migration (the classic editor changed the project, or it
/// was never opened in the Pro Editor).
ProjectTimeline timelineFor(SubtitleProject p, {String Function()? newId}) {
  final saved = p.timelineV2;
  if (saved != null && p.timelineV2Base == v1Fingerprint(p)) {
    try {
      return ProjectTimeline.fromJson(saved);
    } catch (_) {
      // Unreadable → rebuild from v1 below.
    }
  }
  return migrateV1(p, newId: newId).timeline;
}

/// Write [t] back as a v1 project (for the classic editor / exporter) that
/// also carries the v2 JSON. Identity (id, name, dates, thumbnail) comes from
/// [base].
(SubtitleProject, List<String>) saveTimeline(SubtitleProject base, ProjectTimeline t,
    {Map<String, String> rendered = const {}}) {
  final named = t.copyWith(settings: {...t.settings, 'id': base.id, 'name': base.name});
  // One source file → the file + removed ranges (what the exporter and the
  // classic editor render correctly). Several files need a merge first, so
  // they stay as a multi-clip list until export.
  final plan = ExportPlan.of(named, const {});
  final r = projectToV1(named,
      plan: plan != null && !plan.needsMerge ? plan : null, rendered: rendered);
  final p = r.project
    ..name = base.name
    ..thumbnailPath = base.thumbnailPath
    ..createdAt = base.createdAt;
  p.timelineV2 = t.toJson();
  p.timelineV2Base = v1Fingerprint(p);
  return (p, r.lossy);
}
