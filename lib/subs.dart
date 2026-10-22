import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'core.dart';

// ---------------------------------------------------------------------------------------------
// Online subtitles (OpenSubtitles.com), like FileX: used when the movie / series file itself has
// no subtitle track in the language the customer wants (English by default).
//
// ONE-TIME SETUP by the app owner (customers never see or enter anything):
//   1. Make a free account on opensubtitles.com
//   2. Open opensubtitles.com/consumers and create an API consumer: copy its API key
//   3. Paste key, username and password below
// A customer can also type their own details in Settings > OpenSubtitles; those win over these.
// ---------------------------------------------------------------------------------------------
const osDefaultKey = 'RweP92dEaZpNmCXGG5zz9FdVsQRX9CpZ';
const osDefaultUser = 'junaidbhai';
const osDefaultPass = 'KarachiPakistan';

class Cue {
  final int a, b; // start / end in milliseconds
  final String t;
  const Cue(this.a, this.b, this.t);
}

class OnlineSubs {
  static final Map<String, List<Cue>> _cache = {};
  static String? _token;
  static String _base = 'api.opensubtitles.com';

  static String get _key => Cfg.gs('os_key').isNotEmpty ? Cfg.gs('os_key') : osDefaultKey;
  static String get _user => Cfg.gs('os_user').isNotEmpty ? Cfg.gs('os_user') : osDefaultUser;
  static String get _pass => Cfg.gs('os_pass').isNotEmpty ? Cfg.gs('os_pass') : osDefaultPass;

  static bool get ready => _key.isNotEmpty && _user.isNotEmpty && _pass.isNotEmpty;

  static Map<String, String> get _h => {
        'Api-Key': _key,
        'User-Agent': 'Streamivo v1.2',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  static Future<bool> _login() async {
    if (_token != null) return true;
    final r = await http
        .post(Uri.parse('https://api.opensubtitles.com/api/v1/login'),
            headers: _h, body: jsonEncode({'username': _user, 'password': _pass}))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) return false;
    final j = jsonDecode(r.body);
    _token = '${j['token'] ?? ''}';
    final b = '${j['base_url'] ?? ''}'.trim();
    if (b.isNotEmpty) _base = b.replaceAll(RegExp(r'^https?://'), '').replaceAll(RegExp(r'/.*$'), '');
    return _token!.isNotEmpty;
  }

