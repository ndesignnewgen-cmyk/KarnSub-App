import 'package:flutter/services.dart';
import '../models/subtitle_style_model.dart';

/// Builds .srt / .vtt subtitle files from the project segments and saves them to
/// Download/SubtitleAI (via the native MediaStore channel) so creators can
/// import them into CapCut / YouTube / Premiere etc.
class SubtitleExportService {
  static const _channel = MethodChannel('com.anniekaydee.subtitle_app/audio');

  /// SRT timestamp: HH:MM:SS,mmm
  static String _srtTime(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final ms = d.inMilliseconds.remainder(1000).toString().padLeft(3, '0');
    return '$h:$m:$s,$ms';
  }

  /// VTT timestamp: HH:MM:SS.mmm
  static String _vttTime(Duration d) => _srtTime(d).replaceFirst(',', '.');

  static List<SubtitleSegment> _sorted(List<SubtitleSegment> segs) {
    final out = List<SubtitleSegment>.from(segs)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    return out.where((s) => s.text.trim().isNotEmpty).toList();
  }

  static String buildSrt(List<SubtitleSegment> segments, {bool bilingual = false}) {
    final segs = _sorted(segments);
    final b = StringBuffer();
    for (int i = 0; i < segs.length; i++) {
      final s = segs[i];
      var end = s.endTime;
      if (end <= s.startTime) end = s.startTime + const Duration(seconds: 2);
      b.writeln('${i + 1}');
      b.writeln('${_srtTime(s.startTime)} --> ${_srtTime(end)}');
      b.writeln(s.text.trim());
      if (bilingual && (s.translatedText?.trim().isNotEmpty ?? false)) {
        b.writeln(s.translatedText!.trim());
      }
      b.writeln(); // blank line between entries
    }
    return b.toString();
  }

  static String buildVtt(List<SubtitleSegment> segments, {bool bilingual = false}) {
    final segs = _sorted(segments);
    final b = StringBuffer();
    b.writeln('WEBVTT');
    b.writeln();
    for (int i = 0; i < segs.length; i++) {
      final s = segs[i];
      var end = s.endTime;
      if (end <= s.startTime) end = s.startTime + const Duration(seconds: 2);
      b.writeln('${_vttTime(s.startTime)} --> ${_vttTime(end)}');
      b.writeln(s.text.trim());
      if (bilingual && (s.translatedText?.trim().isNotEmpty ?? false)) {
        b.writeln(s.translatedText!.trim());
      }
      b.writeln();
    }
    return b.toString();
  }

  /// Saves [content] as [fileName] to Download/SubtitleAI. Returns the saved
  /// relative path (e.g. "Download/SubtitleAI/foo.srt"). Throws on failure.
  static Future<String> save(String content, String fileName, {required bool isVtt}) async {
    final mime = isVtt ? 'text/vtt' : 'application/x-subrip';
    final path = await _channel.invokeMethod<String>('saveTextFile', {
      'content': content,
      'fileName': fileName,
      'mime': mime,
    });
    return path ?? 'Download/SubtitleAI/$fileName';
  }

  /// Convenience: build + save in one call.
  static Future<String> export({
    required List<SubtitleSegment> segments,
    required String baseName,
    required bool vtt,
    bool bilingual = false,
  }) async {
    // Keep word chars + Thai/Lao letters (U+0E00–U+0EFF); collapse the rest to _.
    var safe = baseName.replaceAll(RegExp('[^\\w\\u0E00-\\u0EFF]+'), '_');
    if (safe.replaceAll('_', '').isEmpty) safe = 'subtitle';
    final fileName = '$safe.${vtt ? 'vtt' : 'srt'}';
    final content =
        vtt ? buildVtt(segments, bilingual: bilingual) : buildSrt(segments, bilingual: bilingual);
    return save(content, fileName, isVtt: vtt);
  }
}
