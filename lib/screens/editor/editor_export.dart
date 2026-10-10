part of '../editor_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

/// Export, translate, add-segment sheet, SRT, dubbing, dialogs.
/// Split out of editor_screen.dart verbatim (phase 0) — the
/// fields and lifecycle stay in [_EditorScreenState].
extension _EditorExport on _EditorScreenState {
  void _showExportOptions() {
    Widget tile(IconData icon, Color color, String title, String sub, VoidCallback onTap) {
      return ListTile(
        onTap: onTap,
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(title,
            style: const TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Text(sub,
            style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
      );
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(tr('ed.exportTitle'),
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ),
            tile(Icons.movie_creation_outlined, AppColors.primary,
                tr('ed.exportVideo'), tr('ed.exportVideoSub'), () {
              Navigator.pop(ctx);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ExportScreen()));
            }),
            tile(Icons.subtitles_outlined, const Color(0xFF00BFA5),
                tr('ed.exportSrt'), tr('ed.exportSrtSub'), () {
              Navigator.pop(ctx);
              _exportSubtitleFile(vtt: false);
            }),
            tile(Icons.closed_caption_outlined, const Color(0xFF7C5CFF),
                tr('ed.exportVtt'), tr('ed.exportVttSub'), () {
              Navigator.pop(ctx);
              _exportSubtitleFile(vtt: true);
            }),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _exportSubtitleFile({required bool vtt}) async {
    final project = context.read<ProjectProvider>().currentProject;
    if (project == null || project.segments.isEmpty) {
      _toast(tr('ed.noSubtitle'));
      return;
    }
    // Free users: 2 subtitle-file exports per day. PRO is unlimited.
    final remaining = await FreeQuotaService.remainingSrtExports();
    if (remaining <= 0) {
      _showProFeatureDialog(tr('ed.srtQuotaReached'));
      return;
    }
    final isPro = await FreeQuotaService.isPro();
    try {
      final path = await SubtitleExportService.export(
        segments: project.segments,
        baseName: project.name.trim().isEmpty ? 'subtitle' : project.name.trim(),
        vtt: vtt,
        bilingual: project.showBilingual,
      );
      if (!isPro) await FreeQuotaService.useSrtExport();
      if (mounted) {
        final left = isPro ? '' : tr('ed.srtQuota', {'n': remaining - 1});
        _toast('${tr('ed.subFileSaved', {'path': path})}$left');
      }
    } catch (e) {
      if (mounted) _toast(tr('ed.subFileFail', {'e': '$e'}));
    }
  }

  void _showTranslateSheet(ProjectProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('ed.translateSub'),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr('ed.pickTransLang'),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            _buildLangOption('🇬🇧 English', 'en', provider),
            const SizedBox(height: 10),
            _buildLangOption(tr('lang.opt.th'), 'th', provider),
            const SizedBox(height: 10),
            _buildLangOption(tr('lang.opt.lo'), 'lo', provider),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildLangOption(
    String label,
    String langCode,
    ProjectProvider provider,
  ) {
    return GestureDetector(
      onTap: () async {
        Navigator.pop(context);
        await _translateSegments(langCode, provider);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Future<void> _translateSegments(
    String targetLang,
    ProjectProvider provider,
  ) async {
    final project = provider.currentProject;
    if (project == null || project.segments.isEmpty) return;

    final apiKey = await ApiConfig.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('ed.needGeminiTranslate')),
            backgroundColor: AppColors.accent,
          ),
        );
      }
      return;
    }

    setState(() => _isTranslating = true);
    try {
      final service = GeminiSpeechService(apiKey: apiKey);
      final texts = project.segments.map((s) => s.text).toList();
      final translated = await service.translateTexts(texts, targetLang);

      final updated = project.segments.asMap().entries.map((e) {
        final s = e.value.copy();
        if (e.key < translated.length) s.translatedText = translated[e.key];
        return s;
      }).toList();

      provider.updateSegments(updated, recordHistory: false);
      if (mounted) {
        if (!provider.showTranslation) provider.toggleShowTranslation();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('ed.translateDone')),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('ed.translateFail', {'e': '$e'})),
            backgroundColor: AppColors.accent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isTranslating = false);
    }
  }

  void _showAddSegmentSheet(ProjectProvider provider) {
    final textCtrl = TextEditingController();
    final transCtrl = TextEditingController();
    Duration startTime = _position;
    Duration endTime = _position + const Duration(seconds: 3);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('ed.addSubtitle'),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              // Line 1 — main text
              _buildTextField(
                controller: textCtrl,
                label: tr('ed.row1'),
                hint: tr('ed.egHello'),
                autofocus: true,
                accentColor: AppColors.primary,
              ),
              const SizedBox(height: 10),
              // Line 2 — translated text
              _buildTextField(
                controller: transCtrl,
                label: tr('ed.row2'),
                hint: 'ເຊັ່ນ: Hello',
                accentColor: const Color(0xFFFFB300),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Timestamp',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTimeEditor(
                            label: tr('ed.start'),
                            time: startTime,
                            maxTime: _duration > Duration.zero
                                ? _duration
                                : const Duration(hours: 1),
                            onChanged: (t) => setModal(() => startTime = t),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Icon(
                            Icons.arrow_forward,
                            color: AppColors.textHint,
                            size: 16,
                          ),
                        ),
                        Expanded(
                          child: _buildTimeEditor(
                            label: tr('ed.end'),
                            time: endTime,
                            maxTime: _duration > Duration.zero
                                ? _duration
                                : const Duration(hours: 1),
                            onChanged: (t) => setModal(() => endTime = t),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  final text = textCtrl.text.trim();
                  if (text.isEmpty) return;
                  final trans = transCtrl.text.trim();
                  final newSeg = SubtitleSegment(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    text: text,
                    startTime: startTime,
                    endTime: endTime > startTime
                        ? endTime
                        : startTime + const Duration(seconds: 2),
                    translatedText: trans.isEmpty ? null : trans,
                  );
                  final updated =
                      List<SubtitleSegment>.from(
                          provider.currentProject!.segments,
                        )
                        ..add(newSeg)
                        ..sort((a, b) => a.startTime.compareTo(b.startTime));
                  provider.updateSegments(updated);
                  // auto-show bilingual if second line was filled
                  if (trans.isNotEmpty && !provider.showTranslation) {
                    provider.toggleShowTranslation();
                  }
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: Text(tr('ed.add')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool autofocus = false,
    Color accentColor = AppColors.primary,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: accentColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          autofocus: autofocus,
          style: const TextStyle(color: AppColors.textPrimary),
          maxLines: 2,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.textHint),
            filled: true,
            fillColor: AppColors.surfaceLight,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: accentColor, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  void _exportSRT() {
    final project = context.read<ProjectProvider>().currentProject;
    if (project == null) return;

    final buffer = StringBuffer();
    for (int i = 0; i < project.segments.length; i++) {
      final s = project.segments[i];
      buffer.writeln('${i + 1}');
      buffer.writeln('${_toSRTTime(s.startTime)} --> ${_toSRTTime(s.endTime)}');
      buffer.writeln(s.text);
      buffer.writeln();
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'SRT Content',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: SingleChildScrollView(
          child: Text(
            buffer.toString(),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('common.close')),
          ),
        ],
      ),
    );
  }

  String _toSRTTime(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final ms = d.inMilliseconds.remainder(1000).toString().padLeft(3, '0');
    return '$h:$m:$s,$ms';
  }

  void _showDubbingDialog(ProjectProvider provider) async {
    final project = provider.currentProject;
    if (project == null) return;

    final hasApiKey = true;

    String ttsLang = project.language.isEmpty ? 'lo' : project.language;
    if (ttsLang == 'Auto') ttsLang = 'lo';

    String selectedVoice = '';
    double speechRate = 0.5;
    bool useTranslation = project.showBilingual;
    bool saveAudioOnly = false;
    List<Map<String, String>> availableVoices = [];
    bool loadingVoices = true;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            // Load voices if not loaded yet
            if (loadingVoices && hasApiKey) {
              loadingVoices = false;
              _ttsService.getVoicesForLanguage(ttsLang).then((voices) {
                if (ctx.mounted) {
                  setDlgState(() {
                    availableVoices = voices;
                    if (voices.isNotEmpty) {
                      // Try to find a common voice like Rachel or Adam, or select first
                      final defaultVoice = voices.firstWhere(
                        (v) => v['name']!.toLowerCase().contains('rachel') || v['name']!.toLowerCase().contains('adam'),
                        orElse: () => voices.first,
                      );
                      selectedVoice = defaultVoice['name'] ?? '';
                    } else {
                      selectedVoice = '';
                    }
                  });
                }
              });
            }

            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.record_voice_over, color: AppColors.primary, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    tr('ed.aiDubbing'),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!hasApiKey) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.accent.withOpacity(0.25)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: AppColors.accent, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    tr('ed.noGeminiSet'),
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              tr('ed.geminiTtsHint2'),
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ] else ...[
                      Text(
                        tr('ed.pickVoiceTone'),
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                    ],
                    // Language selection
                    Text(tr('ed.voiceLang'), style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
                    DropdownButton<String>(
                      value: ttsLang,
                      isExpanded: true,
                      dropdownColor: AppColors.surface,
                      style: const TextStyle(color: AppColors.textPrimary),
                      items: [
                        DropdownMenuItem(value: 'lo', child: Text(tr('ed.langLaoOpt'))),
                        DropdownMenuItem(value: 'th', child: Text(tr('ed.langThaiOpt'))),
                        DropdownMenuItem(value: 'en', child: Text(tr('ed.langEnOpt'))),
                      ],
                      onChanged: !hasApiKey ? null : (val) {
                        if (val != null) {
                          setDlgState(() {
                            ttsLang = val;
                            loadingVoices = true; // trigger reloading voices
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    if (hasApiKey) ...[
                      // Voice selection
                      Text(tr('ed.voiceTones'), style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
                      if (availableVoices.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            tr('ed.loadingVoices'),
                            style: const TextStyle(color: AppColors.textHint, fontSize: 12, fontStyle: FontStyle.italic),
                          ),
                        )
                      else
                        DropdownButton<String>(
                          value: selectedVoice.isEmpty ? null : selectedVoice,
                          isExpanded: true,
                          dropdownColor: AppColors.surface,
                          style: const TextStyle(color: AppColors.textPrimary),
                          items: availableVoices.map((v) {
                            final gender = v['gender'] == 'male' ? tr('ed.male') : (v['gender'] == 'female' ? tr('ed.female') : '');
                            return DropdownMenuItem(
                              value: v['name'],
                              child: Text('${v['name']}$gender'),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setDlgState(() => selectedVoice = val);
                            }
                          },
                        ),
                      const SizedBox(height: 12),
                      // Speech rate
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(tr('ed.voiceSpeed'), style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
                          Text('${(speechRate * 2).toStringAsFixed(1)}x', style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Slider(
                        value: speechRate,
                        min: 0.1,
                        max: 1.0,
                        activeColor: AppColors.primary,
                        inactiveColor: AppColors.border,
                        onChanged: (val) {
                          setDlgState(() => speechRate = val);
                        },
                      ),
                      const SizedBox(height: 6),
                      // Use translation toggle
                      if (project.showBilingual) ...[
                        CheckboxListTile(
                          title: Text(
                            tr('ed.dubFromTranslation'),
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                          ),
                          value: useTranslation,
                          activeColor: AppColors.primary,
                          checkColor: Colors.white,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) {
                            if (val != null) {
                              setDlgState(() => useTranslation = val);
                            }
                          },
                        ),
                      ],
                      CheckboxListTile(
                        title: Text(
                          tr('ed.sfxAutoSyncTitle'),
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          tr('ed.autoSfxDesc'),
                          style: const TextStyle(color: AppColors.textHint, fontSize: 10),
                        ),
                        value: project.isAutoSyncSfx,
                        activeColor: AppColors.primary,
                        checkColor: Colors.white,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) {
                          if (val != null) {
                            setDlgState(() {
                              project.isAutoSyncSfx = val;
                              provider.updateProject(project);
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(tr('ed.exportFormat'), style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
                      const SizedBox(height: 6),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border, width: 0.5),
                        ),
                        child: Column(
                          children: [
                            RadioListTile<bool>(
                              title: Text(tr('ed.muxVideo'), style: const TextStyle(color: AppColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.bold)),
                              subtitle: Text(tr('ed.muxVideoSub'), style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                              value: false,
                              groupValue: saveAudioOnly,
                              activeColor: AppColors.primary,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                              onChanged: (val) {
                                if (val != null) {
                                  setDlgState(() => saveAudioOnly = val);
                                }
                              },
                            ),
                            const Divider(height: 1, color: AppColors.border),
                            RadioListTile<bool>(
                              title: Text(tr('ed.audioOnly'), style: const TextStyle(color: AppColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.bold)),
                              subtitle: Text(tr('ed.audioOnlySub'), style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                              value: true,
                              groupValue: saveAudioOnly,
                              activeColor: AppColors.primary,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                              onChanged: (val) {
                                if (val != null) {
                                  setDlgState(() => saveAudioOnly = val);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(tr('common.close'), style: const TextStyle(color: AppColors.textSecondary)),
                ),
                if (!hasApiKey)
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SettingsScreen()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.settings, size: 16),
                    label: Text(tr('ed.goToSettings'), style: const TextStyle(fontWeight: FontWeight.bold)),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: selectedVoice.isEmpty
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            _runDubbingPipeline(
                              provider: provider,
                              language: ttsLang,
                              voiceName: selectedVoice,
                              speechRate: speechRate,
                              useTranslation: useTranslation,
                              saveAudioOnly: saveAudioOnly,
                            );
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.surfaceLight,
                    ),
                    icon: const Icon(Icons.record_voice_over, size: 16),
                    label: Text(tr('ed.startDubbing'), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  void _runDubbingPipeline({
    required ProjectProvider provider,
    required String language,
    required String voiceName,
    required double speechRate,
    required bool useTranslation,
    bool saveAudioOnly = false,
  }) async {
    final project = provider.currentProject;
    if (project == null || project.videoPath == null) return;


    // Show persistent progress overlay
    String progressText = tr('ed.preparingSystem');
    double progressPct = 0.0;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setProgState) {
            // Hook synthesis callback to dynamically update progress screen
            if (progressPct == 0.0) {
              progressPct = 0.05;
              final tempDir = Directory.systemTemp;
              final outputWav = '${tempDir.path}/tts_stitched_${DateTime.now().millisecondsSinceEpoch}.wav';
              final outputSfxWav = '${tempDir.path}/sfx_only_${DateTime.now().millisecondsSinceEpoch}.wav';

              _ttsService.synthesizeAndStitch(
                segments: project.segments,
                languageCode: language,
                voiceName: voiceName,
                speechRate: speechRate,
                useTranslation: useTranslation,
                outputWavPath: outputWav,
                
                onProgress: (status) {
                  if (ctx.mounted) {
                    setProgState(() {
                      progressText = status;
                      if (status.contains('ສັງເຄາະສຽງປະໂຫຍກ')) {
                        progressPct = 0.15 + (0.65 * chunksProgressFraction(status));
                      } else if (status.contains('ຈັດຊ່ວງເວລາ')) {
                        progressPct = 0.85;
                      }
                    });
                  }
                },
              ).then((errorMsg) async {
                if (errorMsg != null) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  _showErrorBanner(errorMsg);
                  return;
                }

                if (saveAudioOnly) {
                  if (ctx.mounted) {
                    setProgState(() {
                      progressText = tr('ed.savingAudio');
                      progressPct = 0.95;
                    });
                  }
                  try {
                    const channel = MethodChannel('com.anniekaydee.subtitle_app/audio');
                    final newPath = await channel.invokeMethod<String>('saveAudioToGallery', {
                      'audioPath': outputWav,
                      'fileName': 'dubbed_audio_${DateTime.now().millisecondsSinceEpoch}.wav',
                    });

                    if (newPath != null) {
                      if (project.sfxBlocks.isNotEmpty) {
                        await channel.invokeMethod<String>('saveAudioToGallery', {
                          'audioPath': outputSfxWav,
                          'fileName': 'sfx_only_${DateTime.now().millisecondsSinceEpoch}.wav',
                        });
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                      _showAudioSuccessDialog(newPath);
                    } else {
                      throw Exception('Failed to save audio to gallery');
                    }
                  } catch (e) {
                    if (ctx.mounted) Navigator.pop(ctx);
                    _showErrorBanner(tr('ed.audioSaveFail', {'e': e.toString()}));
                  }
                  return;
                }

                if (ctx.mounted) {
                  setProgState(() {
                    progressText = tr('ed.addingAiTrack');
                    progressPct = 0.95;
                  });
                }

                try {
                  // Non-destructive: save the stitched AI voice as a SEPARATE
                  // timeline track. The original video audio is left untouched;
                  // the tracks are only combined (at chosen volumes) on export.
                  final supportDir = await getApplicationSupportDirectory();
                  final aiDir = Directory(p.join(supportDir.path, 'ai_voice'));
                  if (!aiDir.existsSync()) aiDir.createSync(recursive: true);
                  final destPath = p.join(aiDir.path,
                      'ai_voice_${DateTime.now().millisecondsSinceEpoch}.wav');
                  await File(outputWav).copy(destPath);

                  // Read the WAV header to compute the track duration.
                  final raf = await File(destPath).open();
                  final hdr = await raf.read(44);
                  await raf.close();
                  final wavLen = await File(destPath).length();
                  final bd = ByteData.sublistView(hdr);
                  final chs = bd.getInt16(22, Endian.little);
                  final sr = bd.getInt32(24, Endian.little);
                  final bps = bd.getInt16(34, Endian.little) ~/ 8;
                  final durMs = (sr * chs * bps) > 0
                      ? ((wavLen - 44) / (sr * chs * bps) * 1000).round()
                      : 0;

                  provider.pushHistory();
                  // Replace any previous AI track file.
                  final oldPath = project.aiVoicePath;
                  if (oldPath != null && oldPath != destPath) {
                    try { File(oldPath).deleteSync(); } catch (_) {}
                  }
                  project.aiVoicePath = destPath;
                  project.aiVoiceDurationMs = durMs;
                  project.aiVoiceOffsetMs = 0;
                  project.aiVoiceTrimStartMs = 0;
                  project.aiVoiceTrimEndMs = null;
                  project.aiVoiceMuted = false;
                  provider.commit();
                  _aiVoiceLoadedPath = null;
                  await _ensureAiVoicePlayer();

                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) setState(() {});
                  _showAiTrackAddedDialog();
                } catch (e) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  _showErrorBanner(tr('ed.aiTrackFail', {'e': e.toString()}));
                }
              });
            }

            return PopScope(
              canPop: false,
              child: AlertDialog(
                backgroundColor: AppColors.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                content: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        progressText,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(progressPct * 100).toInt()}%',
                        style: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  double chunksProgressFraction(String status) {
    try {
      final match = RegExp(r'(\d+)/(\d+)').firstMatch(status);
      if (match != null) {
        final current = double.parse(match.group(1)!);
        final total = double.parse(match.group(2)!);
        return current / total;
      }
    } catch (_) {}
    return 0.5;
  }

  void _showErrorBanner(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.accent,
      ),
    );
  }

  void _showSuccessDialog(String fileName) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 24),
            const SizedBox(width: 10),
            Text(
              tr('ed.dubDone'),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Text(
          tr('ed.dubMuxedBody', {'file': fileName}),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
            ),
            child: Text(tr('ed.ok'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAudioSuccessDialog(String savedPath) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 24),
            const SizedBox(width: 10),
            Text(
              tr('ed.dubSavedTitle'),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Text(
          tr('ed.dubSavedBody', {'file': savedPath.split('/').last}),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
            ),
            child: Text(tr('ed.ok'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Shown when Muxing fails but audio was saved as a fallback layer file
  void _showAudioFallbackDialog(String savedPath) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.amber, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tr('ed.saveAsAudioLayer'),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('ed.muxFailBody'),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                '📂 Music/SubtitleAI/${savedPath.split('/').last}',
                style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              tr('ed.audioLayerHint'),
              style: const TextStyle(color: AppColors.textHint, fontSize: 11.5, height: 1.4),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: Text(tr('ed.understood'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
