import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../models/subtitle_style_model.dart';
import '../providers/project_provider.dart';
import '../services/gemini_speech_service.dart';
import '../services/openai_whisper_service.dart';
import '../services/groq_speech_service.dart';
import '../services/audio_sync_service.dart';
import '../services/lao_word_service.dart';
import '../services/api_config.dart';
import 'editor_screen.dart';
import 'settings_screen.dart';

class ProcessingScreen extends StatefulWidget {
  final String videoPath;
  final String aiEngine;

  const ProcessingScreen({
    super.key,
    required this.videoPath,
    this.aiEngine = 'gemini',
  });

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  double _progress = 0;
  String _statusText = 'ກຳລັງກຽມໄຟລ໌...';
  bool _hasError = false;
  String _errorMessage = '';

  late final List<_StepItem> _steps;
  int _currentStep = 0;
  String _actualEngine = 'gemini';

  @override
  void initState() {
    super.initState();
    _actualEngine = widget.aiEngine;
    _start();
  }

  Future<void> _setupDynamicSteps() async {
    final project = context.read<ProjectProvider>().currentProject!;
    
    final groqKey = await ApiConfig.getGroqKey();
    final openAiKey = await ApiConfig.getOpenAiKey();
    final hasWhisperTiming = (groqKey != null && groqKey.isNotEmpty) || (openAiKey != null && openAiKey.isNotEmpty);
    
    final isBilingual = project.translateMode == TranslateMode.bilingual;
    final isTranslating = project.sourceLanguage != project.language && project.translateMode != TranslateMode.none;
    
    final String transcribeLang = (isBilingual || (isTranslating && _actualEngine != 'gemini'))
        ? (project.sourceLanguage.isEmpty ? 'th' : project.sourceLanguage)
        : project.language;
        
    final didTranscribeInSource = transcribeLang == project.sourceLanguage;
    final willTranslate = isTranslating && didTranscribeInSource;

    final langLabel = transcribeLang == 'lo' 
        ? 'ພາສາລາວ' 
        : (transcribeLang == 'th' ? 'ພາສາໄທ' : 'English');

    final targetLabel = project.language == 'lo'
        ? 'ພາສາລາວ'
        : (project.language == 'th' ? 'ພາສາໄທ' : 'English');
    
    if (mounted) {
      setState(() {
        final List<_StepItem> steps = [
          _StepItem(Icons.audio_file_outlined, 'ດຶງສຽງຈາກວິດີໂອ'),
        ];
        
        if (_actualEngine == 'gemini') {
          steps.add(_StepItem(Icons.hearing, 'Gemini ຖອດສຽງ$langLabel'));
          if (willTranslate) {
            steps.add(_StepItem(Icons.translate, 'Gemini ແປເປັນ$targetLabel'));
          } else if (project.language == 'lo' && hasWhisperTiming) {
            steps.add(_StepItem(Icons.auto_awesome, 'Whisper ຈັບເວລາໃຫ້ຕົງ'));
          } else {
            steps.add(_StepItem(Icons.subtitles, 'ສ້າງ Subtitle'));
          }
        } else {
          final engineName = _actualEngine == 'groq' ? 'Groq (ໄວ)' : 'Whisper';
          steps.add(_StepItem(Icons.hearing, '$engineName ຖອດສຽງ$langLabel'));
          if (willTranslate) {
            steps.add(_StepItem(Icons.translate, 'Gemini ແປເປັນ$targetLabel'));
          } else {
            steps.add(_StepItem(Icons.subtitles, 'ສ້າງ Subtitle'));
          }
        }
        
        _steps = steps;
      });
    }
  }

