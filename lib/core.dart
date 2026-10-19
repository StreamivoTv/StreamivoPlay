import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

// ---- Your 3 servers (customers never see these) ----
const servers = [
  'http://filex.me.uk:8080',
  'http://hexavip4u.online:80',
  'http://fiberstream.live:88',
];

// Optional: put a free TMDB API key here to show cast photos and roles
// (get one at themoviedb.org). Leave empty to show cast names only.
const tmdbKey = '3bf6a5f0d7d9ddf8027b98ca0dd3c655';

// Many IPTV panels block Dart's default User-Agent, so look like a normal player
const defaultUa = 'VLC/3.0.20 LibVLC/3.0.20';
Map<String, String> ua = {'User-Agent': defaultUa, 'Accept': '*/*'};

const String appVersion = '1.1.0';

// Bumped whenever a display setting changes so the whole UI rebuilds
final ValueNotifier<int> uiTick = ValueNotifier<int>(0);

// Last login failure details (shown on the login screen)
String loginDiag = '';

// UI zoom on phones (1.0 = original size)
const double uiScale = 0.75;

const bg = Color(0xFF0B0B12);
const card = Color(0xFF16162A);
const accent = Color(0xFFFF6A4D);


// ---------------- Simple local storage (no plugin, never hangs) ----------------
class SharedPreferences {
  static SharedPreferences? _i;
  final Map<String, dynamic> _m = {};
  File? _f;

  static Future<SharedPreferences> getInstance() async {
    if (_i != null) return _i!;
    final s = SharedPreferences();
    try {
      final f = File('${Directory.systemTemp.path}/streamivo_prefs.json');
      s._f = f;
      if (f.existsSync()) {
        final d = jsonDecode(f.readAsStringSync());
        if (d is Map) s._m.addAll(Map<String, dynamic>.from(d));
      }
    } catch (_) {}
    _i = s;
    return s;
  }

  void _save() {
    try {
      _f?.writeAsStringSync(jsonEncode(_m), flush: true);
    } catch (_) {}
  }

  String? getString(String k) => _m[k] is String ? _m[k] as String : null;
  bool? getBool(String k) => _m[k] is bool ? _m[k] as bool : null;
  List<String>? getStringList(String k) =>
      _m[k] is List ? [for (final x in _m[k] as List) '$x'] : null;
  Future<bool> setString(String k, String v) async {
    _m[k] = v;
    _save();
    return true;
  }

  Future<bool> setBool(String k, bool v) async {
    _m[k] = v;
    _save();
    return true;
  }

  Future<bool> setStringList(String k, List<String> v) async {
    _m[k] = v;
    _save();
    return true;
  }

  Future<bool> remove(String k) async {
    _m.remove(k);
    _save();
    return true;
  }
}

// Follows redirects by hand (the video engine refuses http -> https redirects)
Future<String> resolveFinal(String url) async {
  final hc = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    var u = Uri.parse(url);
    for (var i = 0; i < 6; i++) {
      final rq = await hc.getUrl(u).timeout(const Duration(seconds: 8));
      rq.followRedirects = false;
      ua.forEach((k, v) => rq.headers.set(k, v));
      rq.headers.set('Range', 'bytes=0-0');
      final rs = await rq.close().timeout(const Duration(seconds: 10));
      final loc = rs.headers.value('location');
      if (rs.statusCode >= 300 && rs.statusCode < 400 && loc != null) {
        u = u.resolve(loc);
        continue;
      }
      return u.toString();
    }
    return u.toString();
  } catch (_) {
    return url;
  } finally {
    hc.close(force: true);
  }
}

// Hides status bar + navigation buttons; they come back only when the screen edge is swiped
void hideBars() {
  try {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  } catch (_) {}
}

// ---------------- Native bridge ----------------
const MethodChannel _ch = MethodChannel('streamivo/native');
bool isTv = false;
final ValueNotifier<bool> inPip = ValueNotifier<bool>(false);

