import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/subtitle_style_model.dart';
import '../services/storage_service.dart';

class ProjectProvider extends ChangeNotifier {
  final List<SubtitleProject> _projects = [];
  SubtitleProject? _currentProject;
  final _uuid = const Uuid();
  bool _loaded = false;

  // Undo / Redo stacks (snapshots of segment list and sfx blocks)
  final List<ProjectSnapshot> _undoStack = [];
  final List<ProjectSnapshot> _redoStack = [];

  // Whether to show translated subtitles in preview
  bool showTranslation = false;

  List<SubtitleProject> get projects => List.unmodifiable(_projects);
  SubtitleProject? get currentProject => _currentProject;
  bool get isLoaded => _loaded;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  Future<void> loadFromStorage() async {
    if (_loaded) return;
    final saved = await StorageService.loadProjects();
    _projects.clear();
    _projects.addAll(saved);
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    await StorageService.saveProjects(_projects);
  }

  SubtitleProject createProject(String name) {
    final project = SubtitleProject(
      id: _uuid.v4(),
      name: name,
      selectedStyle: subtitlePresets.first,
    );
    _projects.insert(0, project);
    _currentProject = project;
    _persist();
    notifyListeners();
    return project;
  }

  void setCurrentProject(SubtitleProject project) {
    _currentProject = project;
    showTranslation = project.showBilingual;
    _undoStack.clear();
    _redoStack.clear();
    notifyListeners();
  }

  void updateProject(SubtitleProject updated) {
    final index = _projects.indexWhere((p) => p.id == updated.id);
    if (index != -1) {
      _projects[index] = updated;
      if (_currentProject?.id == updated.id) _currentProject = updated;
      _persist();
      notifyListeners();
    }
  }

  void renameProject(String id, String name) {
    final p = _projects.firstWhere((p) => p.id == id, orElse: () => _projects.first);
    p.name = name.trim().isEmpty ? p.name : name.trim();
    _persist();
    notifyListeners();
  }

  SubtitleProject duplicateProject(SubtitleProject src) {
    final copy = SubtitleProject(
      id: _uuid.v4(),
      name: '${src.name} (ສຳເນົາ)',
      videoPath: src.videoPath,
      thumbnailPath: src.thumbnailPath,
      aspectRatio: src.aspectRatio,
      selectedStyle: src.selectedStyle,
      wordSplit: src.wordSplit,
      translateMode: src.translateMode,
      segments: src.segments.map((s) => s.copy()).toList(),
      videoDuration: src.videoDuration,
      language: src.language,
      sourceLanguage: src.sourceLanguage,
      fontSize: src.fontSize,
      fontWeight: src.fontWeight,
      subtitlePositionY: src.subtitlePositionY,
      fontFamily: src.fontFamily,
      isKaraokeHighlight: src.isKaraokeHighlight,
      karaokeHighlightColor: src.karaokeHighlightColor,
      bilingualPresetIndex: src.bilingualPresetIndex,
      bilingualFontSize: src.bilingualFontSize,
      bilingualGap: src.bilingualGap,
      showBilingual: src.showBilingual,
      subtitleAnimation: src.subtitleAnimation,
    );
    final idx = _projects.indexWhere((p) => p.id == src.id);
    _projects.insert(idx < 0 ? 0 : idx + 1, copy);
    _persist();
    notifyListeners();
    return copy;
  }

  void deleteProject(String id) {
    _projects.removeWhere((p) => p.id == id);
    if (_currentProject?.id == id) _currentProject = null;
    _persist();
    notifyListeners();
  }

  ProjectSnapshot _snapshot() => ProjectSnapshot(
        _currentProject!.segments.map((s) => s.copy()).toList(),
        _currentProject!.sfxBlocks.map((s) => s.copy()).toList(),
        _currentProject!.removedRanges.map((r) => List<int>.from(r)).toList(),
        List<int>.from(_currentProject!.splitPointsMs),
        _currentProject!.imageOverlays.map((o) => o.copy()).toList(),
        _currentProject!.zoomEffects.map((z) => z.copy()).toList(),
        _currentProject!.fadeEffects.map((f) => f.copy()).toList(),
        _currentProject!.shakeEffects.map((s) => s.copy()).toList(),
      );

  void _restore(ProjectSnapshot snap) {
    _currentProject!.segments = snap.segments;
    _currentProject!.sfxBlocks = snap.sfxBlocks;
    _currentProject!.removedRanges =
        snap.removedRanges.map((r) => List<int>.from(r)).toList();
    _currentProject!.splitPointsMs = List<int>.from(snap.splitPointsMs);
    _currentProject!.imageOverlays =
        snap.imageOverlays.map((o) => o.copy()).toList();
    _currentProject!.zoomEffects =
        snap.zoomEffects.map((z) => z.copy()).toList();
    _currentProject!.fadeEffects =
        snap.fadeEffects.map((f) => f.copy()).toList();
    _currentProject!.shakeEffects =
        snap.shakeEffects.map((s) => s.copy()).toList();
  }

  void addImageOverlay(ImageOverlay o) {
    if (_currentProject == null) return;
    _pushHistory();
    _currentProject!.imageOverlays.add(o);
    commit();
  }

  void removeImageOverlay(String id) {
    if (_currentProject == null) return;
    _pushHistory();
    _currentProject!.imageOverlays.removeWhere((o) => o.id == id);
    commit();
  }

  void addZoomEffect(ZoomEffect z) {
    if (_currentProject == null) return;
    _pushHistory();
    // Remove any existing zoom overlapping the same range (one zoom per span).
    _currentProject!.zoomEffects.removeWhere((e) =>
        z.startTime < e.endTime && e.startTime < z.endTime);
    _currentProject!.zoomEffects.add(z);
    commit();
  }

