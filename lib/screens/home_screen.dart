import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../i18n/i18n.dart';
import '../providers/project_provider.dart';
import '../models/subtitle_style_model.dart';
import '../services/media_info_service.dart';
import '../services/free_quota_service.dart';
import 'setup_screen.dart';
import 'editor_screen.dart';
import 'settings_screen.dart';

enum _ProjectSort { newest, oldest, name }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _grid = false;
  String _query = '';
  _ProjectSort _sort = _ProjectSort.newest;

  // PRO / free-quota status shown on the home header (refreshed on resume).
  bool _isPro = false;
  DateTime? _proExpiry;
  int _freeFhd = FreeQuotaService.freeFhdPerDay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _generateThumbs();
      _loadStatus();
    });
  }

  Future<void> _loadStatus() async {
    final pro = await FreeQuotaService.isPro();
    final expiry = await FreeQuotaService.proExpiry();
    final fhd = await FreeQuotaService.remainingFhdExports();
    if (!mounted) return;
    setState(() {
      _isPro = pro;
      _proExpiry = expiry;
      _freeFhd = fhd;
    });
  }

  /// Apply the search filter + chosen sort order to the project list.
  List<SubtitleProject> _visible(List<SubtitleProject> all) {
    final q = _query.trim().toLowerCase();
    final list = q.isEmpty
        ? List<SubtitleProject>.from(all)
        : all.where((p) => p.name.toLowerCase().contains(q)).toList();
    switch (_sort) {
      case _ProjectSort.newest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case _ProjectSort.oldest:
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case _ProjectSort.name:
        list.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
    }
    return list;
  }

  Future<void> _generateThumbs() async {
    if (!mounted) return;
    final provider = context.read<ProjectProvider>();
    for (final p in provider.projects) {
      if (p.videoPath == null) continue;
      final hasThumb =
          p.thumbnailPath != null && File(p.thumbnailPath!).existsSync();
      if (hasThumb && p.videoDuration != null) continue;
      final m = await MediaInfoService.meta(p.videoPath!, p.id);
      var changed = false;
      if (m.thumb != null && p.thumbnailPath != m.thumb) {
        p.thumbnailPath = m.thumb;
        changed = true;
      }
      if (m.durationMs > 0 && p.videoDuration == null) {
        p.videoDuration = Duration(milliseconds: m.durationMs);
        changed = true;
      }
      if (changed && mounted) provider.updateProject(p);
    }
  }

  String _fmtDur(Duration? d) {
    if (d == null) return '--:--';
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year % 100}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Consumer<ProjectProvider>(
          builder: (context, provider, _) {
            final projects = provider.projects;
            final visible = _visible(projects);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, projects.length),
                _buildStatusCard(context),
                _buildHeroButton(context),
                // Clip-editing (multi-clip) shelved until ready — entry hidden.
                // _buildEditClipButton(context),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        tr('home.recentProjects'),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const Spacer(),
                      if (projects.isNotEmpty) ...[
                        _sortBtn(),
                        const SizedBox(width: 8),
                        _iconBtn(
                          _grid
                              ? Icons.view_list_rounded
                              : Icons.grid_view_rounded,
                          () => setState(() => _grid = !_grid),
                        ),
                      ],
                    ],
                  ),
                ),
                if (projects.length > 5) _buildSearchBar(),
                Expanded(
                  child: projects.isEmpty
                      ? _buildEmptyState(context)
                      : (visible.isEmpty
                          ? _buildNoMatch()
                          : (_grid
                              ? _buildGrid(visible)
                              : _buildList(visible))),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Icon(icon, color: AppColors.textSecondary, size: 19),
    ),
  );

  /// PRO badge (gold) when active, else a free-quota strip with an upgrade CTA.
  Widget _buildStatusCard(BuildContext context) {
    void openSettings() async {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      );
      _loadStatus();
    }

    if (_isPro) {
      final until = _proExpiry != null ? _fmtDate(_proExpiry!) : '';
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFD700), Color(0xFFFFB703)],
            ),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            children: [
              const Icon(Icons.workspace_premium, color: Colors.black, size: 18),
              const SizedBox(width: 8),
              Text(
                tr('home.proActive'),
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              if (until.isNotEmpty)
                Text(
                  tr('home.proUntil', {'date': until}),
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 11.5,
                  ),
                ),
            ],
          ),
        ),
      ).animate(delay: 80.ms).fadeIn();
    }

    final out = _freeFhd <= 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: GestureDetector(
        onTap: openSettings,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: out ? AppColors.accent : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                out ? Icons.lock_clock : Icons.bolt,
                color: out ? AppColors.accent : AppColors.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  out
                      ? tr('home.freeQuotaOut')
                      : tr('home.freeQuota', {'n': _freeFhd}),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: AppGradients.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.workspace_premium,
                        color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      tr('home.upgradePro'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ).animate(delay: 80.ms).fadeIn(),
    );
  }

  Widget _sortBtn() {
    return PopupMenuButton<_ProjectSort>(
      onSelected: (v) => setState(() => _sort = v),
      color: AppColors.surfaceLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: const Icon(Icons.sort_rounded,
            color: AppColors.textSecondary, size: 19),
      ),
      itemBuilder: (_) => [
        _sortItem(_ProjectSort.newest, tr('home.sortNewest')),
        _sortItem(_ProjectSort.oldest, tr('home.sortOldest')),
        _sortItem(_ProjectSort.name, tr('home.sortName')),
      ],
    );
  }

  PopupMenuItem<_ProjectSort> _sortItem(_ProjectSort v, String label) {
    final active = _sort == v;
    return PopupMenuItem<_ProjectSort>(
      value: v,
      child: Row(
        children: [
          Icon(active ? Icons.check : Icons.remove,
              size: 16,
              color: active ? AppColors.primary : Colors.transparent),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                color: active ? AppColors.primary : AppColors.textPrimary,
                fontSize: 14,
              )),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, color: AppColors.textHint, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 14),
                cursorColor: AppColors.primary,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: tr('home.search'),
                  hintStyle:
                      const TextStyle(color: AppColors.textHint, fontSize: 14),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            if (_query.isNotEmpty)
              GestureDetector(
                onTap: () => setState(() => _query = ''),
                child: const Icon(Icons.close,
                    color: AppColors.textHint, size: 18),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoMatch() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off_rounded,
              color: AppColors.textHint, size: 40),
          const SizedBox(height: 12),
          Text(
            tr('home.noMatch'),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Image.asset(
                'assets/icon/icon.png',
                width: 46,
                height: 46,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  decoration: BoxDecoration(gradient: AppGradients.primary),
                  child: const Icon(
                    Icons.subtitles_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'KarnSub',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  count == 0 ? tr('home.tagline') : tr('home.projectCount', {'n': count}),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          _iconBtn(
            Icons.settings_outlined,
            () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              _loadStatus(); // PRO state may have changed in Settings
            },
          ),
        ],
      ).animate().fadeIn(duration: 350.ms),
    );
  }

  /// Secondary entry: jump straight into the clip editor (merge/trim/cut)
  /// WITHOUT transcribing first. Transcription can be run later inside the editor.
  Widget _buildEditClipButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: GestureDetector(
        onTap: _editClip,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: const Color(0xFF7C4DFF)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF7C4DFF).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.content_cut_rounded,
                    color: Color(0xFF7C4DFF), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('home.editClip'),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tr('home.editClipSub'),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: AppColors.textHint, size: 20),
            ],
          ),
        ),
      ).animate(delay: 120.ms).fadeIn(),
    );
  }

  /// Pick clip(s) → (merge if >1) → create a project → open the editor directly.
  Future<void> _editClip() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;
    final paths = result.files.map((f) => f.path).whereType<String>().toList();
    if (paths.isEmpty) return;

    if (!mounted) return;
    final provider = context.read<ProjectProvider>();
    final name =
        '${tr('home.editClip')} ${DateTime.now().day}/${DateTime.now().month}';
    final project = provider.createProject(name);

    // CapCut model: keep each pick as a SEPARATE clip (no merge) so they stay
    // reorderable + each plays in its own native orientation (no rotation bug).
    final clips = <VideoClip>[];
    for (int i = 0; i < paths.length; i++) {
      final meta = await MediaInfoService.meta(paths[i], '${project.id}_clip$i');
      clips.add(VideoClip(
        id: '${DateTime.now().microsecondsSinceEpoch}_$i',
        path: paths[i],
        durationMs: meta.durationMs > 0 ? meta.durationMs : null,
      ));
    }
    project.clips = clips;
    project.videoPath = paths.first; // preview shows clip 1 (sequential = stage 3)
    provider.updateProject(project);

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EditorScreen()),
    );
    _loadStatus();
  }

  Widget _buildHeroButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SetupScreen()),
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: AppGradients.primary,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      tr('home.newProject'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      tr('home.newProjectSub'),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  color: Colors.white70, size: 16),
            ],
          ),
        ),
      ).animate(delay: 100.ms).fadeIn().slideY(begin: 0.1, end: 0),
    );
  }

  Widget _thumb(SubtitleProject p, {double radius = 10}) {
    final ok = p.thumbnailPath != null && File(p.thumbnailPath!).existsSync();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ok
          ? Image.file(File(p.thumbnailPath!), fit: BoxFit.cover)
          : Container(
              color: AppColors.surfaceLight,
              child: const Center(
                child: Icon(
                  Icons.movie_outlined,
                  color: AppColors.primary,
                  size: 30,
                ),
              ),
            ),
    );
  }

  Widget _badges(SubtitleProject p) {
    final hasTrans = p.segments.any((s) => (s.translatedText ?? '').isNotEmpty);
    final hasBroll = p.imageOverlays.any((o) => o.isVideo);
    final hasVoice = (p.aiVoicePath ?? '').isNotEmpty;
    final chips = <Widget>[];
    if (hasTrans) chips.add(_chip(Icons.translate, tr('home.bilingualBadge')));
    if (hasBroll) chips.add(_chip(Icons.movie_creation_outlined, tr('home.brollBadge')));
    if (hasVoice) chips.add(_chip(Icons.graphic_eq, tr('home.voiceBadge')));
    return Wrap(spacing: 6, runSpacing: 4, children: chips);
  }

  Widget _chip(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: AppColors.primary),
        const SizedBox(width: 3),
        Text(
          label,
          style: const TextStyle(color: AppColors.primary, fontSize: 10),
        ),
      ],
    ),
  );

  Widget _buildList(List<SubtitleProject> projects) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      itemCount: projects.length,
      itemBuilder: (context, index) {
        final p = projects[index];
        return GestureDetector(
          onTap: () => _open(p),
          child:
              Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        SizedBox(width: 62, height: 62, child: _thumb(p)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.name,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.schedule,
                                    size: 12,
                                    color: AppColors.textHint,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    _fmtDur(p.videoDuration),
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const Text(
                                    '  •  ',
                                    style: TextStyle(
                                      color: AppColors.textHint,
                                      fontSize: 11,
                                    ),
                                  ),
                                  Text(
                                    '${p.segments.length} ${tr('home.segments')}',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const Text(
                                    '  •  ',
                                    style: TextStyle(
                                      color: AppColors.textHint,
                                      fontSize: 11,
                                    ),
                                  ),
                                  Text(
                                    _fmtDate(p.createdAt),
                                    style: const TextStyle(
                                      color: AppColors.textHint,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              _badges(p),
                            ],
                          ),
                        ),
                        _menu(p),
                      ],
                    ),
                  )
                  .animate(delay: (index * 50).ms)
                  .fadeIn()
                  .slideX(begin: 0.08, end: 0),
        );
      },
    );
  }

  Widget _buildGrid(List<SubtitleProject> projects) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemCount: projects.length,
      itemBuilder: (context, index) {
        final p = projects[index];
        return GestureDetector(
          onTap: () => _open(p),
          child:
              Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Stack(
                            children: [
                              Positioned.fill(child: _thumb(p, radius: 14)),
                              Positioned(
                                right: 6,
                                bottom: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    _fmtDur(p.videoDuration),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 2,
                                top: 2,
                                child: _menu(p, light: true),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.name,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${p.segments.length} ${tr('home.segments')} • ${_fmtDate(p.createdAt)}',
                                style: const TextStyle(
                                  color: AppColors.textHint,
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                  .animate(delay: (index * 50).ms)
                  .fadeIn()
                  .scale(begin: const Offset(0.96, 0.96)),
        );
      },
    );
  }

  Widget _menu(SubtitleProject p, {bool light = false}) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert,
        color: light ? Colors.white : AppColors.textHint,
        size: 20,
      ),
      color: AppColors.surfaceLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (v) async {
        final provider = context.read<ProjectProvider>();
        if (v == 'rename') {
          _renameDialog(p);
        } else if (v == 'dup') {
          provider.duplicateProject(p);
        } else if (v == 'del') {
          final ok = await _confirmDelete(context, p.name);
          if (ok == true && mounted) {
            provider.deleteProject(p.id);
          }
        }
      },
      itemBuilder: (_) => [
        _menuItem('rename', Icons.edit_outlined, tr('home.rename')),
        _menuItem('dup', Icons.copy_all_outlined, tr('home.duplicate')),
        _menuItem('del', Icons.delete_outline, tr('common.delete'), danger: true),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(
    String v,
    IconData icon,
    String label, {
    bool danger = false,
  }) {
    final c = danger ? AppColors.accent : AppColors.textPrimary;
    return PopupMenuItem<String>(
      value: v,
      child: Row(
        children: [
          Icon(icon, size: 18, color: c),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: c, fontSize: 14)),
        ],
      ),
    );
  }

  void _open(SubtitleProject p) async {
    context.read<ProjectProvider>().setCurrentProject(p);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EditorScreen()),
    );
    _loadStatus(); // exporting in the editor may have consumed free quota
  }

  void _renameDialog(SubtitleProject p) {
    final ctrl = TextEditingController(text: p.name);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          tr('home.renameTitle'),
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(hintText: tr('home.projectNameHint')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              tr('common.cancel'),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<ProjectProvider>().renameProject(p.id, ctrl.text);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(tr('common.save')),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(
              Icons.video_library_outlined,
              color: AppColors.textHint,
              size: 40,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            tr('home.empty'),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Text(
            tr('home.emptySub'),
            style: const TextStyle(color: AppColors.textHint, fontSize: 13),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SetupScreen()),
            ),
            icon: const Icon(Icons.add, size: 20),
            label: Text(tr('home.createFirst')),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 46),
              padding: const EdgeInsets.symmetric(horizontal: 22),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context, String name) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.delete_outline, color: AppColors.accent, size: 22),
            const SizedBox(width: 8),
            Text(
              tr('home.deleteTitle'),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
            ),
          ],
        ),
        content: Text(
          tr('home.deleteBody', {'name': name}),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              tr('common.cancel'),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(tr('common.delete'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
