import 'package:audioplayers/audioplayers.dart';
import '../models/subtitle_style_model.dart';

class SfxPlayerService {
  static final SfxPlayerService _instance = SfxPlayerService._internal();
  factory SfxPlayerService() => _instance;
  SfxPlayerService._internal();

  final List<AudioPlayer> _pool = List.generate(4, (_) => AudioPlayer());
  final List<int> _poolPlaybackIds = List.generate(4, (_) => 0);
  int _poolIndex = 0;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    final audioContext = AudioContext(
      android: const AudioContextAndroid(
        isSpeakerphoneOn: true,
        stayAwake: false,
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.assistanceSonification,
        audioFocus: AndroidAudioFocus.none,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.ambient,
        options: const {
          AVAudioSessionOptions.mixWithOthers,
        },
      ),
    );

    await AudioPlayer.global.setAudioContext(audioContext);
    _initialized = true;
  }

  String _getAssetPath(SfxType type) {
    final name = type.name;
    final snakeCaseName = name.replaceAllMapped(RegExp(r'[A-Z]'), (m) => '_${m.group(0)!.toLowerCase()}');
    return 'sfx/$snakeCaseName.wav'; // audioplayers AssetSource prepends "assets/" by default
  }

  Future<void> playSfx(SfxType type, {double volume = 1.0, Duration? trimStart, Duration? duration, String? customPath}) async {
    if (!_initialized) await init();

    final pIdx = _poolIndex;
    final player = _pool[pIdx];
    _poolIndex = (_poolIndex + 1) % _pool.length;
    _poolPlaybackIds[pIdx]++;
    final currentPlaybackId = _poolPlaybackIds[pIdx];
    
    await player.stop();
    await player.setVolume(volume.clamp(0.0, 1.0));
    
    if (customPath != null && customPath.isNotEmpty) {
      await player.play(DeviceFileSource(customPath));
    } else {
      final path = _getAssetPath(type);
      await player.play(AssetSource(path));
    }
    
    if (trimStart != null && trimStart.inMilliseconds > 0) {
      await player.seek(trimStart);
    }
    
    if (duration != null) {
      Future.delayed(duration, () {
        if (_poolPlaybackIds[pIdx] == currentPlaybackId && player.state == PlayerState.playing) {
          player.stop();
        }
      });
    }
  }
  void pauseAll() {
    for (final player in _pool) {
      if (player.state == PlayerState.playing) {
        player.pause();
      }
    }
  }
}

