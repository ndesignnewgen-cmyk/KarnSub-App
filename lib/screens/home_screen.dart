import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/project_provider.dart';
import '../models/subtitle_style_model.dart';
import '../services/media_info_service.dart';
import 'setup_screen.dart';
import 'editor_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _grid = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _generateThumbs());
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
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, projects.length),
                _buildHeroButton(context),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 16, 8),
                  child: Row(
                    children: [
                      const Text(
                        'ໂປຣເຈກຫຼ້າສຸດ',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const Spacer(),
                      if (projects.isNotEmpty)
                        _iconBtn(
                          _grid
                              ? Icons.view_list_rounded
                              : Icons.grid_view_rounded,
                          () => setState(() => _grid = !_grid),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: projects.isEmpty
                      ? _buildEmptyState(context)
                      : (_grid ? _buildGrid(projects) : _buildList(projects)),
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
                  color: AppColors.primary.withOpacity(0.35),
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
                  count == 0 ? 'ສ້າງ subtitle ໄວ ດ້ວຍ AI' : 'ມີ $count ໂປຣເຈກ',
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
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ).animate().fadeIn(duration: 350.ms),
    );
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
          height: 110,
          decoration: BoxDecoration(
            gradient: AppGradients.primary,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.4),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -16,
                top: -16,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.07),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.add,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'ສ້າງໂປຣເຈກໃໝ່',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'ອັບໂຫລດ video → AI ສ້າງ subtitle',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
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
    final chips = <Widget>[];
    if (hasTrans) chips.add(_chip(Icons.translate, '2 ພາສາ'));
    return Wrap(spacing: 6, runSpacing: 4, children: chips);
  }

  Widget _chip(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.primary.withOpacity(0.15),
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
                                    '${p.segments.length} ປ່ອນ',
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
                                    color: Colors.black.withOpacity(0.6),
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
                                '${p.segments.length} ປ່ອນ • ${_fmtDate(p.createdAt)}',
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
        _menuItem('rename', Icons.edit_outlined, 'ປ່ຽນຊື່'),
        _menuItem('dup', Icons.copy_all_outlined, 'ສຳເນົາ'),
        _menuItem('del', Icons.delete_outline, 'ລຶບ', danger: true),
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

  void _open(SubtitleProject p) {
    context.read<ProjectProvider>().setCurrentProject(p);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EditorScreen()),
    );
  }

  void _renameDialog(SubtitleProject p) {
    final ctrl = TextEditingController(text: p.name);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'ປ່ຽນຊື່ໂປຣເຈກ',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(hintText: 'ຊື່ໂປຣເຈກ'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'ຍົກເລີກ',
              style: TextStyle(color: AppColors.textSecondary),
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
            child: const Text('ບັນທຶກ'),
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
          const Text(
            'ຍັງບໍ່ມີໂປຣເຈກ',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
          ),
          const SizedBox(height: 6),
          const Text(
            'ກົດ "ສ້າງໂປຣເຈກໃໝ່" ເພື່ອເລີ່ມ',
            style: TextStyle(color: AppColors.textHint, fontSize: 13),
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
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: AppColors.accent, size: 22),
            SizedBox(width: 8),
            Text(
              'ລຶບໂປຣເຈກ',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
            ),
          ],
        ),
        content: Text(
          'ຕ້ອງການລຶບ "$name" ບໍ?\nຂໍ້ມູນຈະຫາຍໄປຖາວອນ',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'ຍົກເລີກ',
              style: TextStyle(color: AppColors.textSecondary),
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
            child: const Text('ລຶບ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
