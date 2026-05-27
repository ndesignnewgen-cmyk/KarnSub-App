import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../models/subtitle_style_model.dart';
import '../providers/project_provider.dart';
import '../services/free_quota_service.dart';
import '../widgets/style_preview_card.dart';
import 'processing_screen.dart';
import 'editor_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  String? _videoPath;
  String? _videoName;
  AspectRatioMode _aspectRatio = AspectRatioMode.ratio9x16;
  SubtitlePreset _selectedStyle = subtitlePresets.first;
  WordSplit _wordSplit = WordSplit.none;
  TranslateMode _translateMode = TranslateMode.none;
  String _language = 'lo';
  bool _isPro = false;
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProStatus();
  }

  Future<void> _loadProStatus() async {
    final pro = await FreeQuotaService.isPro();
    if (mounted) setState(() => _isPro = pro);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _videoPath = result.files.first.path;
        _videoName = result.files.first.name;
        if (_nameController.text.isEmpty) {
          _nameController.text = result.files.first.name.replaceAll(
            RegExp(r'\.[^\.]+$'),
            '',
          );
        }
      });
    }
  }

  void _startProcessing() {
    if (_videoPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ກາລຸນາເລືອກວິດີໂອກ່ອນ'),
          backgroundColor: AppColors.accent,
        ),
      );
      return;
    }
    final name = _nameController.text.trim().isEmpty
        ? 'ໂປຣເຈກ ${DateTime.now().day}/${DateTime.now().month}'
        : _nameController.text.trim();

    final project = context.read<ProjectProvider>().createProject(name);
    project.videoPath = _videoPath;
    project.aspectRatio = _aspectRatio;
    project.selectedStyle = _selectedStyle;
    project.wordSplit = _wordSplit;
    project.translateMode = _translateMode;
    project.language = _language;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ProcessingScreen(videoPath: _videoPath!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('ໂປຣເຈກໃໝ່'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionLabel('ຊື່ໂປຣເຈກ'),
            const SizedBox(height: 8),
            _buildNameField(),
            const SizedBox(height: 24),
            _buildSectionLabel('ອັບໂຫລດວິດີໂອ'),
            const SizedBox(height: 8),
            _buildVideoUpload(),
            const SizedBox(height: 24),
            _buildSectionLabel('ອັດຕາສ່ວນ'),
            const SizedBox(height: 10),
            _buildAspectRatioSelector(),
            const SizedBox(height: 24),
            _buildSectionLabel('ສໄຕລ໌ Subtitle'),
            const SizedBox(height: 10),
            _buildStyleGrid(),
            const SizedBox(height: 24),
            _buildSectionLabel('ການແປພາສາ'),
            const SizedBox(height: 10),
            _buildTranslateOptions(),
            const SizedBox(height: 24),
            _buildSectionLabel('ພາສາທີ່ເວົ້າໃນວິດີໂອ'),
            const SizedBox(height: 10),
            _buildLanguageSelector(),
            const SizedBox(height: 24),
            _buildSectionLabel('ການແບ່ງ Subtitle'),
            const SizedBox(height: 10),
            _buildWordSplitOptions(),
            const SizedBox(height: 24),
            _buildPreviewBox(),
            const SizedBox(height: 32),
            _buildStartButton(),
            const SizedBox(height: 12),
            _buildManualButton(),
            const SizedBox(height: 20),
          ],
        ),
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

  Widget _buildNameField() {
    return TextField(
      controller: _nameController,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: 'ເຊັ່ນ: ຄລິບສອນທຳອາຫານ EP.1',
        hintStyle: const TextStyle(color: AppColors.textHint),
        filled: true,
        fillColor: AppColors.surface,
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
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }

  Widget _buildVideoUpload() {
    return GestureDetector(
      onTap: _pickVideo,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        height: 140,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _videoPath != null ? AppColors.primary : AppColors.border,
            width: _videoPath != null ? 1.5 : 1,
            style: _videoPath != null ? BorderStyle.solid : BorderStyle.solid,
          ),
        ),
        child: _videoPath != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: AppColors.success,
                    size: 36,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _videoName ?? '',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'ແຕະເພື່ອປ່ຽນວິດີໂອ',
                    style: TextStyle(color: AppColors.textHint, fontSize: 12),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.upload_rounded,
                      color: AppColors.primary,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'ແຕະເລືອກວິດີໂອ',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'MP4, MOV, AVI • ສູງສຸດ 10 ນາທີ',
                    style: TextStyle(color: AppColors.textHint, fontSize: 12),
                  ),
                ],
              ),
      ),
    ).animate().fadeIn(delay: 100.ms);
  }

  Widget _buildAspectRatioSelector() {
    final ratios = [
      (AspectRatioMode.ratio9x16, '9:16', Icons.phone_android),
      (AspectRatioMode.ratio1x1, '1:1', Icons.crop_square),
      (AspectRatioMode.ratio16x9, '16:9', Icons.laptop),
      (AspectRatioMode.ratio4x5, '4:5', Icons.crop_portrait),
    ];
    return Row(
      children: ratios.map((r) {
        final isSelected = _aspectRatio == r.$1;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _aspectRatio = r.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withOpacity(0.15)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.border,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    r.$3,
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    size: 18,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    r.$2,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStyleGrid() {
    return GridView.builder(
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
        final locked = preset.isPro && !_isPro;
        return StylePreviewCard(
          preset: preset,
          isSelected: _selectedStyle.type == preset.type,
          locked: locked,
          onTap: () {
            if (locked) {
              _showProFeatureDialog('ສະໄຕລ໌ ${preset.name}');
              return;
            }
            setState(() => _selectedStyle = preset);
          },
        );
      },
    );
  }

  Widget _buildTranslateOptions() {
    final options = [
      (TranslateMode.none, 'ບໍ່ແປ', false),
      (TranslateMode.translate, 'ແປພາສາ', true),
      (TranslateMode.bilingual, 'Bilingual', true),
    ];
    return Row(
      children: options.map((o) {
        final isSelected = _translateMode == o.$1;
        final isPremium = o.$3;
        final locked = isPremium && !_isPro;
        return Expanded(
          child: GestureDetector(
            onTap: locked
                ? () => _showProFeatureDialog(o.$2)
                : () => setState(() => _translateMode = o.$1),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withOpacity(0.15)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.border,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    o.$2,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (locked) ...[
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'PRO',
                        style: TextStyle(color: Color(0xFFFFD700), fontSize: 9),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLanguageSelector() {
    final langs = [('lo', 'ລາວ'), ('th', 'ໄທ'), ('en', 'ອັງກິດ'), ('', 'Auto')];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: langs.map((l) {
          final isSelected = _language == l.$1;
          return GestureDetector(
            onTap: () => setState(() => _language = l.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.border,
                ),
              ),
              child: Text(
                l.$2,
                style: TextStyle(
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildWordSplitOptions() {
    final options = [
      (WordSplit.none, 'ບໍ່ແບ່ງ'),
      (WordSplit.one, '1 ຄຳ'),
      (WordSplit.two, '2 ຄຳ'),
      (WordSplit.three, '3 ຄຳ'),
      (WordSplit.four, '4 ຄຳ'),
      (WordSplit.six, '6 ຄຳ'),
      (WordSplit.eight, '8 ຄຳ'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.map((o) {
          final isSelected = _wordSplit == o.$1;
          return GestureDetector(
            onTap: () => setState(() => _wordSplit = o.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.border,
                ),
              ),
              child: Text(
                o.$2,
                style: TextStyle(
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPreviewBox() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('ຕົວຢ່າງ Subtitle'),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          height: 80,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Center(
            child: _buildLivePreviewText('ນີ້ຄືຕົວຢ່າງ subtitle ຂອງເຈົ້າ'),
          ),
        ),
      ],
    );
  }

  Widget _buildLivePreviewText(String text) {
    final preset = _selectedStyle;
    Widget textWidget;

    if (preset.hasNeonGlow) {
      textWidget = Text(
        text,
        style: TextStyle(
          color: preset.textColor,
          fontWeight: preset.fontWeight,
          fontSize: preset.fontSize,
          shadows: [
            Shadow(color: preset.glowColor ?? preset.textColor, blurRadius: 14),
            Shadow(color: preset.glowColor ?? preset.textColor, blurRadius: 28),
          ],
        ),
      );
    } else if (preset.hasUnderline) {
      textWidget = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(
              color: preset.textColor,
              fontWeight: preset.fontWeight,
              fontSize: preset.fontSize,
            ),
          ),
          const SizedBox(height: 3),
          Container(
            width: 120,
            height: 3,
            decoration: BoxDecoration(
              color: preset.underlineColor ?? AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      );
    } else {
      textWidget = Text(
        text,
        style: TextStyle(
          color: preset.textColor,
          fontWeight: preset.fontWeight,
          fontSize: preset.fontSize,
          shadows: preset.hasShadow
              ? [
                  const Shadow(
                    color: Colors.black,
                    blurRadius: 8,
                    offset: Offset(1, 2),
                  ),
                ]
              : null,
        ),
      );
    }

    if (preset.backgroundColor != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: preset.backgroundColor,
          borderRadius: BorderRadius.circular(6),
        ),
        child: textWidget,
      );
    }
    return textWidget;
  }

  Widget _buildStartButton() {
    return ElevatedButton(
      onPressed: _startProcessing,
      style: ElevatedButton.styleFrom(
        backgroundColor: _videoPath != null
            ? AppColors.primary
            : AppColors.surfaceLight,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.auto_awesome, size: 20),
          const SizedBox(width: 8),
          Text(
            _videoPath != null ? 'ສ້າງ Subtitle →' : 'ກາລຸນາເລືອກວິດີໂອກ່ອນ',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildManualButton() {
    return OutlinedButton(
      onPressed: _startManual,
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.border),
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.edit_outlined, size: 18, color: AppColors.textSecondary),
          SizedBox(width: 8),
          Text(
            'ພິມ subtitle ດ້ວຍຕົນເອງ',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _startManual() {
    if (_videoPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ກາລຸນາເລືອກວິດີໂອກ່ອນ'),
          backgroundColor: AppColors.accent,
        ),
      );
      return;
    }
    final name = _nameController.text.trim().isEmpty
        ? 'ໂປຣເຈກ ${DateTime.now().day}/${DateTime.now().month}'
        : _nameController.text.trim();

    final project = context.read<ProjectProvider>().createProject(name);
    project.videoPath = _videoPath;
    project.aspectRatio = _aspectRatio;
    project.selectedStyle = _selectedStyle;
    project.wordSplit = _wordSplit;
    project.language = _language;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const EditorScreen()),
    );
  }

  void _showProFeatureDialog(String featureName) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.star_rounded, color: Color(0xFFFFD700), size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'PRO: $featureName',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'ຟີເຈີນີ້ສຳລັບ PRO ເທົ່ານັ້ນ\nສະມັກ PRO 39,000 ກີບ/ເດືອນ ໃນໜ້າ "ຕັ້ງຄ່າ"',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'ປິດ',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
            ),
            child: const Text('Upgrade PRO'),
          ),
        ],
      ),
    );
  }
}
