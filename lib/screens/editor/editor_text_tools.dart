part of '../editor_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

/// Text tools: filler-word removal, text edit sheet.
/// Split out of editor_screen.dart verbatim (phase 0) — the
/// fields and lifecycle stay in [_EditorScreenState].
extension _EditorTextTools on _EditorScreenState {
  void _autoRemoveFiller(ProjectProvider provider) {
    final project = provider.currentProject;
    if (project == null || project.segments.isEmpty) {
      _toast(tr('ed.textEditNoWords'));
      return;
    }
    _pauseForEdit();
    final n = _applyWordRemoval(
      provider,
      remove: (seg, i) => _fillerWords.contains(_normFiller(seg.words![i])),
      removeWhole: (seg) => _fillerWords.contains(_normFiller(seg.text)),
    );
    _toast(n == 0 ? tr('ed.fillerNone') : tr('ed.fillerDone', {'n': n}));
  }

  /// Core word-removal engine shared by "remove filler" and "text-based edit".
  /// For each kept-timing word where [remove] returns true, its time span is
  /// cut (added to removedRanges, the proven manual-cut path) and the word is
  /// stripped from the caption. [removeWhole] handles segments without per-word
  /// timings (whole-segment drop). Returns how many words were removed.
  int _applyWordRemoval(
    ProjectProvider provider, {
    required bool Function(SubtitleSegment seg, int wordIndex) remove,
    bool Function(SubtitleSegment seg)? removeWhole,
  }) {
    final project = provider.currentProject;
    if (project == null || project.segments.isEmpty) return 0;

    final newRanges = <List<int>>[];
    final rebuilt = <SubtitleSegment>[];
    int removedCount = 0;

    for (final seg in project.segments) {
      final words = seg.words;
      final timings = seg.wordTimings;

      if (words != null &&
          timings != null &&
          words.length == timings.length &&
          words.isNotEmpty) {
        final keep = <int>[];
        for (int i = 0; i < words.length; i++) {
          if (remove(seg, i)) {
            int start = timings[i].inMilliseconds;
            int end = (i + 1 < timings.length)
                ? timings[i + 1].inMilliseconds
                : seg.endTime.inMilliseconds;
            // Inset the cut edges slightly so we slice inside the word, not at
            // its exact boundary — word timings are ~±50ms estimates, and a cut
            // landing mid-phoneme of the NEIGHBOUR word sounds like a click.
            if (end - start > 200) {
              start += 40;
              end -= 40;
            }
            if (end > start) newRanges.add([start, end]);
            removedCount++;
          } else {
            keep.add(i);
          }
        }
        if (keep.length == words.length) {
          rebuilt.add(seg); // nothing removed here
          continue;
        }
        if (keep.isEmpty) {
          newRanges.add(
              [seg.startTime.inMilliseconds, seg.endTime.inMilliseconds]);
          continue;
        }
        final newWords = [for (final i in keep) words[i]];
        final newTimings = [for (final i in keep) timings[i]];
        final indexMap = {for (int n = 0; n < keep.length; n++) keep[n]: n};
        final newEmphasis = seg.emphasis
            ?.where(indexMap.containsKey)
            .map((e) => indexMap[e]!)
            .toList();
        final c = seg.copy();
        c.words = newWords;
        c.wordTimings = newTimings;
        c.text = joinWordsSmart(newWords);
        c.startTime = newTimings.first;
        c.emphasis = (newEmphasis != null && newEmphasis.isNotEmpty)
            ? newEmphasis
            : null;
        rebuilt.add(c);
      } else {
        // No per-word timings → optional whole-segment drop.
        if (removeWhole != null && removeWhole(seg)) {
          newRanges.add(
              [seg.startTime.inMilliseconds, seg.endTime.inMilliseconds]);
          removedCount++;
        } else {
          rebuilt.add(seg);
        }
      }
    }

    if (removedCount == 0) return 0;

    provider.pushHistory();
    project.segments = rebuilt;
    project.removedRanges = _normalizeRanges([
      ...project.removedRanges,
      ...newRanges,
    ]);
    provider.commit();
    setState(() {});
    return removedCount;
  }

  /// Text-based editing (Descript/CapCut style): show the whole transcript as
  /// tappable word chips; tap to mark words for deletion; apply → the marked
  /// words' video+audio spans are cut and stripped from the captions.
  void _showTextEditSheet(ProjectProvider provider) {
    final project = provider.currentProject;
    if (project == null || project.segments.isEmpty) {
      _toast(tr('ed.noSubtitle'));
      return;
    }
    _pauseForEdit();

    // Only segments with per-word timings can be word-cut.
    final editable = project.segments.where((s) =>
        s.words != null &&
        s.wordTimings != null &&
        s.words!.length == s.wordTimings!.length &&
        s.words!.isNotEmpty);
    if (editable.isEmpty) {
      _toast(tr('ed.textEditNoWords'));
      return;
    }

    final selected = <String>{}; // keys: "<segId>:<wordIndex>"

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.92,
              expand: false,
              builder: (ctx, scrollCtrl) {
                return Column(
                  children: [
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Row(
                        children: [
                          const Icon(Icons.edit_note_rounded,
                              color: Color(0xFF42A5F5), size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              tr('ed.textEditTitle'),
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        tr('ed.textEditHint'),
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.border),
                    Expanded(
                      child: ListView(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.all(14),
                        children: [
                          for (final seg in project.segments)
                            if (seg.words != null &&
                                seg.wordTimings != null &&
                                seg.words!.length == seg.wordTimings!.length &&
                                seg.words!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (int i = 0;
                                        i < seg.words!.length;
                                        i++)
                                      _wordChip(
                                        seg.words![i],
                                        selected.contains('${seg.id}:$i'),
                                        () => setSheet(() {
                                          final k = '${seg.id}:$i';
                                          if (!selected.remove(k)) {
                                            selected.add(k);
                                          }
                                        }),
                                      ),
                                  ],
                                ),
                              ),
                        ],
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: selected.isEmpty
                                ? null
                                : () {
                                    Navigator.pop(ctx);
                                    final n = _applyWordRemoval(
                                      provider,
                                      remove: (seg, i) =>
                                          selected.contains('${seg.id}:$i'),
                                    );
                                    _toast(tr('ed.textEditDone', {'n': n}));
                                  },
                            icon: const Icon(Icons.content_cut_rounded,
                                size: 18),
                            label: Text(selected.isEmpty
                                ? tr('ed.textEditNone')
                                : tr('ed.textEditApply',
                                    {'n': selected.length})),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(0, 50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _wordChip(String word, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.18)
              : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.border,
          ),
        ),
        child: Text(
          word,
          style: TextStyle(
            color: selected ? AppColors.accent : AppColors.textPrimary,
            fontSize: 14,
            decoration:
                selected ? TextDecoration.lineThrough : TextDecoration.none,
            decorationColor: AppColors.accent,
            decorationThickness: 2,
          ),
        ),
      ),
    );
  }

  /// Delete the currently-selected video clip (removes its span + ripples).
  void _deleteSelectedClip(ProjectProvider provider) {
    final project = provider.currentProject;
    if (project == null || _selectedClipIndex == null) return;
    final clips = _videoClips(project);
    if (_selectedClipIndex! >= clips.length) {
      setState(() => _selectedClipIndex = null);
      return;
    }
    if (clips.length <= 1) {
      _toast(tr('ed.needOneClip'));
      return;
    }
    final clip = clips[_selectedClipIndex!];
    _cutRange(provider, clip.start, clip.end);
    setState(() => _selectedClipIndex = null);
  }
}
