part of '../editor_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

/// Style & position tabs: fonts, templates, animation, bilingual, karaoke.
/// Split out of editor_screen.dart verbatim (phase 0) — the
/// fields and lifecycle stay in [_EditorScreenState].
extension _EditorStyle on _EditorScreenState {
  Widget _buildWeightChip(
    String label,
    int weight,
    SubtitleProject project,
    ProjectProvider provider,
  ) {
    final isSelected = project.fontWeight == weight;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          project.fontWeight = weight;
          provider.updateProject(project);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: _applyLaoFont(
              project.fontFamily,
              TextStyle(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontWeight: fontWeightFromInt(weight),
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// One selectable font row (used for both built-in and imported fonts).
  Widget _buildFontTile({
    required String fontKey,
    required String name,
    required bool isSelected,
    required VoidCallback onTap,
    VoidCallback? onDelete,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.12)
              : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? AppColors.primary : AppColors.textHint,
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    tr('ed.previewExample'),
                    style: _applyLaoFont(
                      fontKey,
                      TextStyle(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textHint,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (onDelete != null)
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: AppColors.textHint,
                  size: 18,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }

  /// "Import font" button — opens the system picker for a .ttf/.otf file.
  Widget _buildImportFontButton(
    ProjectProvider provider,
    SubtitleProject project,
  ) {
    return GestureDetector(
      onTap: _importingFont ? null : () => _importFont(provider, project),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.primary.withOpacity(0.5),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_importingFont)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              )
            else
              const Icon(Icons.add, color: AppColors.primary, size: 18),
            const SizedBox(width: 8),
            Text(
              _importingFont ? tr('ed.importingFont') : tr('ed.importFont'),
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importFont(
    ProjectProvider provider,
    SubtitleProject project,
  ) async {
    setState(() => _importingFont = true);
    try {
      final font = await CustomFontService.importFromPicker();
      if (!mounted) return;
      if (font == null) {
        setState(() => _importingFont = false);
        return;
      }
      // Auto-select the freshly imported font.
      project.fontFamily = CustomFontService.familyKey(font.id);
      provider.updateProject(project);
      setState(() => _importingFont = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('ed.fontImported', {'name': font.name})),
          backgroundColor: AppColors.surface,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _importingFont = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('ed.fontImportFail', {'e': '$e'})),
          backgroundColor: AppColors.accent,
        ),
      );
    }
  }

  Future<void> _deleteCustomFont(
    CustomFont cf,
    ProjectProvider provider,
    SubtitleProject project,
  ) async {
    final key = CustomFontService.familyKey(cf.id);
    await CustomFontService.remove(cf.id);
    // If the deleted font was in use, fall back to the script-matching default.
    if (project.fontFamily == key) {
      project.fontFamily = defaultFontForLang(project.language);
      provider.updateProject(project);
    }
    if (mounted) setState(() {});
  }


  /// One-tap template gallery (style + size + position + karaoke + animation).
  Widget _buildTemplatesRow(SubtitleProject project, ProjectProvider provider) {
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: subtitleTemplates.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final t = subtitleTemplates[i];
          final locked = t.isPro && !_isPro;
          final selected =
              project.selectedStyle.type == t.styleType &&
              project.isKaraokeHighlight == t.karaoke;
          return GestureDetector(
            onTap: () => _applyTemplate(t, project, provider),
            child: Container(
              width: 76,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withOpacity(0.15)
                    : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.border,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(t.emoji, style: const TextStyle(fontSize: 24)),
                        const SizedBox(height: 6),
                        Text(
                          t.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected
                                ? AppColors.primary
                                : AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (locked)
                    const Positioned(
                      top: 0,
                      right: 0,
                      child: Icon(
                        Icons.lock,
                        size: 12,
                        color: Color(0xFFFFD700),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _applyTemplate(
    SubtitleTemplate t,
    SubtitleProject project,
    ProjectProvider provider,
  ) async {
    if (t.isPro && !_isPro) {
      _showProFeatureDialog(tr('ed.templateProDialog', {'name': t.name}));
      return;
    }
    final preset = subtitlePresets.firstWhere(
      (p) => p.type == t.styleType,
      orElse: () => project.selectedStyle,
    );
    project.selectedStyle = preset;
    project.fontFamily = t.fontFamily;
    project.fontSize = t.fontSize;
    project.fontWeight = t.fontWeight;
    project.subtitlePositionY = t.positionY;
    project.isKaraokeHighlight = t.karaoke;
    project.karaokeHighlightColor = Color(t.karaokeColorValue);
    project.karaokeScale = t.karaokeScale;
    project.subtitleAnimation = t.animation;
    project.exitAnimation = t.exitAnimation;
    project.animationSpeed = t.speed;
    provider.updateProject(project);
    // When the template turns karaoke on, make sure every line has real
    // word-level units so the sweep moves word-by-word.
    if (t.karaoke) {
      await LaoWordService.refineToRealWords(
        project.segments,
        locale: project.language,
      );
      if (mounted) {
        provider.commit();
        setState(() {});
      }
    }
    _toast(tr('ed.templateApplied', {'name': t.name}));
  }

  Widget _buildStyleTab() {
    return Consumer<ProjectProvider>(
      builder: (context, provider, _) {
        final project = provider.currentProject;
        if (project == null) return const SizedBox();
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_mosaic,
                    color: Color(0xFFFFC107),
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    tr('ed.templates'),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildTemplatesRow(project, provider),
              const SizedBox(height: 22),
              Text(
                tr('ed.tab.style'),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  mainAxisExtent: 90,
                ),
                itemCount: subtitlePresets.length,
                itemBuilder: (context, index) {
                  final preset = subtitlePresets[index];
                  return StylePreviewCard(
                    preset: preset,
                    isSelected: project.selectedStyle.type == preset.type,
                    locked: preset.isPro && !_isPro,
                    onTap: () {
                      if (preset.isPro && !_isPro) {
                        _showProFeatureDialog(tr('ed.styleProDialog', {'name': preset.name}));
                        return;
                      }
                      project.selectedStyle = preset;
                      provider.updateProject(project);
                    },
                  );
                },
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    tr('ed.fontSizeLabel'),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${project.fontSize.toInt()}px',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                  ),
                  activeTrackColor: AppColors.primary,
                  inactiveTrackColor: AppColors.surfaceLight,
                  thumbColor: AppColors.primary,
                  overlayColor: AppColors.primary.withOpacity(0.2),
                ),
                child: Slider(
                  value: project.fontSize.clamp(4.0, 60.0),
                  min: 4,
                  max: 60,
                  divisions: 56,
                  onChanged: (v) {
                    project.fontSize = v;
                    provider.updateProject(project);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text(
                      '4',
                      style: TextStyle(color: AppColors.textHint, fontSize: 11),
                    ),
                    Text(
                      '60',
                      style: TextStyle(color: AppColors.textHint, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildAnimationPicker(project, provider),
              const SizedBox(height: 24),
              _buildKaraokeSection(project, provider),
              const SizedBox(height: 24),
              _buildBilingualSection(project, provider),
              const SizedBox(height: 24),
              Text(
                tr('ed.fontShort'),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ...(_fontOptionsFor(project).map(
                (f) => _buildFontTile(
                  fontKey: f.$1,
                  name: f.$2,
                  isSelected: project.fontFamily == f.$1,
                  onTap: () {
                    project.fontFamily = f.$1;
                    provider.updateProject(project);
                  },
                ),
              )),
              // User-imported fonts (CapCut-style)
              ...CustomFontService.fonts.map((cf) {
                final key = CustomFontService.familyKey(cf.id);
                return _buildFontTile(
                  fontKey: key,
                  name: cf.name,
                  isSelected: project.fontFamily == key,
                  onTap: () {
                    project.fontFamily = key;
                    provider.updateProject(project);
                  },
                  onDelete: () => _deleteCustomFont(cf, provider, project),
                );
              }),
              _buildImportFontButton(provider, project),
              const SizedBox(height: 20),
              Text(
                tr('ed.weightFull'),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildWeightChip(tr('ed.thin'), 300, project, provider),
                  const SizedBox(width: 8),
                  _buildWeightChip(tr('ed.regular'), 400, project, provider),
                  const SizedBox(width: 8),
                  _buildWeightChip(tr('ed.bold'), 700, project, provider),
                  const SizedBox(width: 8),
                  _buildWeightChip(tr('ed.boldest'), 900, project, provider),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _animChip({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.15)
              : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimationPicker(
    SubtitleProject project,
    ProjectProvider provider,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('ed.animIn'),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _animOptions.map((opt) {
              return _animChip(
                icon: opt.$2,
                label: opt.$3,
                isSelected: project.subtitleAnimation == opt.$1,
                onTap: () {
                  project.subtitleAnimation = opt.$1;
                  provider.updateProject(project);
                },
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          tr('ed.animOut'),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _exitAnimOptions.map((opt) {
              return _animChip(
                icon: opt.$2,
                label: opt.$3,
                isSelected: project.exitAnimation == opt.$1,
                onTap: () {
                  project.exitAnimation = opt.$1;
                  provider.updateProject(project);
                },
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          tr('ed.animSpeed'),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: _speedOptions.map((opt) {
            final isSelected = project.animationSpeed == opt.$1;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  project.animationSpeed = opt.$1;
                  provider.updateProject(project);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withOpacity(0.15)
                        : AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.border,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    opt.$2,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildBilingualSection(
    SubtitleProject project,
    ProjectProvider provider,
  ) {
    final biPreset =
        subtitlePresets[project.bilingualPresetIndex.clamp(
          0,
          subtitlePresets.length - 1,
        )];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: project.showBilingual
            ? const Color(0xFFFFB300).withOpacity(0.07)
            : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: project.showBilingual
              ? const Color(0xFFFFB300)
              : AppColors.border,
          width: project.showBilingual ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with toggle
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: project.showBilingual
                      ? const Color(0xFFFFB300).withOpacity(0.2)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.translate,
                  color: project.showBilingual
                      ? const Color(0xFFFFB300)
                      : AppColors.textHint,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('ed.bilingualSub'),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      tr('ed.bilingualDesc'),
                      style: const TextStyle(color: AppColors.textHint, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Stack(
                alignment: Alignment.topRight,
                children: [
                  Switch(
                    value: project.showBilingual,
                    activeColor: const Color(0xFFFFB300),
                    onChanged: (v) {
                      if (v && !_isPro) {
                        _showProFeatureDialog(tr('ed.bilingualProDialog'));
                        return;
                      }
                      project.showBilingual = v;
                      provider.updateProject(project);
                      if (v != provider.showTranslation) {
                        provider.toggleShowTranslation();
                      }
                    },
                  ),
                  if (!_isPro)
                    const Positioned(
                      top: 0,
                      right: 0,
                      child: Icon(
                        Icons.lock_rounded,
                        size: 12,
                        color: Color(0xFFFFD700),
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (project.showBilingual) ...[
            const SizedBox(height: 16),
            // Font size for line 2
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  tr('ed.row2Size'),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB300).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    '${project.bilingualFontSize.toInt()}px',
                    style: const TextStyle(
                      color: Color(0xFFFFB300),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                activeTrackColor: const Color(0xFFFFB300),
                inactiveTrackColor: AppColors.surfaceLight,
                thumbColor: const Color(0xFFFFB300),
                overlayColor: const Color(0xFFFFB300).withOpacity(0.2),
              ),
              child: Slider(
                value: project.bilingualFontSize.clamp(4.0, 48.0),
                min: 4,
                max: 48,
                divisions: 44,
                onChanged: (v) {
                  project.bilingualFontSize = v;
                  provider.updateProject(project);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text(
                    '4',
                    style: TextStyle(color: AppColors.textHint, fontSize: 10),
                  ),
                  Text(
                    '48',
                    style: TextStyle(color: AppColors.textHint, fontSize: 10),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Gap between the main line and the translated line
            Row(
              children: [
                Text(
                  tr('ed.rowGap'),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB300).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    project.bilingualGap.toInt().toString(),
                    style: const TextStyle(
                      color: Color(0xFFFFB300),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                activeTrackColor: const Color(0xFFFFB300),
                inactiveTrackColor: AppColors.surfaceLight,
                thumbColor: const Color(0xFFFFB300),
                overlayColor: const Color(0xFFFFB300).withOpacity(0.2),
              ),
              child: Slider(
                value: project.bilingualGap.clamp(0.0, 40.0),
                min: 0,
                max: 40,
                divisions: 40,
                onChanged: (v) {
                  project.bilingualGap = v;
                  provider.updateProject(project);
                },
              ),
            ),
            const SizedBox(height: 16),
            // Style grid for line 2
            Text(
              tr('ed.row2Style'),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                mainAxisExtent: 90,
              ),
              itemCount: subtitlePresets.length,
              itemBuilder: (context, index) {
                final preset = subtitlePresets[index];
                return StylePreviewCard(
                  preset: preset,
                  isSelected: project.bilingualPresetIndex == index,
                  onTap: () {
                    project.bilingualPresetIndex = index;
                    provider.updateProject(project);
                  },
                );
              },
            ),
            const SizedBox(height: 12),
            // Live preview of line 2
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: _buildSubtitleOverlay(
                  tr('ed.preview'),
                  biPreset,
                  fontSizeOverride: project.bilingualFontSize,
                  fontFamily: project.fontFamily,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKaraokeSection(
    SubtitleProject project,
    ProjectProvider provider,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: project.isKaraokeHighlight
            ? AppColors.primary.withOpacity(0.08)
            : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: project.isKaraokeHighlight
              ? AppColors.primary
              : AppColors.border,
          width: project.isKaraokeHighlight ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: project.isKaraokeHighlight
                      ? project.karaokeHighlightColor.withOpacity(0.2)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.highlight,
                  color: project.isKaraokeHighlight
                      ? project.karaokeHighlightColor
                      : AppColors.textHint,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Karaoke Highlight',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      tr('ed.karaokeDesc'),
                      style: const TextStyle(color: AppColors.textHint, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Stack(
                alignment: Alignment.topRight,
                children: [
                  Switch(
                    value: project.isKaraokeHighlight,
                    activeColor: AppColors.primary,
                    onChanged: (v) async {
                      if (v && !_isPro) {
                        _showProFeatureDialog('Karaoke Highlight');
                        return;
                      }
                      project.isKaraokeHighlight = v;
                      provider.updateProject(project);
                      // Refresh to real word-level units so the sweep is per-word.
                      if (v) {
                        await LaoWordService.refineToRealWords(
                          project.segments,
                          locale: project.language,
                        );
                        if (mounted) {
                          provider.commit();
                          setState(() {});
                        }
                      }
                    },
                  ),
                  if (!_isPro)
                    const Positioned(
                      top: 0,
                      right: 0,
                      child: Icon(
                        Icons.lock_rounded,
                        size: 12,
                        color: Color(0xFFFFD700),
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (project.isKaraokeHighlight) ...[
            const SizedBox(height: 14),
            Text(
              tr('ed.highlightColor'),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _karaokeColors.map((color) {
                final isSelected =
                    project.karaokeHighlightColor.value == color.value;
                return GestureDetector(
                  onTap: () {
                    project.karaokeHighlightColor = color;
                    provider.updateProject(project);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.transparent,
                        width: 2.5,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: color.withOpacity(0.7),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 20)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('ed.wordPop'),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        tr('ed.wordPopDesc'),
                        style: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: project.karaokeScale,
                  activeColor: AppColors.primary,
                  onChanged: (v) {
                    project.karaokeScale = v;
                    provider.updateProject(project);
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPositionTab() {
    return Consumer<ProjectProvider>(
      builder: (context, provider, _) {
        final project = provider.currentProject;
        if (project == null) return const SizedBox();
        final pos = project.subtitlePositionY;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('ed.subPosition'),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              // Quick presets
              Row(
                children: [
                  _buildPositionOption(
                    tr('ed.top'),
                    Icons.vertical_align_top,
                    pos < 0.2,
                    () {
                      project.subtitlePositionY = 0.1;
                      provider.updateProject(project);
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildPositionOption(
                    tr('ed.middle'),
                    Icons.vertical_align_center,
                    pos >= 0.2 && pos <= 0.7,
                    () {
                      project.subtitlePositionY = 0.5;
                      provider.updateProject(project);
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildPositionOption(
                    tr('ed.bottom'),
                    Icons.vertical_align_bottom,
                    pos > 0.7,
                    () {
                      project.subtitlePositionY = 0.85;
                      provider.updateProject(project);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                tr('ed.fineTune'),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              // Visual position indicator
              Container(
                height: 160,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: (pos * 140).clamp(8, 132),
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            tr('ed.subHere'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                  ),
                  activeTrackColor: AppColors.primary,
                  inactiveTrackColor: AppColors.surfaceLight,
                  thumbColor: AppColors.primary,
                  overlayColor: AppColors.primary.withOpacity(0.2),
                ),
                child: Slider(
                  value: pos,
                  min: 0.05,
                  max: 0.95,
                  onChanged: (v) {
                    project.subtitlePositionY = v;
                    provider.updateProject(project);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      tr('ed.top'),
                      style: const TextStyle(color: AppColors.textHint, fontSize: 11),
                    ),
                    Text(
                      tr('ed.bottom'),
                      style: const TextStyle(color: AppColors.textHint, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPositionOption(
    String label,
    IconData icon,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withOpacity(0.15)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                size: 22,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
