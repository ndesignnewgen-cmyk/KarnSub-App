import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../i18n/i18n.dart';
import '../models/subtitle_style_model.dart';
import '../providers/project_provider.dart';
import '../services/free_quota_service.dart';
import '../services/api_config.dart';
import '../widgets/style_preview_card.dart';
import 'processing_screen.dart';
import 'editor_screen.dart';
import 'settings_screen.dart';

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
  TranslateMode _translateMode = TranslateMode.translate;
  String _sourceLanguage = 'th';
  String _targetLanguage = 'lo';
  String _aiEngine = 'gemini';
  bool _isPro = false;
  bool _proofread = true;
  bool _hasGroqKey = false;
  bool _hasOpenAiKey = false;
  final _nameController = TextEditingController();
  final _hintController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProStatus();
  }

  Future<void> _loadProStatus() async {
    final pro = await FreeQuotaService.isPro();
    final groq = await ApiConfig.hasGroqKey();
    final openAi = await ApiConfig.hasOpenAiKey();
    if (mounted) {
      setState(() {
        _isPro = pro;
        _hasGroqKey = groq;
        _hasOpenAiKey = openAi;
        _aiEngine = 'gemini'; // Default to Gemini
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hintController.dispose();
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
        SnackBar(
          content: Text(tr('setup.pickVideoFirst')),
          backgroundColor: AppColors.accent,
        ),
      );
      return;
    }
    final name = _nameController.text.trim().isEmpty
        ? '${tr('setup.defaultProjectName')} ${DateTime.now().day}/${DateTime.now().month}'
        : _nameController.text.trim();

    final project = context.read<ProjectProvider>().createProject(name);
    project.videoPath = _videoPath;
    project.aspectRatio = _aspectRatio;
    project.selectedStyle = _selectedStyle;
    project.wordSplit = _wordSplit;
    project.translateMode = _translateMode;
    project.language = _targetLanguage;
    project.sourceLanguage = _sourceLanguage;
    project.transcriptionHint = _hintController.text.trim();
    project.proofread = _proofread;
    project.showBilingual = (_translateMode == TranslateMode.bilingual);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ProcessingScreen(
          videoPath: _videoPath!,
          aiEngine: _aiEngine,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(tr('setup.title')),
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
            _buildSectionLabel(tr('setup.projectName')),
            const SizedBox(height: 8),
            _buildNameField(),
            const SizedBox(height: 24),

            _buildSectionLabel(tr('setup.uploadVideo')),
            const SizedBox(height: 8),
            _buildVideoUpload(),
            const SizedBox(height: 24),
            _buildSectionLabel(tr('setup.aspectRatio')),
            const SizedBox(height: 10),
            _buildAspectRatioSelector(),
            const SizedBox(height: 24),
            _buildSectionLabel(tr('setup.subtitleStyle')),
            const SizedBox(height: 10),
            _buildStyleGrid(),
            const SizedBox(height: 24),
            _buildSectionLabel(tr('setup.speechLang')),
            const SizedBox(height: 10),
            _buildSourceLanguageSelector(),
            const SizedBox(height: 24),
            _buildSectionLabel(tr('setup.subtitleLang')),
            const SizedBox(height: 10),
            _buildTargetLanguageSelector(),
            const SizedBox(height: 24),
            _buildSectionLabel(tr('setup.aiEngine')),
            const SizedBox(height: 10),
            _buildAiEngineSelector(),
            if (!_hasGroqKey && !_hasOpenAiKey) ...[
              const SizedBox(height: 10),
              _buildGroqTip(),
            ],
            const SizedBox(height: 24),
            _buildSectionLabel(tr('setup.hint')),
            const SizedBox(height: 8),
            _buildHintField(),
            const SizedBox(height: 14),
            _buildProofreadToggle(),
            const SizedBox(height: 24),
            _buildSectionLabel(tr('setup.translationMode')),
            const SizedBox(height: 10),
            _buildDisplayModeSelector(),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: (_targetLanguage == 'lo') ? null : 0,
              margin: EdgeInsets.only(top: (_targetLanguage == 'lo') ? 12 : 0),
              child: (_targetLanguage == 'lo')
                  ? Builder(
                      builder: (context) {
                        final hasWhisperTiming = _hasGroqKey || _hasOpenAiKey;
                        final isGemini = _aiEngine == 'gemini';
                        
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary.withValues(alpha: 0.15),
                                AppColors.primary.withValues(alpha: 0.05),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isGemini ? Icons.auto_awesome : Icons.bolt,
                                color: AppColors.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isGemini
                                          ? (hasWhisperTiming
                                              ? '⚡️ Hybrid AI Mode (ແນະນຳທີ່ສຸດ)'
                                              : '♊️ Gemini Direct Lao Mode')
                                          : '⚡️ Whisper Direct Transcribe',
                                      style: const TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      isGemini
                                          ? (hasWhisperTiming
                                              ? 'ຖອດສຽງເປັນພາສາລາວທຳມະຊາດດ້ວຍ Gemini + ໃຊ້ Whisper ຈັບເວລາໃຫ້ຕົງສຽງເວົ້າ 100%'
                                              : 'ຖອດສຽງໄທເປັນລາວໂດຍກົງດ້ວຍ Gemini. (ໃສ່ Groq/OpenAI Key ໃນ Settings ເພື່ອໃຫ້ເວລາຕົງເປະ)')
                                          : 'ຖອດສຽງພາສາໄທດ້ວຍ Whisper + ແປເປັນລາວອັດຕະໂນມັດ.',
                                      style: const TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 24),
            _buildSectionLabel(tr('setup.subtitleSplit')),
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
        hintText: tr('setup.nameHint'),
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

  Widget _buildHintField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _hintController,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: tr('setup.hintHint'),
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
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            prefixIcon: const Icon(Icons.spellcheck, color: AppColors.textHint, size: 18),
          ),
        ),
        const SizedBox(height: 6),
        Text(tr('setup.hintDesc'),
            style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
      ],
    );
  }

  Widget _buildProofreadToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.fact_check_outlined, color: AppColors.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('setup.proofread'),
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(tr('setup.proofreadDesc'),
                    style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
              ],
            ),
          ),
          Switch(
            value: _proofread,
            activeColor: AppColors.primary,
            onChanged: (v) => setState(() => _proofread = v),
          ),
        ],
      ),
    );
  }

  Widget _buildGroqTip() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            const Color(0xFF00BFA5).withValues(alpha: 0.15),
            const Color(0xFF00BFA5).withValues(alpha: 0.05),
          ]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF00BFA5).withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.bolt, color: Color(0xFF00BFA5), size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('setup.groqTipTitle'),
                      style: const TextStyle(
                          color: Color(0xFF00BFA5),
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(tr('setup.groqTipBody'),
                      style: const TextStyle(
                          color: Color(0xFF00BFA5), fontSize: 11, height: 1.35)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF00BFA5), size: 20),
          ],
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
                  Text(
                    tr('setup.tapToChange'),
                    style: const TextStyle(color: AppColors.textHint, fontSize: 12),
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
                  Text(
                    tr('setup.tapToPick'),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr('setup.videoFormats'),
                    style: const TextStyle(color: AppColors.textHint, fontSize: 12),
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

  Widget _buildSourceLanguageSelector() {
    final langs = [
      ('th', tr('lang.opt.th'), tr('lang.src.th')),
      ('lo', tr('lang.opt.lo'), tr('lang.src.lo')),
      ('en', tr('lang.opt.en'), tr('lang.src.en')),
      ('', tr('lang.opt.auto'), tr('lang.src.auto')),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        mainAxisExtent: 65,
      ),
      itemCount: langs.length,
      itemBuilder: (context, index) {
        final l = langs[index];
        final isSelected = _sourceLanguage == l.$1;
        return GestureDetector(
          onTap: () {
            setState(() {
              _sourceLanguage = l.$1;
              // If source matches target, turn off translation
              if (_sourceLanguage == _targetLanguage) {
                _translateMode = TranslateMode.none;
              } else if (_targetLanguage == 'lo' && _sourceLanguage == 'th') {
                _translateMode = TranslateMode.translate;
              }
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary.withValues(alpha: 0.12) : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.border,
                width: isSelected ? 1.8 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  l.$2,
                  style: TextStyle(
                    color: isSelected ? AppColors.primary : AppColors.textPrimary,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 2),
                Text(
                  l.$3,
                  style: TextStyle(
                    color: isSelected ? AppColors.primary.withValues(alpha: 0.8) : AppColors.textSecondary,
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTargetLanguageSelector() {
    final langs = [
      ('lo', tr('lang.opt.lo'), tr('lang.tgt.lo')),
      ('th', tr('lang.opt.th'), tr('lang.tgt.th')),
      ('en', tr('lang.opt.en'), tr('lang.tgt.en')),
    ];
    return Row(
      children: langs.map((l) {
        final isSelected = _targetLanguage == l.$1;
        return Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                _targetLanguage = l.$1;
                // If target matches source, turn off translation
                if (_sourceLanguage == _targetLanguage) {
                  _translateMode = TranslateMode.none;
                } else {
                  _translateMode = TranslateMode.translate;
                }
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary.withValues(alpha: 0.12) : AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.border,
                  width: isSelected ? 1.8 : 1,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    l.$2,
                    style: TextStyle(
                      color: isSelected ? AppColors.primary : AppColors.textPrimary,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l.$3,
                    style: TextStyle(
                      color: isSelected ? AppColors.primary.withValues(alpha: 0.8) : AppColors.textSecondary,
                      fontSize: 10,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDisplayModeSelector() {
    // Only show translation/bilingual modes if target != source
    final isTranslating = _sourceLanguage != _targetLanguage;
    final options = [
      (TranslateMode.none, tr('mode.none'), tr('mode.none.sub'), false),
      (TranslateMode.translate, tr('mode.translate'), tr('mode.translate.sub'), true),
      (TranslateMode.bilingual, tr('mode.bilingual'), tr('mode.bilingual.sub'), true),
    ];
    
    return Row(
      children: options.map((o) {
        final isSelected = _translateMode == o.$1;
        final isPremium = o.$4;
        final locked = isPremium && !_isPro;
        
        // If not translating, force TranslateMode.none as selected and disable others
        final disabled = !isTranslating && o.$1 != TranslateMode.none;
        
        return Expanded(
          child: GestureDetector(
            onTap: disabled 
                ? null
                : (locked
                    ? () => _showProFeatureDialog(o.$2)
                    : () => setState(() => _translateMode = o.$1)),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: disabled ? 0.4 : 1.0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                decoration: BoxDecoration(
                  color: isSelected && !disabled
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected && !disabled ? AppColors.primary : AppColors.border,
                    width: isSelected && !disabled ? 1.8 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          o.$2,
                          style: TextStyle(
                            color: isSelected && !disabled ? AppColors.primary : AppColors.textPrimary,
                            fontWeight: isSelected && !disabled ? FontWeight.bold : FontWeight.w500,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (locked) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.lock_outline, size: 10, color: Color(0xFFFFD700)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      o.$3,
                      style: TextStyle(
                        color: isSelected && !disabled ? AppColors.primary.withValues(alpha: 0.8) : AppColors.textSecondary,
                        fontSize: 10,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAiEngineSelector() {
    final engines = [
      ('gemini', tr('engine.gemini'), tr('engine.gemini.sub'), true),
      ('groq', tr('engine.groq'), tr('engine.groq.sub'), _hasGroqKey),
      ('whisper', tr('engine.whisper'), tr('engine.whisper.sub'), _hasOpenAiKey),
    ];
    return Row(
      children: engines.map((e) {
        final isSelected = _aiEngine == e.$1;
        final isAvailable = e.$4;
        return Expanded(
          child: GestureDetector(
            onTap: !isAvailable
                ? () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${e.$2}: ${tr('engine.needKey')}'),
                        backgroundColor: AppColors.accent,
                      ),
                    );
                  }
                : () {
                    setState(() => _aiEngine = e.$1);
                  },
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: isAvailable ? 1.0 : 0.45,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                decoration: BoxDecoration(
                  color: isSelected && isAvailable
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected && isAvailable ? AppColors.primary : AppColors.border,
                    width: isSelected && isAvailable ? 1.8 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          e.$2,
                          style: TextStyle(
                            color: isSelected && isAvailable ? AppColors.primary : AppColors.textPrimary,
                            fontWeight: isSelected && isAvailable ? FontWeight.bold : FontWeight.w500,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (!isAvailable) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.lock_outline, size: 10, color: AppColors.textSecondary),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      e.$3,
                      style: TextStyle(
                        color: isSelected && isAvailable ? AppColors.primary.withValues(alpha: 0.8) : AppColors.textSecondary,
                        fontSize: 9,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildWordSplitOptions() {
    final w = tr('split.word');
    final options = [
      (WordSplit.none, tr('split.none')),
      (WordSplit.one, '1 $w'),
      (WordSplit.two, '2 $w'),
      (WordSplit.three, '3 $w'),
      (WordSplit.four, '4 $w'),
      (WordSplit.six, '6 $w'),
      (WordSplit.eight, '8 $w'),
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
        _buildSectionLabel(tr('setup.previewLabel')),
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
            child: _buildLivePreviewText(tr('setup.previewText')),
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
            _videoPath != null ? tr('setup.createSubtitle') : tr('setup.pickVideoFirst'),
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.edit_outlined, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Text(
            tr('setup.manualType'),
            style: const TextStyle(
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
        SnackBar(
          content: Text(tr('setup.pickVideoFirst')),
          backgroundColor: AppColors.accent,
        ),
      );
      return;
    }
    final name = _nameController.text.trim().isEmpty
        ? '${tr('setup.defaultProjectName')} ${DateTime.now().day}/${DateTime.now().month}'
        : _nameController.text.trim();

    final project = context.read<ProjectProvider>().createProject(name);
    project.videoPath = _videoPath;
    project.aspectRatio = _aspectRatio;
    project.selectedStyle = _selectedStyle;
    project.wordSplit = _wordSplit;
    project.language = _targetLanguage;

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
        content: Text(
          tr('pro.dialogBody'),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              tr('common.close'),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
            ),
            child: Text(tr('pro.upgrade')),
          ),
        ],
      ),
    );
  }
}
