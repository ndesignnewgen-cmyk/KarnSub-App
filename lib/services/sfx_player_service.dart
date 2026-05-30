import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'audio_synth.dart';
import '../models/subtitle_style_model.dart';

class SfxPlayerService {
  static final SfxPlayerService _instance = SfxPlayerService._internal();
  factory SfxPlayerService() => _instance;
  SfxPlayerService._internal();

  final List<AudioPlayer> _pool = List.generate(4, (_) => AudioPlayer());
  int _poolIndex = 0;

  String? _popPath;
  String? _dingPath;
  String? _swooshPath;
  String? _chimePath;
  String? _drumPath;
  String? _beepPath;
  String? _bubblePath;
  String? _clickPath;
  String? _whooshPath;
  String? _tadaPath;
  String? _bouncePath;
  String? _glitchPath;
  String? _heartPath;
  String? _firePath;
  String? _windPath;
  String? _laughPath;
  String? _sadPath;
  String? _magicPath;
  String? _powerPath;
  String? _surprisePath;

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
    
    final tempDir = await getTemporaryDirectory();
    _popPath      = '${tempDir.path}/pop_sfx.wav';
    _dingPath     = '${tempDir.path}/ding_sfx.wav';
    _swooshPath   = '${tempDir.path}/swoosh_sfx.wav';
    _chimePath    = '${tempDir.path}/chime_sfx.wav';
    _drumPath     = '${tempDir.path}/drum_sfx.wav';
    _beepPath     = '${tempDir.path}/beep_sfx.wav';
    _bubblePath   = '${tempDir.path}/bubble_sfx.wav';
    _clickPath    = '${tempDir.path}/click_sfx.wav';
    _whooshPath   = '${tempDir.path}/whoosh_sfx.wav';
    _tadaPath     = '${tempDir.path}/tada_sfx.wav';
    _bouncePath   = '${tempDir.path}/bounce_sfx.wav';
    _glitchPath   = '${tempDir.path}/glitch_sfx.wav';
    _heartPath    = '${tempDir.path}/heart_sfx.wav';
    _firePath     = '${tempDir.path}/fire_sfx.wav';
    _windPath     = '${tempDir.path}/wind_sfx.wav';
    _laughPath    = '${tempDir.path}/laugh_sfx.wav';
    _sadPath      = '${tempDir.path}/sad_sfx.wav';
    _magicPath    = '${tempDir.path}/magic_sfx.wav';
    _powerPath    = '${tempDir.path}/power_sfx.wav';
    _surprisePath = '${tempDir.path}/surprise_sfx.wav';

    Future<void> saveIfMissing(String path, Uint8List Function(int) generator) async {
      final pcm = generator(24000);
      final wav = _addWavHeader(pcm, 24000, 1, 16);
      await File(path).writeAsBytes(wav);
    }

    await saveIfMissing(_popPath!, AudioSynth.generatePop);
    await saveIfMissing(_dingPath!, AudioSynth.generateDing);
    await saveIfMissing(_swooshPath!, AudioSynth.generateSwoosh);
    await saveIfMissing(_chimePath!, AudioSynth.generateChime);
    await saveIfMissing(_drumPath!, AudioSynth.generateDrum);
    await saveIfMissing(_beepPath!, AudioSynth.generateBeep);
    await saveIfMissing(_bubblePath!, AudioSynth.generateBubble);
    await saveIfMissing(_clickPath!, AudioSynth.generateClick);
    await saveIfMissing(_whooshPath!, AudioSynth.generateWhoosh);
    await saveIfMissing(_tadaPath!, AudioSynth.generateTada);
    await saveIfMissing(_bouncePath!, AudioSynth.generateBounce);
    await saveIfMissing(_glitchPath!, AudioSynth.generateGlitch);
    await saveIfMissing(_heartPath!, AudioSynth.generateHeart);
    await saveIfMissing(_firePath!, AudioSynth.generateFire);
    await saveIfMissing(_windPath!, AudioSynth.generateWind);
    await saveIfMissing(_laughPath!, AudioSynth.generateLaugh);
    await saveIfMissing(_sadPath!, AudioSynth.generateSad);
    await saveIfMissing(_magicPath!, AudioSynth.generateMagic);
    await saveIfMissing(_powerPath!, AudioSynth.generatePower);
    await saveIfMissing(_surprisePath!, AudioSynth.generateSurprise);

    _initialized = true;
  }

  String? getPathForType(SfxType type) {
    return switch (type) {
      SfxType.pop      => _popPath,
      SfxType.ding     => _dingPath,
      SfxType.swoosh   => _swooshPath,
      SfxType.chime    => _chimePath,
      SfxType.drum     => _drumPath,
      SfxType.beep     => _beepPath,
      SfxType.bubble   => _bubblePath,
      SfxType.click    => _clickPath,
      SfxType.whoosh   => _whooshPath,
      SfxType.tada     => _tadaPath,
      SfxType.bounce   => _bouncePath,
      SfxType.glitch   => _glitchPath,
      SfxType.heart    => _heartPath,
      SfxType.fire     => _firePath,
      SfxType.wind     => _windPath,
      SfxType.laugh    => _laughPath,
      SfxType.sad      => _sadPath,
      SfxType.magic    => _magicPath,
      SfxType.power    => _powerPath,
      SfxType.surprise => _surprisePath,
    };
  }

  Future<void> playSfx(SfxType type) async {
    if (!_initialized) await init();

    String? path = getPathForType(type);

    if (path != null) {
      final player = _pool[_poolIndex];
      _poolIndex = (_poolIndex + 1) % _pool.length;
      await player.stop();
      await player.play(DeviceFileSource(path));
    }
  }

  Uint8List _addWavHeader(Uint8List pcmBytes, int sampleRate, int channels, int bitsPerSample) {
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    final totalDataLen = pcmBytes.length + 36;
    
    final header = ByteData(44);
    
    // "RIFF"
    header.setUint8(0, 0x52);
    header.setUint8(1, 0x49);
    header.setUint8(2, 0x46);
    header.setUint8(3, 0x46);
    
    header.setUint32(4, totalDataLen, Endian.little);
    
    // "WAVE"
    header.setUint8(8, 0x57);
    header.setUint8(9, 0x41);
    header.setUint8(10, 0x56);
    header.setUint8(11, 0x45);
    
    // "fmt "
    header.setUint8(12, 0x66);
    header.setUint8(13, 0x6D);
    header.setUint8(14, 0x74);
    header.setUint8(15, 0x20);
    
    header.setUint32(16, 16, Endian.little); // PCM chunk size
    header.setUint16(20, 1, Endian.little); // AudioFormat (PCM = 1)
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    
    // "data"
    header.setUint8(36, 0x64);
    header.setUint8(37, 0x61);
    header.setUint8(38, 0x74);
    header.setUint8(39, 0x61);
    
    header.setUint32(40, pcmBytes.length, Endian.little);
    
    final builder = BytesBuilder();
    builder.add(header.buffer.asUint8List());
    builder.add(pcmBytes);
    return builder.toBytes();
  }
}
