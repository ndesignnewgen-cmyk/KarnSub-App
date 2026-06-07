import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class WebImage {
  final String thumb; // small preview URL
  final String full; // full-size URL
  final String title;
  WebImage({required this.thumb, required this.full, required this.title});
}

class WebVideo {
  final String thumb; // preview image URL
  final String url; // direct .mp4 URL
  final String title;
  WebVideo({required this.thumb, required this.url, required this.title});
}

/// Searches the open web for freely-licensed images via the Openverse API
/// (no API key required). Used by the "ຄົ້ນຮູບ web" / auto B-roll feature.
class ImageSearchService {
  // Anonymous access (rate-limited) — fine for in-app, occasional searches.
  static const _endpoint = 'https://api.openverse.org/v1/images/';

  // Pixabay key (royalty-free, no attribution). Images-only — audio API is locked.
  static const _pixabayKey = '56187304-d1f94a26a598e4b26e0bb30ba';

  /// Search [query] (English works best). Tries Pixabay (best quality + license)
  /// first, then Openverse, then Wikimedia Commons (different hosts — survives if
  /// one is blocked/slow).
  static Future<List<WebImage>> search(String query, {int limit = 24}) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final px = await _searchPixabay(q, limit);
    if (px.isNotEmpty) return px;
    final ov = await _searchOpenverse(q, limit);
    if (ov.isNotEmpty) return ov;
    return _searchWikimedia(q, limit);
  }

  /// Pixabay image search — royalty-free, commercial OK, no attribution needed.
  static Future<List<WebImage>> _searchPixabay(String q, int limit) async {
    final uri = Uri.parse('https://pixabay.com/api/').replace(queryParameters: {
      'key': _pixabayKey,
      'q': q,
      'image_type': 'photo',
      'per_page': '${limit.clamp(3, 200)}',
      'safesearch': 'true',
    });
    try {
      final res = await http.get(uri, headers: {
        'User-Agent': 'KarnSub/1.1 (subtitle app)',
      }).timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final hits = (data['hits'] as List<dynamic>? ?? []);
      final out = <WebImage>[];
      for (final h in hits) {
        final m = h as Map<String, dynamic>;
        final full = (m['largeImageURL'] ?? m['webformatURL'] ?? '').toString();
        final thumb = (m['webformatURL'] ?? m['previewURL'] ?? full).toString();
        if (full.isEmpty) continue;
        out.add(WebImage(thumb: thumb, full: full, title: (m['tags'] ?? '').toString()));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  static Future<List<WebImage>> _searchOpenverse(String q, int limit) async {
    final uri = Uri.parse(_endpoint).replace(queryParameters: {
      'q': q,
      'page_size': '$limit',
      'mature': 'false',
      'license_type': 'commercial',
    });
    try {
      final res = await http.get(uri, headers: {
        'Accept': 'application/json',
        'User-Agent': 'KarnSub/1.1 (subtitle app)',
      }).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final results = (data['results'] as List<dynamic>? ?? []);
      final out = <WebImage>[];
      for (final r in results) {
        final m = r as Map<String, dynamic>;
        final full = (m['url'] ?? '').toString();
        final thumb = (m['thumbnail'] ?? full).toString();
        if (full.isEmpty) continue;
        out.add(WebImage(thumb: thumb, full: full, title: (m['title'] ?? '').toString()));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// Wikimedia Commons image search (no key, widely reachable).
  static Future<List<WebImage>> _searchWikimedia(String q, int limit) async {
    final uri = Uri.parse('https://commons.wikimedia.org/w/api.php').replace(
      queryParameters: {
        'action': 'query',
        'generator': 'search',
        'gsrsearch': q,
        'gsrnamespace': '6', // File namespace
        'gsrlimit': '$limit',
        'prop': 'imageinfo',
        'iiprop': 'url|mime',
        'iiurlwidth': '320',
        'format': 'json',
        'origin': '*',
      },
    );
    try {
      final res = await http.get(uri, headers: {
        'User-Agent': 'KarnSub/1.1 (subtitle app)',
      }).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final pages = (data['query']?['pages'] as Map<String, dynamic>?) ?? {};
      final out = <WebImage>[];
      for (final p in pages.values) {
        final iiList = p['imageinfo'] as List<dynamic>?;
        if (iiList == null || iiList.isEmpty) continue;
        final ii = iiList.first as Map<String, dynamic>;
        final mime = (ii['mime'] ?? '').toString();
        if (!mime.startsWith('image/')) continue; // skip svg/pdf/ogg/etc.
        final full = (ii['url'] ?? '').toString();
        final thumb = (ii['thumburl'] ?? full).toString();
        if (full.isEmpty) continue;
        out.add(WebImage(thumb: thumb, full: full, title: (p['title'] ?? '').toString()));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  // Tenor v1 legacy public demo key — lets meme search work with NO setup.
  static const _tenorV1Key = 'LIVDSRZULELA';

  /// Meme GIF search. Uses the user's own Tenor v2 key if set (better quota),
  /// otherwise falls back to the keyless legacy v1 endpoint so it works for
  /// everyone out of the box.
  static Future<List<WebImage>> searchMeme(String query,
      {String? userKey, int limit = 24}) async {
    if (userKey != null && userKey.trim().isNotEmpty) {
      final r = await searchTenor(query, userKey, limit: limit);
      if (r.isNotEmpty) return r;
    }
    return _searchTenorV1(query, limit);
  }

  /// Keyless Tenor v1 (legacy) search.
  static Future<List<WebImage>> _searchTenorV1(String query, int limit) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final uri = Uri.parse('https://g.tenor.com/v1/search').replace(
      queryParameters: {
        'q': q,
        'key': _tenorV1Key,
        'limit': '$limit',
        'media_filter': 'minimal',
        'contentfilter': 'medium',
      },
    );
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final results = (data['results'] as List<dynamic>? ?? []);
      final out = <WebImage>[];
      for (final r in results) {
        final media = (r as Map<String, dynamic>)['media'] as List<dynamic>?;
        if (media == null || media.isEmpty) continue;
        final fmt = media.first as Map<String, dynamic>;
        final gif = (fmt['gif']?['url'] ?? '').toString();
        final tiny = (fmt['tinygif']?['url'] ?? gif).toString();
        if (gif.isEmpty) continue;
        out.add(WebImage(
            thumb: tiny, full: gif, title: (r['content_description'] ?? '').toString()));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// Search Tenor v2 (needs the user's own free key — higher quota).
  /// Returns thumb = tinygif, full = gif.
  static Future<List<WebImage>> searchTenor(String query, String key,
      {int limit = 24}) async {
    final q = query.trim();
    if (q.isEmpty || key.trim().isEmpty) return [];
    final uri = Uri.parse('https://tenor.googleapis.com/v2/search').replace(
      queryParameters: {
        'q': q,
        'key': key.trim(),
        'limit': '$limit',
        'media_filter': 'gif,tinygif',
        'contentfilter': 'medium',
        'client_key': 'karnsub',
      },
    );
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final results = (data['results'] as List<dynamic>? ?? []);
      final out = <WebImage>[];
      for (final r in results) {
        final mf = (r as Map<String, dynamic>)['media_formats']
            as Map<String, dynamic>?;
        if (mf == null) continue;
        final gif = (mf['gif']?['url'] ?? '').toString();
        final tiny = (mf['tinygif']?['url'] ?? gif).toString();
        if (gif.isEmpty) continue;
        out.add(WebImage(thumb: tiny, full: gif, title: (r['content_description'] ?? '').toString()));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// Download [url] into support/overlays and return the local file path.
  /// Tries [url] first, then [fallbackUrl] (e.g. the thumbnail) if it fails.
  static Future<String?> download(String url, {String? fallbackUrl}) async {
    for (final u in [url, if (fallbackUrl != null && fallbackUrl != url) fallbackUrl]) {
      try {
        final res = await http.get(Uri.parse(u), headers: {
          'User-Agent': 'KarnSub/1.1 (subtitle app)',
        }).timeout(const Duration(seconds: 30));
        if (res.statusCode != 200 || res.bodyBytes.length < 512) continue;
        final ct = (res.headers['content-type'] ?? '').toLowerCase();
        final ext = ct.contains('gif')
            ? '.gif'
            : ct.contains('png')
                ? '.png'
                : ct.contains('webp')
                    ? '.webp'
                    : '.jpg';
        final supportDir = await getApplicationSupportDirectory();
        final dir = Directory(p.join(supportDir.path, 'overlays'));
        if (!dir.existsSync()) dir.createSync(recursive: true);
        final dest = p.join(
            dir.path, 'web_${DateTime.now().millisecondsSinceEpoch}$ext');
        await File(dest).writeAsBytes(res.bodyBytes, flush: true);
        return dest;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  /// Pixabay VIDEO search — royalty-free clips for auto B-roll. Returns direct
  /// downloadable .mp4 URLs (prefers the lighter "small"/"tiny" renditions).
  static Future<List<String>> searchVideo(String query, {int limit = 5}) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final uri =
        Uri.parse('https://pixabay.com/api/videos/').replace(queryParameters: {
      'key': _pixabayKey,
      'q': q,
      'per_page': '${limit.clamp(3, 200)}',
      'safesearch': 'true',
    });
    try {
      final res = await http.get(uri, headers: {
        'User-Agent': 'KarnSub/1.1 (subtitle app)',
      }).timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final hits = (data['hits'] as List<dynamic>? ?? []);
      final out = <String>[];
      for (final h in hits) {
        final m = h as Map<String, dynamic>;
        final vids = m['videos'] as Map<String, dynamic>?;
        if (vids == null) continue;
        // Lighter renditions first — plenty for an in-frame B-roll overlay.
        for (final size in ['small', 'tiny', 'medium', 'large']) {
          final v = vids[size] as Map<String, dynamic>?;
          final url = (v?['url'] ?? '').toString();
          if (url.isNotEmpty) {
            out.add(url);
            break;
          }
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// Pixabay VIDEO search with thumbnails — for the manual "search B-roll from
  /// web" grid. Returns clips with a preview image + direct .mp4 URL.
  static Future<List<WebVideo>> searchVideoDetailed(String query,
      {int limit = 24}) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final uri =
        Uri.parse('https://pixabay.com/api/videos/').replace(queryParameters: {
      'key': _pixabayKey,
      'q': q,
      'per_page': '${limit.clamp(3, 200)}',
      'safesearch': 'true',
    });
    try {
      final res = await http.get(uri, headers: {
        'User-Agent': 'KarnSub/1.1 (subtitle app)',
      }).timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final hits = (data['hits'] as List<dynamic>? ?? []);
      final out = <WebVideo>[];
      for (final h in hits) {
        final m = h as Map<String, dynamic>;
        final vids = m['videos'] as Map<String, dynamic>?;
        if (vids == null) continue;
        String url = '';
        String thumb = '';
        for (final size in ['small', 'tiny', 'medium', 'large']) {
          final v = vids[size] as Map<String, dynamic>?;
          if (v == null) continue;
          final u = (v['url'] ?? '').toString();
          if (u.isNotEmpty && url.isEmpty) url = u;
          final t = (v['thumbnail'] ?? '').toString();
          if (t.isNotEmpty && thumb.isEmpty) thumb = t;
        }
        if (url.isEmpty) continue;
        // Fallback thumbnail derived from Pixabay's picture id if none provided.
        if (thumb.isEmpty) {
          final pid = (m['picture_id'] ?? '').toString();
          if (pid.isNotEmpty) {
            thumb = 'https://i.vimeocdn.com/video/${pid}_295x166.jpg';
          }
        }
        out.add(WebVideo(thumb: thumb, url: url, title: (m['tags'] ?? '').toString()));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// Download a video clip into the overlays dir as .mp4. Returns the path or null.
  static Future<String?> downloadVideo(String url) async {
    try {
      final res = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'KarnSub/1.1 (subtitle app)',
      }).timeout(const Duration(seconds: 60));
      if (res.statusCode != 200 || res.bodyBytes.length < 2048) return null;
      final supportDir = await getApplicationSupportDirectory();
      final dir = Directory(p.join(supportDir.path, 'overlays'));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final dest = p.join(
          dir.path, 'broll_${DateTime.now().millisecondsSinceEpoch}.mp4');
      await File(dest).writeAsBytes(res.bodyBytes, flush: true);
      return dest;
    } catch (_) {
      return null;
    }
  }
}
