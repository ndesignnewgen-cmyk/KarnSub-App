import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A sound effect found on the web.
class WebSfx {
  final String id;
  final String title; // human description
  final int durationMs;
  final String wavUrl; // direct WAV (BBC). "" for sources without direct WAV.
  final String mp3Url; // smaller, used for preview streaming + (Freesound) download
  final bool needsDecode; // true → downloaded file is mp3, decode to WAV before use
  WebSfx({
    required this.id,
    required this.title,
    required this.durationMs,
    required this.wavUrl,
    required this.mp3Url,
    this.needsDecode = false,
  });
}

/// Searches the BBC Sound Effects archive (33,000+ pro sounds).
/// Keyless public API; downloads are direct WAV so they drop straight into the
/// existing custom-SFX pipeline (preview + export both expect WAV).
///
/// Note: BBC archive sounds are provided under the RemArc licence
/// (personal / educational / research use).
class SfxSearchService {
  static const _searchEndpoint =
      'https://sound-effects-api.bbcrewind.co.uk/api/sfx/search';
  static const _mediaBase = 'https://sound-effects-media.bbcrewind.co.uk';

  static String wavUrlFor(String id) => '$_mediaBase/wav/$id.wav';
  static String mp3UrlFor(String id) => '$_mediaBase/mp3/$id.mp3';

  /// Search [query] (English works best). Returns up to [limit] results.
  static Future<List<WebSfx>> search(String query, {int limit = 24}) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    try {
      final res = await http
          .post(
            Uri.parse(_searchEndpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'criteria': {'query': q, 'from': 0, 'size': limit},
            }),
          )
          .timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final results = (data['results'] as List<dynamic>? ?? []);
      final out = <WebSfx>[];
      for (final r in results) {
        final m = r as Map<String, dynamic>;
        final id = (m['id'] ?? '').toString();
        if (id.isEmpty) continue;
        final desc = (m['description'] ?? '').toString().trim();
        final durMs = _toInt(m['duration']);
        out.add(WebSfx(
          id: id,
          title: desc.isEmpty ? id : desc,
          durationMs: durMs,
          wavUrl: wavUrlFor(id),
          mp3Url: mp3UrlFor(id),
        ));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// Download [sfx] into support/sfx_web and return the local path.
  /// BBC → WAV directly. Freesound → mp3 (caller decodes to WAV before export).
  static Future<String?> download(WebSfx sfx) async {
    final url = sfx.needsDecode ? sfx.mp3Url : sfx.wavUrl;
    if (url.isEmpty) return null;
    try {
      final res = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'KarnSub/1.1 (subtitle app)',
      }).timeout(const Duration(seconds: 40));
      if (res.statusCode != 200 || res.bodyBytes.length < 64) return null;
      final supportDir = await getApplicationSupportDirectory();
      final dir = Directory(p.join(supportDir.path, 'sfx_web'));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final ext = sfx.needsDecode ? 'mp3' : 'wav';
      final dest = p.join(dir.path, 'sfx_${sfx.id}.$ext');
      await File(dest).writeAsBytes(res.bodyBytes, flush: true);
      return dest;
    } catch (_) {
      return null;
    }
  }

  /// Freesound search — huge CC library incl. meme/UI sounds. Needs a free
  /// [token]. Filtered to CC0 (no attribution required, commercial OK).
  /// Previews are mp3 → [WebSfx.needsDecode] = true.
  static Future<List<WebSfx>> searchFreesound(String query, String token,
      {int limit = 24}) async {
    final q = query.trim();
    if (q.isEmpty || token.trim().isEmpty) return [];
    final uri = Uri.parse('https://freesound.org/apiv2/search/text/').replace(
      queryParameters: {
        'query': q,
        'token': token.trim(),
        'filter': 'license:"Creative Commons 0"',
        'fields': 'id,name,duration,previews',
        'page_size': '${limit.clamp(1, 150)}',
        'sort': 'score',
      },
    );
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final results = (data['results'] as List<dynamic>? ?? []);
      final out = <WebSfx>[];
      for (final r in results) {
        final m = r as Map<String, dynamic>;
        final id = (m['id'] ?? '').toString();
        final prev = m['previews'] as Map<String, dynamic>?;
        final mp3 = (prev?['preview-hq-mp3'] ?? prev?['preview-lq-mp3'] ?? '')
            .toString();
        if (id.isEmpty || mp3.isEmpty) continue;
        final durSec = (m['duration'] as num?)?.toDouble() ?? 0;
        out.add(WebSfx(
          id: 'fs_$id',
          title: (m['name'] ?? id).toString(),
          durationMs: (durSec * 1000).round(),
          wavUrl: '',
          mp3Url: mp3,
          needsDecode: true,
        ));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is String) return double.tryParse(v)?.round() ?? 0;
    return 0;
  }
}
