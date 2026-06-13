import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../i18n/i18n.dart';
import '../providers/project_provider.dart';
import '../models/subtitle_style_model.dart';
import '../services/export_service.dart';
import '../services/free_quota_service.dart';
import '../widgets/gradient_button.dart';

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  ExportType _exportType = ExportType.videoWithSubtitle;
  ExportQuality _quality = ExportQuality.fhd1080;
  bool _isExporting = false;
  double _exportProgress = 0;
  String _exportStatus = '';
  // 'top' or 'bottom' — where the free-tier watermark is stamped.
  String _watermarkPosition = 'top';
  bool _isPro = false;
  int _freeFhd = FreeQuotaService.freeFhdPerDay;
  // Absolute path of the last successful export, used by the Share button.
  String? _lastExportedPath;

  @override
  void initState() {
    super.initState();
    _exportStatus = tr('ex.exporting');
    _loadPro();
  }

  Future<void> _loadPro() async {
    final pro = await FreeQuotaService.isPro();
    final fhd = await FreeQuotaService.remainingFhdExports();
    if (mounted) {
      setState(() {
        _isPro = pro;
        _freeFhd = fhd;
      });
    }
  }

  Future<void> _startExport() async {
    HapticFeedback.mediumImpact(); // big-action feedback
    final project = context.read<ProjectProvider>().currentProject;
    if (project == null) return;

    if (project.segments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('ex.noSubtitle')),
          backgroundColor: AppColors.accent,
        ),
      );
      return;
    }

    // Free users always get the watermark; PRO never does.
    final isPro = await FreeQuotaService.isPro();
    if (!mounted) return;
    final bool withWatermark = !isPro;

    // Free users: FHD (1080p) is capped at 3/day; HD (720p) is unlimited.
    if (_exportType == ExportType.videoWithSubtitle &&
        !isPro &&
        _quality == ExportQuality.fhd1080) {
      final remaining = await FreeQuotaService.remainingFhdExports();
      if (!mounted) return;
      if (remaining <= 0) {
        final action = await _showFhdLimitDialog();
        if (action == null) return; // cancelled
        if (action == 'upgrade') {
          _showUpgradeInfo();
          return;
        }
        // action == 'hd' → downgrade quality and continue
        setState(() => _quality = ExportQuality.hd720);
      } else {
        await FreeQuotaService.useFhdExport();
      }
    }

    setState(() {
      _isExporting = true;
      _exportProgress = 0;
      _exportStatus = tr('ex.preparing');
    });

    try {
      if (_exportType == ExportType.videoWithSubtitle) {
        final videoPath = project.videoPath;
        if (videoPath == null) {
          throw ExportException(tr('ex.noVideo'));
        }

        _lastExportedPath = await ExportService.exportVideoWithSubtitles(
          videoPath,
          project.segments,
          project,
          _quality,
          (prog, status) {
            if (!mounted) return;
            setState(() {
              _exportProgress = prog;
              _exportStatus = status;
            });
          },
          withWatermark: withWatermark,
          watermarkPosition: _watermarkPosition,
        );
      } else {
        setState(() {
          _exportProgress = 0.3;
          _exportStatus = tr('ex.creatingSrt');
        });
        _lastExportedPath =
            await ExportService.exportSrtFile(project.segments, project.name);
        setState(() {
          _exportProgress = 1.0;
          _exportStatus = tr('ex.done');
        });
      }

      if (mounted) {
        setState(() => _isExporting = false);
        _loadPro(); // refresh remaining FHD quota
        _showSuccessDialog();
      }
    } on ExportException catch (e) {
      if (mounted) {
        setState(() => _isExporting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 10),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExporting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${tr('ex.errPrefix')}$e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 10),
        ));
      }
    }
  }

  /// Shown when a free user hits the daily FHD limit.
  /// Returns 'hd' (export 720p instead), 'upgrade', or null (cancel).
  Future<String?> _showFhdLimitDialog() async {
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: AppColors.primary, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr('ex.fhdLimitTitle'),
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
          children: [
            Text(
              tr('ex.fhdLimitBody'),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            _exportChoice(
              icon: Icons.sd_rounded,
              title: tr('ex.choiceHd'),
              subtitle: tr('ex.choiceHdSub'),
              color: AppColors.primary,
              onTap: () => Navigator.pop(context, 'hd'),
            ),
            const SizedBox(height: 10),
            _exportChoice(
              icon: Icons.star_rounded,
              title: tr('ex.choiceUpgrade'),
              subtitle: tr('ex.choiceUpgradeSub'),
              color: const Color(0xFFFFD700),
              onTap: () => Navigator.pop(context, 'upgrade'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: Text(
              tr('common.cancel'),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _exportChoice({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Compact top/bottom selector for the (free-tier) watermark position.
  Widget _watermarkPositionPicker() {
    Widget opt(String value, String label, IconData icon) {
      final selected = _watermarkPosition == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _watermarkPosition = value),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('ex.watermarkPos'),
          style: const TextStyle(color: AppColors.textHint, fontSize: 11),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            opt('top', tr('ex.posTop'), Icons.vertical_align_top_rounded),
            const SizedBox(width: 8),
            opt('bottom', tr('ex.posBottom'),
                Icons.vertical_align_bottom_rounded),
          ],
        ),
      ],
    );
  }

  void _showUpgradeInfo() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          tr('ex.proFeaturesTitle'),
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          tr('ex.proFeaturesBody'),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('ex.gotIt')),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog() {
    final isVideo = _exportType == ExportType.videoWithSubtitle;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: AppColors.success,
                size: 42,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isVideo ? tr('ex.successVideo') : tr('ex.successSrt'),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isVideo ? tr('ex.savedVideo') : tr('ex.savedSrt'),
              style: const TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            GradientButton(
              label: tr('ex.share'),
              icon: Icons.ios_share_rounded,
              height: 48,
              onTap: _shareLastExport,
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              icon: const Icon(Icons.check_rounded,
                  color: AppColors.textSecondary, size: 18),
              label: Text(
                tr('ex.backToEdit'),
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Share the just-exported file via the system sheet (TikTok / Reels / LINE…).
  Future<void> _shareLastExport() async {
    final path = _lastExportedPath;
    if (path == null || !File(path).existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('ex.errPrefix'))),
        );
      }
      return;
    }
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], text: tr('ex.shareText')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(tr('ex.title')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Consumer<ProjectProvider>(
        builder: (context, provider, _) {
          final project = provider.currentProject;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildVideoThumbnail(project),
                const SizedBox(height: 24),
                _buildSectionLabel(tr('ex.format')),
                const SizedBox(height: 12),
                _buildExportTypeSelector(),
                const SizedBox(height: 24),
                if (_exportType == ExportType.videoWithSubtitle) ...[
                  _buildSectionLabel(tr('ex.quality')),
                  const SizedBox(height: 12),
                  _buildQualitySelector(),
                  if (!_isPro) ...[
                    const SizedBox(height: 8),
                    _buildFhdQuotaNote(),
                  ],
                  const SizedBox(height: 24),
                ],
                if (_exportType == ExportType.videoWithSubtitle && !_isPro) ...[
                  _buildSectionLabel(tr('ex.watermark')),
                  const SizedBox(height: 8),
                  Text(
                    tr('ex.watermarkNote'),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _watermarkPositionPicker(),
                  const SizedBox(height: 24),
                ],
                _buildSummaryCard(project),
                // Effects force the slower CPU render path — warn up front so a
                // long export doesn't look like the app froze.
                if (_exportType == ExportType.videoWithSubtitle &&
                    project != null &&
                    (project.imageOverlays.isNotEmpty ||
                        project.zoomEffects.isNotEmpty ||
                        project.fadeEffects.isNotEmpty ||
                        project.shakeEffects.isNotEmpty ||
                        project.bgBlur)) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    const Icon(Icons.hourglass_bottom_rounded,
                        size: 14, color: AppColors.textHint),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        tr('ex.slowEffects'),
                        style: const TextStyle(
                            color: AppColors.textHint, fontSize: 11.5),
                      ),
                    ),
                  ]),
                ],
                const SizedBox(height: 32),
                if (_isExporting)
                  _buildExportingProgress()
                else
                  _buildExportButton(),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  String _fmtDur(Duration? d) {
    if (d == null) return '';
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  Widget _buildVideoThumbnail(SubtitleProject? project) {
    final name = project?.name ?? '';
    final segmentCount = project?.segments.length ?? 0;
    final thumbPath = project?.thumbnailPath;
    final hasThumb = thumbPath != null && File(thumbPath).existsSync();
    final dur = _fmtDur(project?.videoDuration);
    return Container(
      width: double.infinity,
      height: 120,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius:
                const BorderRadius.horizontal(left: Radius.circular(16)),
            child: SizedBox(
              width: 90,
              height: double.infinity,
              child: hasThumb
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(File(thumbPath), fit: BoxFit.cover),
                        if (dur.isNotEmpty)
                          Positioned(
                            right: 4,
                            bottom: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                dur,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 9),
                              ),
                            ),
                          ),
                      ],
                    )
                  : Container(
                      color: Colors.black,
                      child: const Center(
                        child: Icon(Icons.movie,
                            color: AppColors.primary, size: 36),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  tr('ex.segCount', {'n': segmentCount}),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    ).animate().fadeIn();
  }

  /// Free-tier FHD quota note shown beneath the quality selector.
  Widget _buildFhdQuotaNote() {
    final out = _freeFhd <= 0;
    return Row(
      children: [
        Icon(out ? Icons.lock_clock : Icons.bolt,
            size: 14, color: out ? AppColors.accent : AppColors.primary),
        const SizedBox(width: 5),
        Text(
          out ? tr('ex.fhdOut') : tr('ex.fhdRemaining', {'n': _freeFhd}),
          style: TextStyle(
            color: out ? AppColors.accent : AppColors.textSecondary,
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }

  Widget _buildExportTypeSelector() {
    return Column(
      children: [
        _buildExportOption(
          type: ExportType.videoWithSubtitle,
          icon: Icons.movie_creation_outlined,
          title: tr('ex.typeVideo'),
          subtitle: tr('ex.typeVideoSub'),
        ),
        const SizedBox(height: 10),
        _buildExportOption(
          type: ExportType.srtOnly,
          icon: Icons.subtitles_outlined,
          title: tr('ex.typeSrt'),
          subtitle: tr('ex.typeSrtSub'),
        ),
      ],
    );
  }

  Widget _buildExportOption({
    required ExportType type,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final isSelected = _exportType == type;
    return GestureDetector(
      onTap: () => setState(() => _exportType = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.2)
                    : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: AppColors.primary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQualitySelector() {
    return Row(
      children: [
        _buildQualityChip(ExportQuality.hd720, '720p HD'),
        const SizedBox(width: 10),
        _buildQualityChip(ExportQuality.fhd1080, '1080p FHD'),
      ],
    );
  }

  Widget _buildQualityChip(ExportQuality q, String label) {
    final isSelected = _quality == q;
    return GestureDetector(
      onTap: () => setState(() => _quality = q),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(project) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('ex.summary'),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _summaryRow(
            tr('ex.sumFormat'),
            _exportType == ExportType.videoWithSubtitle
                ? 'MP4 + Subtitle'
                : 'SRT Only',
          ),
          if (_exportType == ExportType.videoWithSubtitle)
            _summaryRow(
              tr('ex.sumQuality'),
              _quality == ExportQuality.fhd1080 ? '1080p FHD' : '720p HD',
            ),
          if (_exportType == ExportType.videoWithSubtitle) ...[
            _summaryRow(tr('ex.sumOrigAudio'), (project?.originalMuted ?? false) ? tr('ex.audioOff') : tr('ex.audioOn')),
            _summaryRow(tr('ex.sumSfx'), (project?.sfxBlocks.isNotEmpty ?? false) ? tr('ex.has') : tr('ex.none')),
            _summaryRow(tr('ex.sumAiVoice'), (project?.aiVoicePath != null) ? tr('ex.has') : tr('ex.none')),
          ],
          _summaryRow(tr('ex.sumStyle'), project?.selectedStyle.name ?? '-'),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExportingProgress() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _exportStatus,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${(_exportProgress * 100).toInt()}%',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _exportProgress,
              minHeight: 8,
              backgroundColor: AppColors.surfaceLight,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.warning_amber_outlined,
                color: AppColors.textHint,
                size: 14,
              ),
              const SizedBox(width: 4),
              Text(
                tr('ex.dontLeave'),
                style: const TextStyle(color: AppColors.textHint, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExportButton() {
    return GradientButton(
      label: _exportType == ExportType.videoWithSubtitle
          ? tr('ex.exportVideoBtn')
          : tr('ex.exportSrtBtn'),
      icon: Icons.download_rounded,
      height: 56,
      onTap: _startExport,
    );
  }
}

enum ExportType { videoWithSubtitle, srtOnly }
