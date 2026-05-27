import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/project_provider.dart';
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
  String _exportStatus = 'ກຳລັງ Export...';
  // 'top' or 'bottom' — where the free-tier watermark is stamped.
  String _watermarkPosition = 'top';
  bool _isPro = false;

  @override
  void initState() {
    super.initState();
    _loadPro();
  }

  Future<void> _loadPro() async {
    final pro = await FreeQuotaService.isPro();
    if (mounted) setState(() => _isPro = pro);
  }

  Future<void> _startExport() async {
    final project = context.read<ProjectProvider>().currentProject;
    if (project == null) return;

    if (project.segments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ບໍ່ມີ Subtitle — ກາລຸນາຖອດສຽງກ່ອນ'),
          backgroundColor: AppColors.accent,
        ),
      );
      return;
    }

    // Free users always get the watermark; PRO never does.
    final isPro = await FreeQuotaService.isPro();
    if (!mounted) return;
    final bool withWatermark = !isPro;

    // Free users: FHD (1080p) is capped at 1/day; HD (720p) is unlimited.
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
      _exportStatus = 'ກຳລັງກຽມ...';
    });

    try {
      if (_exportType == ExportType.videoWithSubtitle) {
        final videoPath = project.videoPath;
        if (videoPath == null) {
          throw ExportException('ບໍ່ພົບໄຟລ໌ວິດີໂອ — ກາລຸນາເລືອກວິດີໂອໃໝ່');
        }

        await ExportService.exportVideoWithSubtitles(
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
          _exportStatus = 'ກຳລັງສ້າງ SRT file...';
        });
        await ExportService.exportSrtFile(project.segments, project.name);
        setState(() {
          _exportProgress = 1.0;
          _exportStatus = 'ສຳເລັດ!';
        });
      }

      if (mounted) {
        setState(() => _isExporting = false);
        _showSuccessDialog();
      }
    } on ExportException catch (e) {
      if (mounted) {
        setState(() => _isExporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.accent),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ຜິດພາດ: $e'),
            backgroundColor: AppColors.accent,
          ),
        );
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
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: AppColors.primary, size: 22),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'FHD ໝົດໂຄຕ້າມື້ນີ້',
                style: TextStyle(
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
            const Text(
              'ຟຣີ Export FHD (1080p) ໄດ້ 1 ຄັ້ງ/ມື້ — ໝົດແລ້ວ\nເລືອກ Export HD (720p) ຫຼື Upgrade PRO',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            _exportChoice(
              icon: Icons.sd_rounded,
              title: 'Export HD (720p)',
              subtitle: 'ບໍ່ຈຳກັດ — ຍັງຕິດ watermark',
              color: AppColors.primary,
              onTap: () => Navigator.pop(context, 'hd'),
            ),
            const SizedBox(height: 10),
            _exportChoice(
              icon: Icons.star_rounded,
              title: 'Upgrade PRO',
              subtitle: 'FHD ບໍ່ຈຳກັດ, ບໍ່ຕິດ watermark',
              color: const Color(0xFFFFD700),
              onTap: () => Navigator.pop(context, 'upgrade'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text(
              'ຍົກເລີກ',
              style: TextStyle(color: AppColors.textSecondary),
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
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.4)),
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
                  ? AppColors.primary.withOpacity(0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
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
        const Text(
          'ຕຳແໜ່ງລາຍນ້ຳ:',
          style: TextStyle(color: AppColors.textHint, fontSize: 11),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            opt('top', 'ສົ້ນເທິງ', Icons.vertical_align_top_rounded),
            const SizedBox(width: 8),
            opt('bottom', 'ສົ້ນລຸ່ມ', Icons.vertical_align_bottom_rounded),
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
        title: const Text(
          '✨ PRO Features',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          '• Export FHD ບໍ່ຕິດ watermark (ບໍ່ຈຳກັດ)\n'
          '• Karaoke Highlight\n'
          '• ຊັບສອງພາສາ (Bilingual)\n\n'
          'ພຽງ 39,000 ກີບ/ເດືອນ — ສະມັກ PRO ທາງ WhatsApp ໃນໜ້າ "ຕັ້ງຄ່າ"',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ຮັບຊາບ'),
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
                color: AppColors.success.withOpacity(0.15),
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
              isVideo ? 'Export ວິດີໂອສຳເລັດ!' : 'Export SRT ສຳເລັດ!',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isVideo
                  ? 'ວິດີໂອຖືກບັນທຶກໃສ່ Movies/SubtitleAI ໃນ Gallery ແລ້ວ'
                  : 'ໄຟລ໌ .srt ຖືກບັນທຶກໃສ່ Download/SubtitleAI ແລ້ວ',
              style: const TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            GradientButton(
              label: 'ກັບໄປແກ້ໄຂ',
              icon: Icons.check_rounded,
              height: 48,
              onTap: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Export'),
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
                _buildVideoThumbnail(
                  project?.name ?? 'ວິດີໂອ',
                  project?.segments.length ?? 0,
                ),
                const SizedBox(height: 24),
                _buildSectionLabel('ຮູບແບບ Export'),
                const SizedBox(height: 12),
                _buildExportTypeSelector(),
                const SizedBox(height: 24),
                if (_exportType == ExportType.videoWithSubtitle) ...[
                  _buildSectionLabel('ຄຸນນະພາບ'),
                  const SizedBox(height: 12),
                  _buildQualitySelector(),
                  const SizedBox(height: 24),
                ],
                if (_exportType == ExportType.videoWithSubtitle && !_isPro) ...[
                  _buildSectionLabel('ລາຍນ້ຳ (Watermark)'),
                  const SizedBox(height: 8),
                  const Text(
                    'ແບບຟຣີຈະຕິດ logo KarnSub — ເລືອກຕຳແໜ່ງ:',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _watermarkPositionPicker(),
                  const SizedBox(height: 24),
                ],
                _buildSummaryCard(project),
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

  Widget _buildVideoThumbnail(String name, int segmentCount) {
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
          Container(
            width: 90,
            height: double.infinity,
            decoration: const BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.horizontal(left: Radius.circular(16)),
            ),
            child: const Center(
              child: Icon(Icons.movie, color: AppColors.primary, size: 36),
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
                  '$segmentCount ປ່ອນ subtitle',
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

  Widget _buildExportTypeSelector() {
    return Column(
      children: [
        _buildExportOption(
          type: ExportType.videoWithSubtitle,
          icon: Icons.movie_creation_outlined,
          title: 'Video + Subtitle (Burn-in)',
          subtitle: 'ຕໍ່ subtitle ເຂົ້າວິດີໂອ, Export MP4',
        ),
        const SizedBox(height: 10),
        _buildExportOption(
          type: ExportType.srtOnly,
          icon: Icons.subtitles_outlined,
          title: 'SRT File ເທົ່ານັ້ນ',
          subtitle: 'Export .srt ສຳລັບ TikTok / YouTube',
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
              ? AppColors.primary.withOpacity(0.12)
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
                    ? AppColors.primary.withOpacity(0.2)
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
          borderRadius: BorderRadius.circular(12),
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
          const Text(
            'ສະຫຼຸບ',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _summaryRow(
            'ຮູບແບບ',
            _exportType == ExportType.videoWithSubtitle
                ? 'MP4 + Subtitle'
                : 'SRT Only',
          ),
          if (_exportType == ExportType.videoWithSubtitle)
            _summaryRow(
              'ຄຸນນະພາບ',
              _quality == ExportQuality.fhd1080 ? '1080p FHD' : '720p HD',
            ),
          _summaryRow('ສໄຕລ໌', project?.selectedStyle.name ?? '-'),
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
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.warning_amber_outlined,
                color: AppColors.textHint,
                size: 14,
              ),
              SizedBox(width: 4),
              Text(
                'ຢ່ານອກ app ໃນຂະນະ export',
                style: TextStyle(color: AppColors.textHint, fontSize: 12),
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
          ? 'Export Video'
          : 'Export SRT',
      icon: Icons.download_rounded,
      height: 56,
      onTap: _startExport,
    );
  }
}

enum ExportType { videoWithSubtitle, srtOnly }