Future<dynamic> nat(String m, [dynamic a]) async {
  try {
    return await _ch.invokeMethod(m, a);
  } catch (_) {
    return null;
  }
}

void initNative() {
  _ch.setMethodCallHandler((call) async {
    if (call.method == 'pip') inPip.value = call.arguments == true;
    return null;
  });
}

// ---------------- App settings ----------------
class Cfg {
  static bool autoLogin = true;
  static String startScreen = 'home'; // home | live
  static String playerMode = 'builtin'; // builtin | external
  static String externalApp = 'ask'; // ask | vlc | mx
  static String liveFormat = 'default'; // default | m3u8 | ts
  static String fit = 'contain'; // contain | cover | fill
  static String catchupFmt = 'ts'; // ts | m3u8
  static int epgShift = 0; // hours added to guide times

  static final Map<String, int> counts = {};

  // Generic key/value settings (used by the new settings dialogs)
  static SharedPreferences? _p;
  static String gs(String k, [String d = '']) => _p?.getString(k) ?? d;
  static bool gb(String k, bool d) => _p?.getBool(k) ?? d;
  static Future<void> ps(String k, String v) async {
    await _p?.setString(k, v);
  }

  static Future<void> pb(String k, bool v) async {
    await _p?.setBool(k, v);
  }

  static bool get h12 => gs('cfg_time', '24') == '12';
  static int get layout {
    final n = int.tryParse(gs('cfg_layout', '0')) ?? 0;
    return n < 0 || n > 5 ? 0 : n;
  }

  static Future<void> saveCount(String type, int n) async {
    if (counts[type] == n) return;
    counts[type] = n;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('cnt_$type', '$n');
    } catch (_) {}
  }

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _p = p;
    final savedUa = p.getString('cfg_ua') ?? '';
    if (savedUa.trim().isNotEmpty) ua['User-Agent'] = savedUa.trim();
    for (final t in ['live', 'movie', 'series']) {
      final v = int.tryParse(p.getString('cnt_$t') ?? '');
      if (v != null) counts[t] = v;
    }
    autoLogin = p.getBool('cfg_auto') ?? true;
    startScreen = p.getString('cfg_start') ?? 'home';
    playerMode = p.getString('cfg_player') ?? 'builtin';
    externalApp = p.getString('cfg_ext') ?? 'ask';
    liveFormat = p.getString('cfg_fmt') ?? 'default';
    fit = p.getString('cfg_fit') ?? 'contain';
    catchupFmt = p.getString('cfg_cu') ?? 'ts';
    epgShift = int.tryParse(p.getString('cfg_shift') ?? '') ?? 0;
  }

  static Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('cfg_auto', autoLogin);
    await p.setString('cfg_start', startScreen);
    await p.setString('cfg_player', playerMode);
    await p.setString('cfg_ext', externalApp);
    await p.setString('cfg_fmt', liveFormat);
    await p.setString('cfg_fit', fit);
    await p.setString('cfg_cu', catchupFmt);
    await p.setString('cfg_shift', '$epgShift');
  }
}

BoxFit fitOf(String k) => k == 'cover' ? BoxFit.cover : (k == 'fill' ? BoxFit.fill : BoxFit.contain);

// ---------------- Helpers ----------------
bool showFocus(bool f) =>
    f && (isTv || FocusManager.instance.highlightMode == FocusHighlightMode.traditional);

dynamic _decode(String s) => jsonDecode(s);

String clean(dynamic x) {
  final t = '${x ?? ''}'.trim();
  return t == 'null' ? '' : t;
}

