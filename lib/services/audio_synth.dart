import 'dart:math';
import 'dart:typed_data';

class AudioSynth {
  /// Generates a pop sound effect: short pitch sweep (150Hz to 800Hz) with fast decay.
  /// Outputs raw PCM 16-bit signed Mono samples.
  static Uint8List generatePop(int sampleRate) {
    const duration = 0.06; // 60ms
    final numSamples = (duration * sampleRate).toInt();
    final bytes = Uint8List(numSamples * 2);
    final data = ByteData.view(bytes.buffer);
    
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      // Frequency sweep starts at 150Hz and sweeps up linearly to 800Hz
      final freq = 150.0 + 650.0 * (t / duration);
      final phase = 2 * pi * freq * t;
      // Fast exponential envelope decay
      final env = exp(-t * 60.0);
      final val = (sin(phase) * env * 24000.0).toInt();
      data.setInt16(i * 2, val.clamp(-32768, 32767), Endian.little);
    }
    return bytes;
  }

  /// Generates a ding sound effect: high metallic chime tone (1200Hz fundamental + harmonics) with slow decay.
  /// Outputs raw PCM 16-bit signed Mono samples.
  static Uint8List generateDing(int sampleRate) {
    const duration = 0.35; // 350ms
    final numSamples = (duration * sampleRate).toInt();
    final bytes = Uint8List(numSamples * 2);
    final data = ByteData.view(bytes.buffer);
    
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      // Fundamental 1200Hz
      final phase1 = 2 * pi * 1200.0 * t;
      // Harmonious chime overtones (e.g. 2400Hz and 3600Hz)
      final phase2 = 2 * pi * 2400.0 * t;
      final phase3 = 2 * pi * 3600.0 * t;
      
      final wave = sin(phase1) * 0.75 + sin(phase2) * 0.18 + sin(phase3) * 0.07;
      // Slow envelope decay
      final env = exp(-t * 9.0);
      final val = (wave * env * 20000.0).toInt();
      data.setInt16(i * 2, val.clamp(-32768, 32767), Endian.little);
    }
    return bytes;
  }
  static Uint8List generateSwoosh(int sampleRate) {
    const duration = 0.4;
    final numSamples = (duration * sampleRate).toInt();
    final bytes = Uint8List(numSamples * 2);
    final data = ByteData.view(bytes.buffer);
    final random = Random(42);
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final noise = (random.nextDouble() * 2 - 1);
      final env = sin(pi * (t / duration)); // smooth fade in/out
      final val = (noise * env * 12000.0).toInt();
      data.setInt16(i * 2, val.clamp(-32768, 32767), Endian.little);
    }
    return bytes;
  }

  static Uint8List generateChime(int sampleRate) {
    const duration = 0.5;
    final numSamples = (duration * sampleRate).toInt();
    final bytes = Uint8List(numSamples * 2);
    final data = ByteData.view(bytes.buffer);
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final phase1 = 2 * pi * 2000.0 * t;
      final phase2 = 2 * pi * 4000.0 * t;
      final wave = sin(phase1) * 0.6 + sin(phase2) * 0.4;
      final env = exp(-t * 6.0);
      final val = (wave * env * 18000.0).toInt();
      data.setInt16(i * 2, val.clamp(-32768, 32767), Endian.little);
    }
    return bytes;
  }

  static Uint8List generateDrum(int sampleRate) {
    const duration = 0.25;
    final numSamples = (duration * sampleRate).toInt();
    final bytes = Uint8List(numSamples * 2);
    final data = ByteData.view(bytes.buffer);
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final freq = 120.0 * exp(-t * 20.0); // rapid pitch drop
      final phase = 2 * pi * freq * t;
      final env = exp(-t * 15.0);
      final val = (sin(phase) * env * 28000.0).toInt();
      data.setInt16(i * 2, val.clamp(-32768, 32767), Endian.little);
    }
    return bytes;
  }

  static Uint8List generateBeep(int sampleRate) {
    const duration = 0.2;
    final numSamples = (duration * sampleRate).toInt();
    final bytes = Uint8List(numSamples * 2);
    final data = ByteData.view(bytes.buffer);
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final phase = 2 * pi * 1000.0 * t;
      final wave = sin(phase) > 0 ? 1.0 : -1.0; // square wave
      final env = t < 0.02 ? t / 0.02 : (t > duration - 0.02 ? (duration - t) / 0.02 : 1.0);
      final val = (wave * env * 12000.0).toInt();
      data.setInt16(i * 2, val.clamp(-32768, 32767), Endian.little);
    }
    return bytes;
  }
  static Uint8List generateBubble(int sampleRate) {
    const duration = 0.15;
    final numSamples = (duration * sampleRate).toInt();
    final bytes = Uint8List(numSamples * 2);
    final data = ByteData.view(bytes.buffer);
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final freq = 400.0 + 600.0 * sin(t * pi / duration);
      final phase = 2 * pi * freq * t;
      final env = sin(pi * (t / duration)); 
      final val = (sin(phase) * env * 18000.0).toInt();
      data.setInt16(i * 2, val.clamp(-32768, 32767), Endian.little);
    }
    return bytes;
  }

  static Uint8List generateClick(int sampleRate) {
    const duration = 0.02;
    final numSamples = (duration * sampleRate).toInt();
    final bytes = Uint8List(numSamples * 2);
    final data = ByteData.view(bytes.buffer);
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final wave = sin(2 * pi * 3000.0 * t);
      final env = exp(-t * 200.0);
      final val = (wave * env * 15000.0).toInt();
      data.setInt16(i * 2, val.clamp(-32768, 32767), Endian.little);
    }
    return bytes;
  }

  static Uint8List generateWhoosh(int sampleRate) {
    const duration = 0.6;
    final numSamples = (duration * sampleRate).toInt();
    final bytes = Uint8List(numSamples * 2);
    final data = ByteData.view(bytes.buffer);
    final random = Random(123);
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final noise = (random.nextDouble() * 2 - 1);
      final env = pow(sin(pi * (t / duration)), 2); 
      final val = (noise * env * 9000.0).toInt();
      data.setInt16(i * 2, val.clamp(-32768, 32767), Endian.little);
    }
    return bytes;
  }

  static Uint8List generateTada(int sampleRate) {
    const duration = 1.0;
    final numSamples = (duration * sampleRate).toInt();
    final bytes = Uint8List(numSamples * 2);
    final data = ByteData.view(bytes.buffer);
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final chord = sin(2 * pi * 523.25 * t) + sin(2 * pi * 659.25 * t) + sin(2 * pi * 783.99 * t);
      final env = t < 0.1 ? t / 0.1 : exp(-(t - 0.1) * 3.0);
      final val = ((chord / 3.0) * env * 22000.0).toInt();
      data.setInt16(i * 2, val.clamp(-32768, 32767), Endian.little);
    }
    return bytes;
  }

  static Uint8List generateBounce(int sampleRate) {
    const duration = 0.3;
    final numSamples = (duration * sampleRate).toInt();
    final bytes = Uint8List(numSamples * 2);
    final data = ByteData.view(bytes.buffer);
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final freq = 200.0 + 800.0 * (1.0 - exp(-t * 15.0));
      final phase = 2 * pi * freq * t;
      final env = sin(pi * (t / duration));
      final val = (sin(phase) * env * 20000.0).toInt();
      data.setInt16(i * 2, val.clamp(-32768, 32767), Endian.little);
    }
    return bytes;
  }

  static Uint8List generateGlitch(int sampleRate) {
    const duration = 0.25;
    final numSamples = (duration * sampleRate).toInt();
    final bytes = Uint8List(numSamples * 2);
    final data = ByteData.view(bytes.buffer);
    final random = Random(999);
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final freq = 100.0 + 3000.0 * random.nextDouble();
      final wave = sin(2 * pi * freq * t) > 0 ? 1.0 : -1.0;
      final env = exp(-t * 4.0);
      final val = (wave * env * 10000.0).toInt();
      data.setInt16(i * 2, val.clamp(-32768, 32767), Endian.little);
    }
    return bytes;
  }

  /// ❤️ Heart — soft ascending twin-bell pulse (romantic/love)
  static Uint8List generateHeart(int sampleRate) {
    const duration = 0.5;
    final numSamples = (duration * sampleRate).toInt();
    final bytes = Uint8List(numSamples * 2);
    final data = ByteData.view(bytes.buffer);
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      // Two soft sine pulses (heartbeat rhythm)
      final pulse1 = exp(-pow(t - 0.08, 2) * 600) * sin(2 * pi * 280 * t);
      final pulse2 = exp(-pow(t - 0.22, 2) * 600) * sin(2 * pi * 320 * t);
      final val = ((pulse1 + pulse2 * 0.7) * 22000).toInt();
      data.setInt16(i * 2, val.clamp(-32768, 32767), Endian.little);
    }
    return bytes;
  }

  /// 🔥 Fire — rapid stochastic crackle burst (intense/hot)
  static Uint8List generateFire(int sampleRate) {
    const duration = 0.35;
    final numSamples = (duration * sampleRate).toInt();
    final bytes = Uint8List(numSamples * 2);
    final data = ByteData.view(bytes.buffer);
    final rng = Random(7);
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final noise = rng.nextDouble() * 2 - 1;
      // Rapid attack, medium decay with subtle crackle pops
      final env = exp(-t * 10) * (1 + 0.4 * sin(2 * pi * 55 * t));
      final val = (noise * env * 20000).toInt();
      data.setInt16(i * 2, val.clamp(-32768, 32767), Endian.little);
    }
    return bytes;
  }

  /// 🌬️ Wind — soft band-pass noise sweep (breeze)
  static Uint8List generateWind(int sampleRate) {
    const duration = 0.7;
    final numSamples = (duration * sampleRate).toInt();
    final bytes = Uint8List(numSamples * 2);
    final data = ByteData.view(bytes.buffer);
    final rng = Random(13);
    double lp = 0;
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final raw = rng.nextDouble() * 2 - 1;
      lp = lp * 0.92 + raw * 0.08; // low-pass to get "whooshy" texture
      final env = sin(pi * t / duration); // fade in & out
      final val = (lp * env * 14000).toInt();
      data.setInt16(i * 2, val.clamp(-32768, 32767), Endian.little);
    }
    return bytes;
  }

  /// 😂 Laugh — bouncy staccato pitched blips (giggle)
  static Uint8List generateLaugh(int sampleRate) {
    const duration = 0.55;
    final numSamples = (duration * sampleRate).toInt();
    final bytes = Uint8List(numSamples * 2);
    final data = ByteData.view(bytes.buffer);
    // 5 quick "ha" puffs
    const puffs = 5;
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      double val = 0;
      for (int p = 0; p < puffs; p++) {
        final centre = 0.06 + p * 0.095;
        final env = exp(-pow(t - centre, 2) * 900);
        val += env * sin(2 * pi * (420 + p * 40) * t) * 18000;
      }
      data.setInt16(i * 2, val.toInt().clamp(-32768, 32767), Endian.little);
    }
    return bytes;
  }

  /// 😢 Sad — descending minor glide (melancholic)
  static Uint8List generateSad(int sampleRate) {
    const duration = 0.6;
    final numSamples = (duration * sampleRate).toInt();
    final bytes = Uint8List(numSamples * 2);
    final data = ByteData.view(bytes.buffer);
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      // Frequency glides down from 500 Hz to 200 Hz
      final freq = 500 - 300 * (t / duration);
      final env = exp(-t * 5) * (1 - t / duration * 0.3);
      final val = (sin(2 * pi * freq * t) * env * 18000).toInt();
      data.setInt16(i * 2, val.clamp(-32768, 32767), Endian.little);
    }
    return bytes;
  }

  /// 🪄 Magic — shimmering sparkle with harmonics (wand / spell)
  static Uint8List generateMagic(int sampleRate) {
    const duration = 0.55;
    final numSamples = (duration * sampleRate).toInt();
    final bytes = Uint8List(numSamples * 2);
    final data = ByteData.view(bytes.buffer);
    final rng = Random(3);
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      // Base shimmer: rising glide
      final freq = 800 + 1200 * (t / duration);
      double wave = sin(2 * pi * freq * t) * 0.5;
      // Sparkle: random high-frequency ticks
      if (rng.nextDouble() < 0.04) wave += (rng.nextDouble() * 2 - 1) * 0.5;
      final env = exp(-t * 4) + exp(-t * 12) * 0.3;
      final val = (wave * env * 18000).toInt();
      data.setInt16(i * 2, val.clamp(-32768, 32767), Endian.little);
    }
    return bytes;
  }

  /// 💪 Power — deep thud + harmonic punch (impact/strength)
  static Uint8List generatePower(int sampleRate) {
    const duration = 0.3;
    final numSamples = (duration * sampleRate).toInt();
    final bytes = Uint8List(numSamples * 2);
    final data = ByteData.view(bytes.buffer);
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      // Low sub thud
      final sub = sin(2 * pi * 60 * t) * exp(-t * 25);
      // Mid punch
      final punch = sin(2 * pi * 180 * t) * exp(-t * 40);
      // High transient click
      final click = sin(2 * pi * 1200 * t) * exp(-t * 120);
      final val = ((sub * 0.6 + punch * 0.3 + click * 0.1) * 28000).toInt();
      data.setInt16(i * 2, val.clamp(-32768, 32767), Endian.little);
    }
    return bytes;
  }

  /// 😮 Surprise — rising gasp then sparkle reveal
  static Uint8List generateSurprise(int sampleRate) {
    const duration = 0.45;
    final numSamples = (duration * sampleRate).toInt();
    final bytes = Uint8List(numSamples * 2);
    final data = ByteData.view(bytes.buffer);
    final rng = Random(21);
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      // Fast rising sine (gasp)
      final freq = 200 + 1000 * (t / 0.15).clamp(0.0, 1.0);
      final gasp = sin(2 * pi * freq * t) * exp(-t * 8) * 0.7;
      // Sparkle tail after 0.15s
      final sparkle = t > 0.15
          ? (rng.nextDouble() * 2 - 1) * exp(-(t - 0.15) * 15) * 0.3
          : 0.0;
      final val = ((gasp + sparkle) * 22000).toInt();
      data.setInt16(i * 2, val.clamp(-32768, 32767), Endian.little);
    }
    return bytes;
  }
}
