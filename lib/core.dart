import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

// ---- Your 3 servers (customers never see these) ----
const servers = [
  'http://filex.me.uk:8080',
  'http://hexavip4u.online:80',
  'http://fiberstream.live:88',
];

// Optional: put a free TMDB API key here to show cast photos and roles
// (get one at themoviedb.org). Leave empty to show cast names only.
const tmdbKey = '';

const bg = Color(0xFF0B0B12);
const card = Color(0xFF16162A);
const accent = Color(0xFFFF6A4D);

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

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    autoLogin = p.getBool('cfg_auto') ?? true;
    startScreen = p.getString('cfg_start') ?? 'home';
    playerMode = p.getString('cfg_player') ?? 'builtin';
    externalApp = p.getString('cfg_ext') ?? 'ask';
    liveFormat = p.getString('cfg_fmt') ?? 'default';
    fit = p.getString('cfg_fit') ?? 'contain';
  }

  static Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('cfg_auto', autoLogin);
    await p.setString('cfg_start', startScreen);
    await p.setString('cfg_player', playerMode);
    await p.setString('cfg_ext', externalApp);
    await p.setString('cfg_fmt', liveFormat);
    await p.setString('cfg_fit', fit);
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
      _dropCache();
      tick.value++;
    }
    return _job ??= _run();
  }

  Future<String> _path() async =>
      '${(await getTemporaryDirectory()).path}/lib_${type}_${s.user.hashCode.abs()}.tsv';

  Future<void> _dropCache() async {
    try {
      final f = File(await _path());
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
    try {
      if (cats.isEmpty) await loadCats();
      if (type == 'live') {
        final l = await s.fetchItems(itemAction['live']!, '', type, 120);
        if (ep != _epoch) return;
        _group(l);
        full = true;
        progress = 1;
      } else {
        await _runCats(ep);
      }
    } catch (_) {
      failed = true;
      _job = null;
    }
    tick.value++;
  }

  Future<void> _runCats(int ep) async {
    final path = await _path();
    final f = File(path);
    if (f.existsSync() && DateTime.now().difference(f.statSync().modified).inHours < 12) {
      final l = await compute(readCache, path);
      if (ep != _epoch) return;
      if (l.isNotEmpty) {
        _group(l);
        full = true;
        progress = 1;
        tick.value++;
        return;
      }
    }
    final tmp = File('$path.part');
    try {
      if (tmp.existsSync()) tmp.deleteSync();
    } catch (_) {}
    final ids = [for (final c in cats) '${c['category_id']}'];
    var done = 0, next = 0;
    var bad = false, complete = true;
    Future<void> wq = Future<void>.value();
    Future<void> worker() async {
      while (true) {
        final k = next++;
        if (k >= ids.length || ep != _epoch) return;
        if (byCat.containsKey(ids[k])) {
          complete = false;
          done++;
          continue;
        }
        try {
          final l = await s.fetchItems(itemAction[type]!, '&category_id=${ids[k]}', type);
          if (ep != _epoch) return;
          byCat[ids[k]] = l;
          _all = null;
          if (l.isNotEmpty) {
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

    await Future.wait([for (var j = 0; j < 4; j++) worker()]);
    try {
      await wq;
    } catch (_) {
      bad = true;
    }
    if (ep != _epoch) return;
    if (!bad && complete) {
      try {
        if (f.existsSync()) f.deleteSync();
        if (tmp.existsSync()) tmp.renameSync(path);
      } catch (_) {}
      full = true;
    } else {
      try {
        if (tmp.existsSync()) tmp.deleteSync();
      } catch (_) {}
      if (bad) {
        failed = true;
        _job = null;
      } else {
        full = true;
      }
    }
    progress = 1;
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

// ---------------- Session ----------------
class Session {
  final String host, user, pass;
  final Map info;
  Session(this.host, this.user, this.pass, this.info);

  late final Lib live = Lib(this, 'live');
  late final Lib movie = Lib(this, 'movie');
  late final Lib series = Lib(this, 'series');

  String get u => Uri.encodeComponent(user);
  String get p => Uri.encodeComponent(pass);
  String api(String action, [String extra = '']) =>
      '$host/player_api.php?username=$u&password=$p&action=$action$extra';

  Future<List> list(String action, [String extra = '', int secs = 60]) async {
    final r = await http.get(Uri.parse(api(action, extra))).timeout(Duration(seconds: secs));
    final d = await compute(_decode, r.body);
    return d is List ? d : [];
  }

  Future<Map> infoOf(String action, String extra) async {
    final r = await http.get(Uri.parse(api(action, extra))).timeout(const Duration(seconds: 30));
    final d = await compute(_decode, r.body);
    return d is Map ? d : {};
  }

  Future<List<It>> fetchItems(String action, String extra, String type, [int secs = 120]) async {
    final r = await http.get(Uri.parse(api(action, extra))).timeout(Duration(seconds: secs));
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

// Tries all 3 servers one by one; the first one that accepts the login is used
Future<Session?> tryLogin(String user, String pass) async {
  final u = Uri.encodeComponent(user), p = Uri.encodeComponent(pass);
  for (final h in servers) {
    try {
      final r = await http
          .get(Uri.parse('$h/player_api.php?username=$u&password=$p'))
          .timeout(const Duration(seconds: 8));
      final d = jsonDecode(r.body);
      if (d is Map && d['user_info'] is Map && '${d['user_info']['auth']}' == '1') {
        return Session(h, user, pass, d['user_info']);
      }
    } catch (_) {}
  }
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
Future<List<Map>> tmdbCast(String kind, String id) async {
  if (tmdbKey.isEmpty || id.isEmpty || id == '0') return [];
  try {
    final r = await http
        .get(Uri.parse('https://api.themoviedb.org/3/$kind/$id/credits?api_key=$tmdbKey'))
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
      borderRadius: BorderRadius.circular(s * 0.2),
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
  const GradBtn(this.text, this.onTap,
      {this.busy = false, this.outline = false, this.icon, super.key});
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
          height: 48,
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