String fmt(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = two(d.inMinutes.remainder(60)), s = two(d.inSeconds.remainder(60));
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

Future<void> disposeLater(VideoPlayerController? c) async {
  if (c == null) return;
  await WidgetsBinding.instance.endOfFrame;
  await c.dispose();
}

String b64d(String s) => _b64(s);

String _b64(String s) {
  try {
    return utf8.decode(base64.decode(s));
  } catch (_) {
    return s;
  }
}

// ---------------- Playable item (used by the player) ----------------
class Pi {
  final String title, url;
  final String? alt, id;
  const Pi(this.title, this.url, [this.alt, this.id]);
}

// ---------------- Library item (channel / movie / series) ----------------
class It {
  final String id, name, ln, icon, ext;
  final int cat, added;
  It(this.id, this.name, this.icon, this.ext, this.cat, this.added) : ln = name.toLowerCase();

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'icon': icon, 'ext': ext, 'cat': cat, 'added': added};

  factory It.fromJson(Map m) => It('${m['id']}', '${m['name']}', '${m['icon']}', '${m['ext']}',
      int.tryParse('${m['cat']}') ?? 0, int.tryParse('${m['added']}') ?? 0);

  String get line => '${_c(id)}\t${_c(icon)}\t${_c(ext)}\t$cat\t$added\t${_c(name)}\n';
}

String _c(String s) => s.replaceAll(RegExp(r'[\t\r\n]'), ' ');

It _mk(Map m, String type) {
  final series = type == 'series';
  final id = '${series ? m['series_id'] : m['stream_id']}';
  final icon = clean(series ? m['cover'] : m['stream_icon']);
  final added = int.tryParse('${(series ? m['last_modified'] : m['added']) ?? 0}') ?? 0;
  final ext = clean(m['container_extension']);
  return It(id, '${m['name'] ?? ''}', icon, ext.isEmpty ? 'mp4' : ext,
      int.tryParse('${m['category_id']}') ?? 0, added);
}

// Runs in a background isolate
List<It> parseItems(List a) {
  final d = jsonDecode(a[0] as String);
  final type = a[1] as String;
  if (d is! List) return <It>[];
  return [
    for (final m in d)
      if (m is Map) _mk(m, type)
  ];
}

// Runs in a background isolate
List<It> readCache(String path) {
  final out = <It>[];
  try {
    final f = File(path);
    if (!f.existsSync()) return out;
    for (final line in f.readAsLinesSync()) {
      final p = line.split('\t');
      if (p.length < 6) continue;
      out.add(It(p[0], p.sublist(5).join(' '), p[1], p[2], int.tryParse(p[3]) ?? 0,
          int.tryParse(p[4]) ?? 0));
    }
  } catch (_) {}
  return out;
}

// ---------------- Library index (counts, ALL, search, disk cache) ----------------
class Lib {
  final Session s;
  final String type; // live | movie | series
  Lib(this.s, this.type);

  List<Map> cats = [];
  final Map<String, List<It>> byCat = {};
  bool full = false, failed = false;
  double progress = 0;
  final ValueNotifier<int> tick = ValueNotifier<int>(0);
  Future<void>? _job;
  List<It>? _all;
  int _epoch = 0;

  static const catAction = {
    'live': 'get_live_categories',
    'movie': 'get_vod_categories',
    'series': 'get_series_categories'
  };
  static const itemAction = {
    'live': 'get_live_streams',
    'movie': 'get_vod_streams',
    'series': 'get_series'
  };

  int get total {
    var n = 0;
    for (final l in byCat.values) {
      n += l.length;
    }
    return n;
  }

  List<It> get all => _all ??= [
        for (final l in byCat.values) ...l,
      ];

  int? count(String id) => byCat[id]?.length;

  String catName(int id) {
    for (final c in cats) {
      if ('${c['category_id']}' == '$id') return '${c['category_name']}';
    }
    return '';
  }

  Future<void> loadCats() async {
    final l = await s.list(catAction[type]!);
    cats = [
      for (final c in l)
        if (c is Map) c
    ];
  }

  Future<List<It>> cat(String id) async {
    final have = byCat[id];
    if (have != null) return have;
    if (type == 'live' && full) return <It>[];
    final l = await s.fetchItems(itemAction[type]!, '&category_id=$id', type);
    byCat[id] = l;
    _all = null;
    tick.value++;
    return l;
  }