  Future<void> _start() async {
    await _setupDynamicSteps();
    
    if (_actualEngine == 'whisper') {
      final openAiKey = await ApiConfig.getOpenAiKey();
      if (openAiKey == null || openAiKey.isEmpty) {
        setState(() {
          _hasError = true;
          _errorMessage = 'ยັງບໍ່ໄດ້ໃສ່ OpenAI API Key';
        });
        return;
      }
      _runTranscription(openAiKey);
    } else if (_actualEngine == 'groq') {
      final groqKey = await ApiConfig.getGroqKey();
      if (groqKey == null || groqKey.isEmpty) {
        setState(() {
          _hasError = true;
          _errorMessage = 'ຍັງບໍ່ໄດ້ໃສ່ Groq API Key';
        });
        return;
      }
      _runTranscription(groqKey);
    } else {
      final apiKey = await ApiConfig.getApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        setState(() {
          _hasError = true;
          _errorMessage = 'ຍັງບໍ່ໄດ້ໃສ່ Gemini API Key';
        });
        return;
      }
      _runTranscription(apiKey);
    }
  }

  Future<void> _runTranscription(String apiKey) async {
    try {
      final project = context.read<ProjectProvider>().currentProject!;
      
      setState(() {
        _currentStep = 0;
        _progress = 0.05;
        _statusText = 'ກຳລັງກຽມໄຟລ໌...';
      });

      // Determine the language to transcribe the audio in.
      // If Bilingual mode is selected, or if we translate but use Whisper/Groq, we must transcribe in the source language first.
      // If it's Gemini and "Translate" mode, we can transcribe directly in the target language to save time.
      final isBilingual = project.translateMode == TranslateMode.bilingual;
      final isTranslating = project.sourceLanguage != project.language && project.translateMode != TranslateMode.none;

      final String transcribeLang;
      if (isBilingual || (isTranslating && _actualEngine != 'gemini')) {
        transcribeLang = project.sourceLanguage.isEmpty ? 'th' : project.sourceLanguage;
      } else {
        transcribeLang = project.language;
      }

      List<SubtitleSegment> segments;

      if (_actualEngine == 'whisper') {
        final service = OpenAIWhisperService(apiKey: apiKey);
        segments = await service.transcribe(
          widget.videoPath,
          language: transcribeLang,
          wordSplit: project.wordSplit,
          onProgress: _onTranscriptionProgress,
        );
      } else if (_actualEngine == 'groq') {
        final service = GroqSpeechService(apiKey: apiKey);
        segments = await service.transcribe(
          widget.videoPath,
          language: transcribeLang,
          wordSplit: project.wordSplit,
          onProgress: _onTranscriptionProgress,
        );
      } else {
        final service = GeminiSpeechService(apiKey: apiKey);
        segments = await service.transcribe(
          widget.videoPath,
          language: transcribeLang,
          wordSplit: project.wordSplit,
          onProgress: _onTranscriptionProgress,
        );
      }

      // --- GENERAL TRANSLATION / BILINGUAL INTERCEPTION ---
      final didTranscribeInSource = transcribeLang == project.sourceLanguage;
      if (isTranslating && didTranscribeInSource && segments.isNotEmpty) {
        setState(() {
          _currentStep = 2;
          _progress = 0.85;
        });
        final geminiKey = await ApiConfig.getApiKey();
        if (geminiKey != null && geminiKey.isNotEmpty) {
          final gemini = GeminiSpeechService(apiKey: geminiKey);
          await gemini.translateSegments(
            segments: segments,
            sourceLang: project.sourceLanguage,
            targetLang: project.language,
            onProgress: (status) {
              if (!mounted) return;
              setState(() {
                _statusText = status;
              });
            },
            keepOriginalAsBilingual: isBilingual,
          );
        } else {
          throw GeminiSpeechException('ບໍ່ພົບ Gemini API Key ສຳລັບການແປພາສາ. ກະລຸນາໃສ່ໃນໜ້າຕັ້ງຄ່າ');
        }
      }

      // Auto-align the fresh subtitles to the actual speech so they come out
      // synced to the voice without the user having to adjust manually.
      if (segments.isNotEmpty) {
        setState(() {
          _currentStep = 2;
          _progress = 0.95;
          _statusText = 'ກຳລັງຈັດໃຫ້ຕົງສຽງ...';
        });
        // Ensure word-level units first (forced-align maps onto word onsets).
        try {
          await LaoWordService.ensureWordUnits(segments, locale: project.language);
        } catch (_) {}

        bool aligned = false;
        // BEST: use a real Whisper timeline (if a Groq or OpenAI key is set). Gemini gives
        // the text; Whisper gives accurate timing. Prefer re-cutting onto Whisper
        // PHRASE windows (segments) so each subtitle's start/end + DURATION match
        // the real speech (with pauses); fall back to per-word forced-align.
        final groqKey = await ApiConfig.getGroqKey();
        final openAiKey = await ApiConfig.getOpenAiKey();
        final hasGroq = groqKey != null && groqKey.isNotEmpty;
        final hasOpenAi = openAiKey != null && openAiKey.isNotEmpty;

        if (hasGroq || hasOpenAi) {
          try {
            setState(() => _statusText = 'Whisper ກຳລັງຈັບເວລາ (ໃຫ້ຕົງສຽງ)...');
            final alignLang = project.language == 'lo' ? 'th' : project.language;
            final wt = hasGroq
                ? await GroqSpeechService(
                    apiKey: groqKey,
                  ).fetchWordTimings(widget.videoPath, language: alignLang)
                : await OpenAIWhisperService(
                    apiKey: openAiKey!,
                  ).fetchWordTimings(widget.videoPath, language: alignLang);
            final maxWords = switch (project.wordSplit) {
              WordSplit.one => 1,
              WordSplit.two => 2,
              WordSplit.three => 3,
              WordSplit.four => 4,
              WordSplit.six => 6,
              WordSplit.eight => 8,
              WordSplit.none => 6,
            };
            if (wt.regions.length >= 2) {
              segments = AudioSyncService.resegmentByRegions(
                segments,
                wt.regions,
                maxWords: maxWords,
              );
              aligned = true;
            } else if (wt.startsMs.length >= 3) {
              AudioSyncService.forcedAlignToWhisper(
                segments,
                wt.startsMs,
                wt.endMs,
              );
              aligned = true;
            }
          } catch (_) {
            // best-effort — fall through to energy VAD
          }
        }

        if (!aligned) {
          try {
            // Fallback: energy-VAD region alignment (no Groq key / Whisper failed).
            final regions = await AudioSyncService.detectSpeechRegions(
              widget.videoPath,
            );
            if (regions.length >= 2) {
              AudioSyncService.alignToRegions(segments, regions);
            } else {
              await AudioSyncService.autoAlign(widget.videoPath, segments);
            }
          } catch (_) {
            // alignment is best-effort — keep Gemini timing if VAD fails
          }
        }
      }

      setState(() {
        _currentStep = 3;
        _progress = 1.0;
        _statusText = 'ສຳເລັດແລ້ວ! ✅';
      });

      context.read<ProjectProvider>().updateSegments(segments);

      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const EditorScreen()),
        );
      }
    } on GeminiSpeechException catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString();
        setState(() {
          _hasError = true;
          _errorMessage = msg.contains('TimeoutException')
              ? 'ວິດີໂອຍາວເກີນໄປ ຫຼື ເນັດຊ້າ — ກາລຸນາໃຊ້ວິດີໂອສັ້ນກວ່າ 10 ນາທີ ຫຼື ລອງໃໝ່'
              : 'ເກີດຂໍ້ຜິດພາດ: $msg';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: _hasError ? _buildErrorView() : _buildLoadingView(),
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildIcon(),
        const SizedBox(height: 40),
        _buildProgressBar(),
        const SizedBox(height: 32),
        _buildStepsList(),
      ],
    );
  }

  Widget _buildErrorView() {
    final isNoKey = _errorMessage.contains('ຍັງບໍ່ໄດ້ໃສ່');
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Icon(
            Icons.error_outline,
            color: AppColors.accent,
            size: 48,
          ),
        ).animate().fadeIn().scale(),
        const SizedBox(height: 24),
        Text(
          isNoKey
              ? (_errorMessage.contains('OpenAI')
                  ? 'ຍັງບໍ່ໄດ້ຕັ້ງ OpenAI API Key'
                  : 'ຍັງບໍ່ໄດ້ຕັ້ງ Gemini API Key')
              : 'ເກີດຂໍ້ຜິດພາດ',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _errorMessage,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        if (isNoKey)
          ElevatedButton.icon(
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            icon: const Icon(Icons.key, size: 18),
            label: Text(
              _errorMessage.contains('OpenAI')
                  ? 'ໄປຕັ້ງ OpenAI API Key'
                  : 'ໄປຕັ້ງ Gemini API Key',
            ),
          )
        else
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _hasError = false;
                _errorMessage = '';
              });
              _start();
            },
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('ລອງໃໝ່'),
          ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'ກັບໄປ',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _buildIcon() {
    return Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primaryDark, AppColors.primary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.4),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.auto_awesome, color: Colors.white, size: 48),
        )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(begin: 1.0, end: 1.05, duration: 1000.ms);
  }

  Widget _buildProgressBar() {
    return Column(
      children: [
        Text(
          _statusText,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        LinearPercentIndicator(
          lineHeight: 8,
          percent: _progress,
          backgroundColor: AppColors.surfaceLight,
          progressColor: AppColors.primary,
          barRadius: const Radius.circular(4),
          padding: EdgeInsets.zero,
          animation: true,
          animateFromLastPercent: true,
        ),
        const SizedBox(height: 8),
        Text(
          '${(_progress * 100).toInt()}%',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      ],
    );
  }

  void _onTranscriptionProgress(String status) {
    if (!mounted) return;
    setState(() {
      _statusText = status;
      if (status.contains('ດຶງສຽງ')) {
        _currentStep = 0;
        _progress = 0.25;
      } else if (status.contains('Upload') || status.contains('ສົ່ງ')) {
        _currentStep = 0;
        _progress = 0.45;
      } else if (status.contains('ຖອດສຽງ') || status.contains('Whisper') || status.contains('Groq')) {
        _currentStep = 1;
        _progress = 0.75;
      } else if (status.contains('ສ້າງ')) {
        _currentStep = 2;
        _progress = 0.90;
      }
    });
  }

  Widget _buildStepItem(int index, _StepItem step, bool isActive, bool isDone) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDone
              ? AppColors.success.withValues(alpha: 0.4)
              : isActive
              ? AppColors.primary.withValues(alpha: 0.4)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isDone ? Icons.check_circle : step.icon,
            color: isDone
                ? AppColors.success
                : isActive
                ? AppColors.primary
                : AppColors.textHint,
            size: 22,
          ),
          const SizedBox(width: 12),
          Text(
            step.label,
            style: TextStyle(
              color: isDone || isActive
                  ? AppColors.textPrimary
                  : AppColors.textHint,
              fontWeight: isActive
                  ? FontWeight.w600
                  : FontWeight.normal,
            ),
          ),
          const Spacer(),
          if (isActive)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStepsList() {
    return Column(
      children: _steps.asMap().entries.map((entry) {
        final index = entry.key;
        final step = entry.value;
        final isDone = _currentStep > index;
        final isActive = _currentStep == index;

        return _buildStepItem(index, step, isActive, isDone)
            .animate(delay: Duration(milliseconds: index * 80))
            .fadeIn()
            .slideX(begin: 0.1, end: 0);
      }).toList(),
    );
  }
}

class _StepItem {
  final IconData icon;
  final String label;
  _StepItem(this.icon, this.label);
}