  // "|EN| Movie Name (2019) [4K]"  ->  name = "Movie Name", year = "2019"
  static Map<String, String> clean(String raw) {
    var s = raw;
    final ym = RegExp(r'[\(\[]\s*((?:19|20)\d\d)\s*[\)\]]').firstMatch(s);
    var year = ym?.group(1) ?? '';
    s = s.replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)|\{[^}]*\}'), ' ');
    s = s.replaceAll(RegExp(r'^[\s|]*[A-Za-z]{2,4}\s*\|[\s|]*'), ''); // "|EN| " / "EN | "
    s = s.replaceAll(RegExp(r'\b(4k|uhd|fhd|hdr|2160p|1080p|720p|web-?dl|blu-?ray|x26[45]|hevc)\b', caseSensitive: false), ' ');
    s = s.replaceAll(RegExp(r'\b(hindi\s+dubbed|hindi\s+dub|dubbed|dual\s+audio|multi\s+audio)\b', caseSensitive: false), ' ');
    var season = '', episode = '';
    final se = RegExp(r'[sS](\d{1,2})\s*[eE](\d{1,3})').firstMatch(s);
    if (se != null) {
      season = '${int.parse(se.group(1)!)}';
      episode = '${int.parse(se.group(2)!)}';
      s = s.substring(0, se.start);
    }
    if (year.isEmpty) {
      final y2 = RegExp(r'\b((?:19|20)\d\d)\b\s*$').firstMatch(s);
      if (y2 != null) {
        year = y2.group(1)!;
        s = s.substring(0, y2.start);
      }
    }
    s = s.replaceAll(RegExp(r'[-_.:]+\s*$'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return {'name': s, 'year': year, 'season': season, 'episode': episode};
  }

  // Finds, downloads and reads one subtitle file. Returns null when nothing was found.
  static Future<List<Cue>?> fetch(String title, String lang) async {
    final c = clean(title);
    if ((c['name'] ?? '').isEmpty || !ready) return null;
    final ck = '${c['name']}|${c['season']}|${c['episode']}|$lang';
    final hit = _cache[ck];
    if (hit != null) return hit;
    try {
      if (!await _login()) return null;
      final isEp = (c['episode'] ?? '').isNotEmpty;
      // parameters in alphabetical order, all lower case (the server asks for it)
      final q = <String, String>{
        if (isEp) 'episode_number': c['episode']!,
        'languages': lang,
        'order_by': 'download_count',
        'query': c['name']!.toLowerCase(),
        if (isEp) 'season_number': c['season']!,
        'type': isEp ? 'episode' : 'movie',
        if (!isEp && (c['year'] ?? '').isNotEmpty) 'year': c['year']!,
      };
      final sr = await http
          .get(Uri.https(_base, '/api/v1/subtitles', q), headers: _h)
          .timeout(const Duration(seconds: 20));
      if (sr.statusCode != 200) return null;
      final data = jsonDecode(sr.body)['data'];
      if (data is! List || data.isEmpty) return null;
      int? fileId;
      for (final d in data) {
        final files = d['attributes']?['files'];
        if (files is List && files.isNotEmpty && files.first['file_id'] != null) {
          fileId = (files.first['file_id'] as num).toInt();
          break;
        }
      }
      if (fileId == null) return null;
      final dr = await http
          .post(Uri.https(_base, '/api/v1/download'),
              headers: {..._h, 'Authorization': 'Bearer $_token'},
              body: jsonEncode({'file_id': fileId, 'sub_format': 'srt'}))
          .timeout(const Duration(seconds: 20));
      if (dr.statusCode != 200) {
        if (dr.statusCode == 401) _token = null;
        return null;
      }
      final link = '${jsonDecode(dr.body)['link'] ?? ''}';
      if (link.isEmpty) return null;
      final fr = await http.get(Uri.parse(link)).timeout(const Duration(seconds: 25));
      if (fr.statusCode != 200) return null;
      final cues = parseSrt(utf8.decode(fr.bodyBytes, allowMalformed: true));
      if (cues.isEmpty) return null;
      _cache[ck] = cues;
      return cues;
    } catch (_) {
      return null;
    }
  }

  static int _ms(String t) {
    final m = RegExp(r'(\d+):(\d+):(\d+)[,.](\d+)').firstMatch(t);
    if (m == null) return 0;
    var f = m.group(4)!;
    f = (f + '000').substring(0, 3);
    return int.parse(m.group(1)!) * 3600000 +
        int.parse(m.group(2)!) * 60000 +
        int.parse(m.group(3)!) * 1000 +
        int.parse(f);
  }

  static List<Cue> parseSrt(String raw) {
    final out = <Cue>[];
    final txt = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').replaceFirst('﻿', '');
    for (final blk in txt.split(RegExp(r'\n\s*\n'))) {
      final lines = blk.split('\n');
      final ti = lines.indexWhere((l) => l.contains('-->'));
      if (ti < 0) continue;
      final p = lines[ti].split('-->');
      if (p.length < 2) continue;
      final body = lines
          .sublist(ti + 1)
          .join('\n')
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .replaceAll(RegExp(r'\{\\[^}]*\}'), '')
          .trim();
      if (body.isEmpty) continue;
      out.add(Cue(_ms(p[0]), _ms(p[1]), body));
    }
    out.sort((x, y) => x.a.compareTo(y.a));
    return out;
  }

  // The line that is on screen at this position (binary search)
  static String at(List<Cue> l, int ms) {
    var lo = 0, hi = l.length - 1, best = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (l[mid].a <= ms) {
        best = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    // overlapping lines are rare: look a few cues back
    for (var i = best; i >= 0 && i > best - 3; i--) {
      if (ms >= l[i].a && ms <= l[i].b) return l[i].t;
    }
    return '';
  }
}