  Future<void> start({bool force = false}) {
    if (force) {
      _epoch++;
      _job = null;
      byCat.clear();
      cats = [];
      full = false;
      failed = false;
      progress = 0;
      _all = null;
      _lastSync = null;
      _syncing = false;
      _dropCache();
      tick.value++;
    }
    return _job ??= _run();
  }

  Future<String?> _path() async {
    try {
      var dir = await nat('cacheDir');
      if (dir is! String || dir.isEmpty) dir = Directory.systemTemp.path;
      if (!Directory('$dir').existsSync()) return null;
      return '$dir/lib_${type}_${s.user.hashCode.abs()}.tsv';
    } catch (_) {
      return null;
    }
  }

  Future<void> _dropCache() async {
    try {
      final path = await _path();
      if (path == null) return;
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  void _group(List<It> l) {
    for (final i in l) {
      (byCat['${i.cat}'] ??= <It>[]).add(i);
    }
    _all = null;
  }

  Future<void> _run() async {
    final ep = _epoch;
    failed = false;
    try {
      if (cats.isEmpty) await loadCats();
      if (type == 'live') {
        final l = await s.fetchItems(itemAction['live']!, '', type, 120);
        if (ep != _epoch) return;
        _group(l);
        full = true;
        progress = 1;
        _lastSync = DateTime.now();
      } else {
        await _runCats(ep);
      }
    } catch (_) {
      failed = true;
      _job = null;
    }
    tick.value++;
  }

  // One category, with up to 3 tries so a slow or busy server does not leave a gap in the total
  Future<List<It>> _fetchCat(String id) async {
    Object? last;
    for (var a = 0; a < 3; a++) {
      try {
        return await s.fetchItems(itemAction[type]!, '&category_id=$id', type);
      } catch (e) {
        last = e;
        await Future<void>.delayed(Duration(seconds: 1 + a * 2));
      }
    }
    throw last ?? Exception('fetch failed');
  }

  Future<void> _runCats(int ep) async {
    final path = await _path();
    final f = path == null ? null : File(path);
    if (path != null && f != null && f.existsSync()) {
      final l = await compute(readCache, path);
      if (ep != _epoch) return;
      if (l.isNotEmpty) {
        // Saved library: counts and lists show at once, new content is checked in the background
        _group(l);
        full = true;
        progress = 1;
        _lastSync = f.statSync().modified;
        tick.value++;
        if (Cfg.gb('auto_content', true)) refreshBg();
        return;
      }
    }
    final tmp = path == null ? null : File('$path.part');
    try {
      if (tmp != null && tmp.existsSync()) tmp.deleteSync();
    } catch (_) {}
    final ids = [for (final c in cats) '${c['category_id']}'];
    var done = 0, next = 0;
    var bad = false;
    Future<void> wq = Future<void>.value();
    Future<void> worker() async {
      while (true) {
        final k = next++;
        if (k >= ids.length || ep != _epoch) return;
        try {
          final have = byCat[ids[k]];
          final l = have ?? await _fetchCat(ids[k]);
          if (ep != _epoch) return;
          if (have == null) {
            byCat[ids[k]] = l;
            _all = null;
          }
          if (l.isNotEmpty && tmp != null) {
            final data = l.map((e) => e.line).join();
            wq = wq.then((_) => tmp.writeAsString(data, mode: FileMode.append)).catchError((_) {
              bad = true;
              return tmp;
            });
          }
        } catch (_) {
          bad = true;
        }
        done++;
        progress = done / ids.length;
        tick.value++;
      }
    }

    await Future.wait([for (var j = 0; j < 8; j++) worker()]);
    try {
      await wq;
    } catch (_) {
      bad = true;
    }
    if (ep != _epoch) return;
    if (!bad) {
      try {
        if (path != null && f != null && tmp != null) {
          if (f.existsSync()) f.deleteSync();
          if (tmp.existsSync()) tmp.renameSync(path);
        }
      } catch (_) {}
      full = true;
      _lastSync = DateTime.now();
    } else {
      try {
        if (tmp != null && tmp.existsSync()) tmp.deleteSync();
      } catch (_) {}
      failed = true;
      _job = null;
    }
    progress = 1;
  }

  // ---- Automatic update: picks up new / removed content without any button ----
  bool _syncing = false;
  DateTime? _lastSync;

  Future<void> _saveCache() async {
    final path = await _path();
    if (path == null) return;
    final tmp = File('$path.part');
    final sink = tmp.openWrite();
    try {
      for (final l in byCat.values.toList()) {
        if (l.isEmpty) continue;
        sink.write(l.map((e) => e.line).join());
        await Future<void>.delayed(Duration.zero);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
    tmp.renameSync(path);
  }

  bool _same(List<It> a, List<It> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].name != b[i].name || a[i].icon != b[i].icon) return false;
    }
    return true;
  }

  /// Quietly re-reads the server and updates only what changed. The counts keep
  /// showing the old total until the new data is ready, then switch by themselves.
  Future<void> refreshBg({bool force = false}) async {
    if (_syncing || !full) return;
    final last = _lastSync;
    if (!force && last != null && DateTime.now().difference(last).inMinutes < 4) return;
    _syncing = true;
    final ep = _epoch;
    var changed = false;
    try {
      final nc = await s.list(catAction[type]!);
      final newCats = [
        for (final c in nc)
          if (c is Map) c
      ];
      if (ep != _epoch) return;
      if (type == 'live') {
        final l = await s.fetchItems(itemAction['live']!, '', type, 120);
        if (ep != _epoch || l.isEmpty) return;
        final nm = <String, List<It>>{};
        for (final i in l) {
          (nm['${i.cat}'] ??= <It>[]).add(i);
        }
        final keys = {...byCat.keys, ...nm.keys};
        for (final k in keys) {
          final o = byCat[k] ?? <It>[], n = nm[k] ?? <It>[];
          if (!_same(o, n)) {
            changed = true;
            if (n.isEmpty) {
              byCat.remove(k);
            } else {
              byCat[k] = n;
            }
          }
        }
      } else {
        final ids = [for (final c in newCats) '${c['category_id']}'];
        if (ids.isEmpty) return;
        var next = 0;
        var bad = false;
        Future<void> worker() async {
          while (!bad) {
            final k = next++;
            if (k >= ids.length || ep != _epoch) return;
            try {
              final n = await _fetchCat(ids[k]);
              if (ep != _epoch) return;
              final o = byCat[ids[k]] ?? <It>[];
              if (!_same(o, n)) {
                changed = true;
                if (n.isEmpty) {
                  byCat.remove(ids[k]);
                } else {
                  byCat[ids[k]] = n;
                }
                _all = null;
                tick.value++;
              }
            } catch (_) {
              bad = true; // keep what we have; the next check tries again
            }
          }
        }

        await Future.wait([for (var j = 0; j < 4; j++) worker()]);
        if (bad || ep != _epoch) return;
        // categories the server no longer has
        final keep = ids.toSet();
        for (final k in byCat.keys.toList()) {
          if (!keep.contains(k)) {
            byCat.remove(k);
            changed = true;
          }
        }
      }
      if (ep != _epoch) return;
      cats = newCats;
      _lastSync = DateTime.now();
      if (changed) {
        _all = null;
        tick.value++;
        if (type != 'live') await _saveCache();
      } else if (type != 'live') {
        final path = await _path();
        if (path != null && File(path).existsSync()) File(path).setLastModifiedSync(DateTime.now());
      }
    } catch (_) {
      // offline or server busy: try again at the next check
    } finally {
      _syncing = false;
    }
  }

  List<It> recentAdded() {
    final l = List<It>.of(all)..sort((a, b) => b.added.compareTo(a.added));
    return l.take(100).toList();
  }

  List<It> search(String q) {
    final lq = q.toLowerCase();
    final out = <It>[];
    for (final i in all) {
      if (i.ln.contains(lq)) {
        out.add(i);
        if (out.length >= 2000) break;
      }
    }
    return out;
  }
}

Session? gSession;

// ---------------- Session ----------------
class Session {
  final String host, user, pass;
  final Map info;
  Session(this.host, this.user, this.pass, this.info) {
    gSession = this;
  }

