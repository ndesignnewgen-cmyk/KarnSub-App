import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/subtitle_style_model.dart';
import '../services/storage_service.dart';

class ProjectProvider extends ChangeNotifier {
  final List<SubtitleProject> _projects = [];
  SubtitleProject? _currentProject;
  final _uuid = const Uuid();
  bool _loaded = false;

  // Undo / Redo stacks (snapshots of segment list)
  final List<List<SubtitleSegment>> _undoStack = [];
  final List<List<SubtitleSegment>> _redoStack = [];

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

  void _pushHistory() {
    if (_currentProject == null) return;
    _undoStack.add(_currentProject!.segments.map((s) => s.copy()).toList());
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
    _redoStack.add(_currentProject!.segments.map((s) => s.copy()).toList());
    _currentProject!.segments = _undoStack.removeLast();
    final index = _projects.indexWhere((p) => p.id == _currentProject!.id);
    if (index != -1) _projects[index] = _currentProject!;
    _persist();
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty || _currentProject == null) return;
    _undoStack.add(_currentProject!.segments.map((s) => s.copy()).toList());
    _currentProject!.segments = _redoStack.removeLast();
    final index = _projects.indexWhere((p) => p.id == _currentProject!.id);
    if (index != -1) _projects[index] = _currentProject!;
    _persist();
    notifyListeners();
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