  void removeZoomEffect(String id) {
    if (_currentProject == null) return;
    _pushHistory();
    _currentProject!.zoomEffects.removeWhere((z) => z.id == id);
    commit();
  }

  void addFadeEffect(FadeEffect f) {
    if (_currentProject == null) return;
    _pushHistory();
    _currentProject!.fadeEffects.add(f);
    commit();
  }

  void removeFadeEffectsIn(int startMs, int endMs) {
    if (_currentProject == null) return;
    _pushHistory();
    _currentProject!.fadeEffects.removeWhere((f) =>
        f.startTime.inMilliseconds < endMs &&
        startMs < f.endTime.inMilliseconds);
    commit();
  }

  void addShakeEffect(ShakeEffect s) {
    if (_currentProject == null) return;
    _pushHistory();
    _currentProject!.shakeEffects.removeWhere((e) =>
        s.startTime < e.endTime && e.startTime < s.endTime);
    _currentProject!.shakeEffects.add(s);
    commit();
  }

  void removeShakeEffectsIn(int startMs, int endMs) {
    if (_currentProject == null) return;
    _pushHistory();
    _currentProject!.shakeEffects.removeWhere((s) =>
        s.startTime.inMilliseconds < endMs &&
        startMs < s.endTime.inMilliseconds);
    commit();
  }

  void _pushHistory() {
    if (_currentProject == null) return;
    _undoStack.add(_snapshot());
    _redoStack.clear();
    if (_undoStack.length > 30) _undoStack.removeAt(0);
  }

  void updateSegments(List<SubtitleSegment> segments, {bool recordHistory = true}) {
    if (_currentProject == null) return;
    if (recordHistory) _pushHistory();
    _currentProject!.segments = segments;
    final index = _projects.indexWhere((p) => p.id == _currentProject!.id);
    if (index != -1) _projects[index] = _currentProject!;
    _persist();
    notifyListeners();
  }

  void undo() {
    if (_undoStack.isEmpty || _currentProject == null) return;
    _redoStack.add(_snapshot());
    _restore(_undoStack.removeLast());
    final index = _projects.indexWhere((p) => p.id == _currentProject!.id);
    if (index != -1) _projects[index] = _currentProject!;
    _persist();
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty || _currentProject == null) return;
    _undoStack.add(_snapshot());
    _restore(_redoStack.removeLast());
    final index = _projects.indexWhere((p) => p.id == _currentProject!.id);
    if (index != -1) _projects[index] = _currentProject!;
    _persist();
    notifyListeners();
  }

  void addSfxBlock(SfxBlock block) {
    if (_currentProject == null) return;
    _pushHistory();
    _currentProject!.sfxBlocks.add(block);
    _currentProject!.sfxBlocks.sort((a, b) => a.startTime.compareTo(b.startTime));
    commit();
  }

  void removeSfxBlock(String id) {
    if (_currentProject == null) return;
    _pushHistory();
    _currentProject!.sfxBlocks.removeWhere((b) => b.id == id);
    commit();
  }

  void updateSfxBlocks(List<SfxBlock> blocks, {bool recordHistory = true}) {
    if (_currentProject == null) return;
    if (recordHistory) _pushHistory();
    _currentProject!.sfxBlocks = blocks;
    commit();
  }

  void toggleShowTranslation() {
    showTranslation = !showTranslation;
    notifyListeners();
  }

  /// Snapshot current segments for undo (call once before a drag gesture).
  void pushHistory() => _pushHistory();

  /// Lightweight rebuild during a drag (no disk write).
  void liveUpdate() => notifyListeners();

  /// Persist + rebuild after a drag gesture ends.
  void commit() {
    if (_currentProject == null) return;
    final i = _projects.indexWhere((p) => p.id == _currentProject!.id);
    if (i != -1) _projects[i] = _currentProject!;
    _persist();
    notifyListeners();
  }

  /// Shift every segment (and its word timings) by [delta] to re-sync the whole
  /// track against the audio. Times are clamped to be non-negative.
  void shiftAllSegments(Duration delta, {bool recordHistory = true}) {
    if (_currentProject == null) return;
    final segs = _currentProject!.segments;
    if (segs.isEmpty || delta == Duration.zero) return;
    if (recordHistory) _pushHistory();
    Duration clamp(Duration d) => d < Duration.zero ? Duration.zero : d;
    for (final s in segs) {
      s.startTime = clamp(s.startTime + delta);
      s.endTime = clamp(s.endTime + delta);
      if (s.wordTimings != null) {
        s.wordTimings = s.wordTimings!.map((t) => clamp(t + delta)).toList();
      }
    }
    final index = _projects.indexWhere((p) => p.id == _currentProject!.id);
    if (index != -1) _projects[index] = _currentProject!;
    _persist();
    notifyListeners();
  }
}

class ProjectSnapshot {
  final List<SubtitleSegment> segments;
  final List<SfxBlock> sfxBlocks;
  final List<List<int>> removedRanges;
  final List<int> splitPointsMs;
  final List<ImageOverlay> imageOverlays;
  final List<ZoomEffect> zoomEffects;
  final List<FadeEffect> fadeEffects;
  final List<ShakeEffect> shakeEffects;
  ProjectSnapshot(
    this.segments,
    this.sfxBlocks, [
    this.removedRanges = const [],
    this.splitPointsMs = const [],
    this.imageOverlays = const [],
    this.zoomEffects = const [],
    this.fadeEffects = const [],
    this.shakeEffects = const [],
  ]);
}