  late final Lib live = Lib(this, 'live');
  late final Lib movie = Lib(this, 'movie');
  late final Lib series = Lib(this, 'series');

  String get u => Uri.encodeComponent(user);
  String get p => Uri.encodeComponent(pass);
  String api(String action, [String extra = '']) =>
      '$host/player_api.php?username=$u&password=$p&action=$action$extra';

  Future<List> list(String action, [String extra = '', int secs = 60]) async {
    final r = await http.get(Uri.parse(api(action, extra)), headers: ua).timeout(Duration(seconds: secs));
    final d = await compute(_decode, r.body);
    return d is List ? d : [];
  }

  Future<Map> infoOf(String action, String extra) async {
    final r = await http.get(Uri.parse(api(action, extra)), headers: ua).timeout(const Duration(seconds: 30));
    final d = await compute(_decode, r.body);
    return d is Map ? d : {};
  }

  Future<List<It>> fetchItems(String action, String extra, String type, [int secs = 120]) async {
    final r = await http.get(Uri.parse(api(action, extra)), headers: ua).timeout(Duration(seconds: secs));
    return compute(parseItems, <dynamic>[r.body, type]);
  }

  // Returns [now, next] programme titles
  Future<List<String>> epg(String id) async {
    try {
      final m = await infoOf('get_short_epg', '&stream_id=$id&limit=2');
      final l = m['epg_listings'];
      final out = <String>[];
      if (l is List) {
        for (final e in l) {
          if (e is Map) out.add(_b64('${e['title'] ?? ''}'));
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  // Catch-up (timeshift) link: start = 'YYYY-MM-DD HH:MM:SS' as given by the guide
  String catchupUrl(String id, String start, int minutes) {
    final st = start.length >= 16
        ? '${start.substring(0, 10)}:${start.substring(11, 13)}-${start.substring(14, 16)}'
        : start;
    return '$host/timeshift/$u/$p/$minutes/$st/$id.${Cfg.catchupFmt}';
  }

  String liveUrl(String id, [String ext = 'm3u8']) => '$host/live/$u/$p/$id.$ext';
  String movieUrl(String id, String ext) => '$host/movie/$u/$p/$id.$ext';
  String seriesUrl(String id, String ext) => '$host/series/$u/$p/$id.$ext';
}

Pi livePiOf(Session s, String id, String title) {
  final a = s.liveUrl(id, 'm3u8'), b = s.liveUrl(id, 'ts');
  switch (Cfg.liveFormat) {
    case 'ts':
      return Pi(title, b, a, id);
    case 'm3u8':
      return Pi(title, a, null, id);
    default:
      return Pi(title, a, b, id);
  }
}

// Checks which of the servers answer right now (used by "Refresh DNS" on the login screen)
Future<int> checkServers() async {
  final r = await Future.wait([
    for (final h in servers)
      http
          .get(Uri.parse('$h/player_api.php'), headers: ua)
          .timeout(const Duration(seconds: 8))
          .then((_) => true)
          .catchError((_) => false)
  ]);
  return r.where((x) => x).length;
}

// Tries all 3 servers one by one; the first one that accepts the login is used.
// loginDiag is a SHORT message for the screen (no server names, no technical text).
Future<Session?> tryLogin(String user, String pass) async {
  final u = Uri.encodeComponent(user), p = Uri.encodeComponent(pass);
  var answered = false, rejected = false;
  for (final h in servers) {
    try {
      final r = await http
          .get(Uri.parse('$h/player_api.php?username=$u&password=$p'), headers: ua)
          .timeout(const Duration(seconds: 15));
      answered = true;
      if (r.statusCode == 401 || r.statusCode == 403) {
        rejected = true;
        continue;
      }
      final body = r.body.replaceFirst('\uFEFF', '').trim();
      final d = jsonDecode(body);
      if (d is Map && d['user_info'] is Map) {
        if ('${d['user_info']['auth']}' == '1') {
          loginDiag = '';
          return Session(h, user, pass, d['user_info']);
        }
        rejected = true;
      }
    } on TimeoutException {
      // no answer from this server
    } on FormatException {
      answered = true; // server answered with a web page, not with account data
    } catch (_) {
      // no connection to this server
    }
  }
  loginDiag = rejected
      ? 'Username or Password Failed'
      : (answered ? 'Server Error. Try again later.' : 'No Internet Connection');
  return null;
}

// ---------------- Favourites / recently watched storage ----------------
Future<List<It>> loadList(String key) async {
  final pr = await SharedPreferences.getInstance();
  final out = <It>[];
  for (final x in pr.getStringList(key) ?? <String>[]) {
    try {
      out.add(It.fromJson(jsonDecode(x) as Map));
    } catch (_) {}
  }
  return out;
}

Future<void> saveList(String key, List<It> l) async {
  final pr = await SharedPreferences.getInstance();
  await pr.setStringList(key, [for (final i in l) jsonEncode(i.toJson())]);
}

Future<void> addRecentTo(String type, It i) async {
  final l = await loadList('recent_$type');
  l.removeWhere((x) => x.id == i.id);
  l.insert(0, i);
  if (l.length > 30) l.removeRange(30, l.length);
  await saveList('recent_$type', l);
}

// Returns true if the item is now a favourite
Future<bool> toggleFavOf(String type, It i) async {
  final l = await loadList('fav_$type');
  final had = l.any((x) => x.id == i.id);
  if (had) {
    l.removeWhere((x) => x.id == i.id);
  } else {
    l.insert(0, i);
  }
  await saveList('fav_$type', l);
  return !had;
}

// Cast photos and roles from TMDB (only when tmdbKey is set)
String get tmdbActiveKey {
  final c = Cfg.gs('tmdb_key').trim();
  return c.isNotEmpty ? c : tmdbKey;
}

Future<List<Map>> tmdbCast(String kind, String id) async {
  final key = tmdbActiveKey;
  if (!Cfg.gb('tmdb_on', true) || key.isEmpty || id.isEmpty || id == '0') return [];
  try {
    final r = await http
        .get(Uri.parse('https://api.themoviedb.org/3/$kind/$id/credits?api_key=$key'))
        .timeout(const Duration(seconds: 15));
    final d = jsonDecode(r.body);
    final l = d is Map ? d['cast'] : null;
    if (l is! List) return [];
    return [
      for (final e in l.take(20))
        if (e is Map) e
    ];
  } catch (_) {
    return [];
  }
}

// ---------------- Shared widgets ----------------
Widget logoImg(double s) => ClipRRect(
      borderRadius: BorderRadius.circular(s * 0.26),
      child: Image.asset('assets/logo.png', width: s, height: s),
    );

Widget rb(IconData i, VoidCallback f, {bool on = false}) => Padding(
      padding: const EdgeInsets.only(left: 6),
      child: IconButton(
        onPressed: f,
        icon: Icon(i, size: 20, color: on ? accent : null),
        style: IconButton.styleFrom(
            side: const BorderSide(color: Colors.white24),
            shape: const CircleBorder(),
            backgroundColor: card),
      ),
    );

Widget thumb(String img) => img.isEmpty
    ? const Icon(Icons.tv)
    : Image.network(img,
        fit: BoxFit.contain,
        cacheWidth: 120,
        errorBuilder: (_, __, ___) => const Icon(Icons.tv));

class GradBtn extends StatefulWidget {
  final String text;
  final VoidCallback? onTap;
  final bool busy, outline;
  final IconData? icon;
  final double height;
  const GradBtn(this.text, this.onTap,
      {this.busy = false, this.outline = false, this.icon, this.height = 48, super.key});
  @override
  State<GradBtn> createState() => _GradBtnState();
}

class _GradBtnState extends State<GradBtn> {
  bool f = false;
  @override
  Widget build(BuildContext c) => InkWell(
        onTap: widget.busy ? null : widget.onTap,
        onFocusChange: (v) => setState(() => f = v),
        focusColor: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: widget.height,
          decoration: BoxDecoration(
            gradient: widget.outline
                ? null
                : const LinearGradient(colors: [Color(0xFFFF6A4D), Color(0xFFFF4D7A)]),
            color: widget.outline ? card : null,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: showFocus(f)
                    ? Colors.white
                    : (widget.outline ? Colors.white24 : Colors.transparent),
                width: showFocus(f) ? 3 : 1),
          ),
          child: Center(
            child: widget.busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, size: 22, color: Colors.white),
                      const SizedBox(width: 8),
                    ],
                    Text(widget.text,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, letterSpacing: 0.5, color: Colors.white)),
                  ]),
          ),
        ),
      );
}

// Card that grows and gets a border when focused with a remote
class FocusCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLong;
  final bool autofocus;
  final EdgeInsets margin;
  final double radius;
  const FocusCard(
      {required this.child,
      required this.onTap,
      this.onLong,
      this.autofocus = false,
      this.margin = const EdgeInsets.all(6),
      this.radius = 20,
      super.key});
  @override
  State<FocusCard> createState() => _FocusCardState();
}

class _FocusCardState extends State<FocusCard> {
  bool f = false;
  @override
  Widget build(BuildContext c) {
    final on = showFocus(f);
    return AnimatedScale(
      scale: on ? 1.05 : 1,
      duration: const Duration(milliseconds: 120),
      child: InkWell(
        autofocus: widget.autofocus,
        onTap: widget.onTap,
        onLongPress: widget.onLong,
        onFocusChange: (v) => setState(() => f = v),
        focusColor: Colors.transparent,
        borderRadius: BorderRadius.circular(widget.radius),
        child: Container(
          margin: widget.margin,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(color: on ? accent : Colors.white12, width: on ? 3 : 1),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

// Poster / backdrop from TMDB when the provider has none
Future<Map<String, String>> tmdbArt(String kind, String id, String name) async {
  final out = <String, String>{};
  final key = tmdbActiveKey;
  if (!Cfg.gb('tmdb_on', true) || key.isEmpty) return out;
  try {
    Map? m;
    if (id.isNotEmpty && id != '0') {
      final r = await http
          .get(Uri.parse('https://api.themoviedb.org/3/$kind/$id?api_key=$key'))
          .timeout(const Duration(seconds: 15));
      final d = jsonDecode(r.body);
      if (d is Map) m = d;
    }
    if (m == null || m['poster_path'] == null) {
      final ym = RegExp(r'\((\d{4})\)').firstMatch(name);
      final q = name
          .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '')
          .replaceFirst(RegExp(r'^[^|]*\|'), '')
          .trim();
      if (q.isEmpty) return out;
      var url = 'https://api.themoviedb.org/3/search/$kind?api_key=$key&query=${Uri.encodeComponent(q)}';
      if (ym != null) {
        url += kind == 'tv' ? '&first_air_date_year=${ym.group(1)}' : '&year=${ym.group(1)}';
      }
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      final d = jsonDecode(r.body);
      final l = d is Map ? d['results'] : null;
      if (l is List && l.isNotEmpty && l.first is Map) m = l.first as Map;
    }
    if (m != null) {
      final pp = clean(m['poster_path']);
      final bp = clean(m['backdrop_path']);
      if (pp.isNotEmpty) out['poster'] = 'https://image.tmdb.org/t/p/w500$pp';
      if (bp.isNotEmpty) out['back'] = 'https://image.tmdb.org/t/p/w780$bp';
    }
  } catch (_) {}
  return out;
}
