import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

// ---- Aapke 3 servers (customer ko yeh kabhi nahi dikhte) ----
const servers = [
  'http://filex.me.uk:8080',
  'http://hexavip4u.online:80',
  'http://fiberstream.live:88',
];

const bg = Color(0xFF0B0B12);
const card = Color(0xFF16162A);
const accent = Color(0xFFFF6A4D);

// ---------------- Native (volume, brightness, TV detect) ----------------
const _ch = MethodChannel('streamivo/native');
bool isTv = false;

Future<dynamic> nat(String m, [dynamic a]) async {
  try {
    return await _ch.invokeMethod(m, a);
  } catch (_) {
    return null;
  }
}

bool showFocus(bool f) =>
    f && (isTv || FocusManager.instance.highlightMode == FocusHighlightMode.traditional);

dynamic _decode(String s) => jsonDecode(s);

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

// ---------------- Session ----------------
class Session {
  final String host, user, pass;
  final Map info;
  Future<List>? _live;
  Session(this.host, this.user, this.pass, this.info);

  String get u => Uri.encodeComponent(user);
  String get p => Uri.encodeComponent(pass);
  String api(String action, [String extra = '']) =>
      '$host/player_api.php?username=$u&password=$p&action=$action$extra';

  Future<List> list(String action, [String extra = '', int secs = 60]) async {
    final r = await http.get(Uri.parse(api(action, extra))).timeout(Duration(seconds: secs));
    final d = await compute(_decode, r.body);
    return d is List ? d : [];
  }

  // Live ki poori list ek baar load hoti hai (counts + ALL + search ke liye)
  Future<List> liveAll() => _live ??= list('get_live_streams', '', 120).catchError((Object e) {
        _live = null;
        throw e;
      });
  void clear() => _live = null;

  String liveUrl(String id, [String ext = 'm3u8']) => '$host/live/$u/$p/$id.$ext';
  String movieUrl(String id, String ext) => '$host/movie/$u/$p/$id.$ext';
  String seriesUrl(String id, String ext) => '$host/series/$u/$p/$id.$ext';
}

// Teeno servers ko ek ek karke try karta hai, jahan login ho wahi use hota hai
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

Future<void> doLogout(BuildContext c) async {
  final pr = await SharedPreferences.getInstance();
  await pr.remove('u');
  await pr.remove('p');
  if (c.mounted) {
    Navigator.pushAndRemoveUntil(c, MaterialPageRoute(builder: (_) => const Login()), (_) => false);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  isTv = (await nat('isTv')) == true;
  runApp(const StreamivoApp());
}

class StreamivoApp extends StatelessWidget {
  const StreamivoApp({super.key});
  @override
  Widget build(BuildContext c) => MaterialApp(
        title: 'Streamivo',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: bg,
          colorScheme: const ColorScheme.dark(primary: accent),
          focusColor: const Color(0x59FF6A4D),
          appBarTheme: const AppBarTheme(backgroundColor: bg, elevation: 0),
        ),
        home: const Splash(),
      );
}

// ---------------- Chhote widgets ----------------
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
  final bool busy;
  const GradBtn(this.text, this.onTap, {this.busy = false, super.key});
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
            gradient: const LinearGradient(colors: [Color(0xFFFF6A4D), Color(0xFFFF4D7A)]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: showFocus(f) ? Colors.white : Colors.transparent, width: 3),
          ),
          child: Center(
            child: widget.busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(widget.text,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, letterSpacing: 1, color: Colors.white)),
          ),
        ),
      );
}

// Card jo remote focus par bada + border dikhata hai
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

// ---------------- Splash (auto login) ----------------
class Splash extends StatefulWidget {
  const Splash({super.key});
  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> {
  @override
  void initState() {
    super.initState();
    boot();
  }

  Future<void> boot() async {
    final pr = await SharedPreferences.getInstance();
    final u = pr.getString('u'), pw = pr.getString('p');
    Session? s;
    if (u != null && pw != null) s = await tryLogin(u, pw);
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => s == null ? const Login() : Home(s)));
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            logoImg(140),
            const SizedBox(height: 20),
            const CircularProgressIndicator(),
          ]),
        ),
      );
}

// ---------------- Login ----------------
class Login extends StatefulWidget {
  const Login({super.key});
  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final u = TextEditingController(), p = TextEditingController();
  bool busy = false, hide = true;
  String? err;

  Future<void> go() async {
    if (u.text.trim().isEmpty || p.text.isEmpty) {
      setState(() => err = 'Username aur password dalein');
      return;
    }
    setState(() {
      busy = true;
      err = null;
    });
    final s = await tryLogin(u.text.trim(), p.text);
    if (!mounted) return;
    if (s == null) {
      setState(() {
        busy = false;
        err = 'Login nahi hua. Username/password ya internet check karein.';
      });
      return;
    }
    final pr = await SharedPreferences.getInstance();
    await pr.setString('u', s.user);
    await pr.setString('p', s.pass);
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => Home(s)));
  }

  @override
  Widget build(BuildContext c) {
    final form = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(20)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Login to your account',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          TextField(
            controller: u,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.person_outline),
                labelText: 'USERNAME',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: p,
            obscureText: hide,
            onSubmitted: (_) => go(),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.lock_outline),
              labelText: 'PASSWORD',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(hide ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => hide = !hide),
              ),
            ),
          ),
          if (err != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(err!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ),
          const SizedBox(height: 14),
          GradBtn('LOGIN', go, busy: busy),
        ],
      ),
    );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              logoImg(MediaQuery.of(c).size.height * 0.55),
              const SizedBox(width: 28),
              Flexible(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 400), child: form)),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------- Home ----------------
class Home extends StatefulWidget {
  final Session s;
  const Home(this.s, {super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  Session get s => widget.s;
  late Future<List> live = s.liveAll();

  String expiry() {
    final e = s.info['exp_date'];
    if (e == null) return 'Unlimited';
    final n = int.tryParse('$e');
    if (n == null) return '$e';
    final d = DateTime.fromMillisecondsSinceEpoch(n * 1000);
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }

  String get conns => '${s.info['active_cons'] ?? 0}/${s.info['max_connections'] ?? 1}';

  void account() => showDialog(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Account'),
          content: Text('Username: ${s.user}\nStatus: ${s.info['status'] ?? ''}\n'
              'Connections: $conns\nExpiry: ${expiry()}'),
          actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('OK'))],
        ),
      );

  Widget tile(String t, IconData i, Color col, String type, Widget sub, {bool first = false}) =>
      Expanded(
        child: FocusCard(
          autofocus: first,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Browse(s, type))),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(i, size: 56, color: col),
            const SizedBox(height: 8),
            Text(t, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            sub,
          ]),
        ),
      );

  Widget stat(String k, String v, {Color? col}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(k, style: const TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1)),
          const SizedBox(height: 2),
          Text(v, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: col)),
        ],
      );

  @override
  Widget build(BuildContext c) {
    const subStyle = TextStyle(color: Colors.white54, fontSize: 13);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Column(children: [
            Row(children: [
              logoImg(44),
              const SizedBox(width: 12),
              const Text('Streamivo', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const Spacer(),
              rb(Icons.person_outline, account),
              rb(Icons.refresh, () {
                s.clear();
                setState(() => live = s.liveAll());
              }),
              rb(Icons.logout, () => doLogout(c)),
            ]),
            const SizedBox(height: 8),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                tile(
                  'Live TV',
                  Icons.live_tv,
                  Colors.redAccent,
                  'live',
                  FutureBuilder<List>(
                    future: live,
                    builder: (_, snap) => Text(
                        snap.hasData ? '${snap.data!.length} Channels' : 'Loading...',
                        style: subStyle),
                  ),
                  first: true,
                ),
                tile('Movies', Icons.movie, Colors.lightBlueAccent, 'movie',
                    const Text('Browse', style: subStyle)),
                tile('Series', Icons.video_library, Colors.purpleAccent, 'series',
                    const Text('Browse', style: subStyle)),
              ]),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(20)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('DASHBOARD',
                        style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 2)),
                    const SizedBox(height: 2),
                    Text(s.user,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  ]),
                ),
                stat('CONNECTIONS', conns),
                const SizedBox(width: 24),
                stat('STATUS', '${s.info['status'] ?? ''}', col: Colors.greenAccent),
                const SizedBox(width: 24),
                stat('EXPIRY DATE', expiry()),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------- Live / Movies / Series ----------------
class Browse extends StatefulWidget {
  final Session s;
  final String type; // live | movie | series
  const Browse(this.s, this.type, {super.key});
  @override
  State<Browse> createState() => _BrowseState();
}

class _BrowseState extends State<Browse> {
  Session get s => widget.s;
  String get t => widget.type;
  bool get live => t == 'live';

  List cats = [], items = [], shown = [], allLive = [];
  Map<String, int> counts = {};
  String catId = '';
  bool loading = true, searching = false, sortAz = false;
  String? error;
  String q = '';
  int selGen = 0;
  final sc = TextEditingController();
  Map<String, Map> favs = {};
  List<Map> recent = [];

  // live preview
  VideoPlayerController? pv;
  Map? sel;
  bool pLoading = false;
  String? pErr;
  int pgen = 0;

  static const catA = {
    'live': 'get_live_categories',
    'movie': 'get_vod_categories',
    'series': 'get_series_categories'
  };
  static const itemA = {
    'live': 'get_live_streams',
    'movie': 'get_vod_streams',
    'series': 'get_series'
  };

  String idOf(Map i) => '${t == 'series' ? i['series_id'] : i['stream_id']}';
  String imgOf(Map i) => '${(t == 'series' ? i['cover'] : i['stream_icon']) ?? ''}';

  @override
  void initState() {
    super.initState();
    init();
  }

  @override
  void dispose() {
    pgen++;
    pv?.dispose();
    sc.dispose();
    super.dispose();
  }

  Future<void> init() async {
    final pr = await SharedPreferences.getInstance();
    for (final x in pr.getStringList('fav_$t') ?? <String>[]) {
      final m = jsonDecode(x) as Map;
      favs[idOf(m)] = m;
    }
    if (live) {
      for (final x in pr.getStringList('recent_live') ?? <String>[]) {
        recent.add(jsonDecode(x) as Map);
      }
    }
    await reload();
  }

  Future<void> reload() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      cats = await s.list(catA[t]!);
      if (live) {
        allLive = await s.liveAll();
        counts = {};
        for (final x in allLive) {
          final k = '${x['category_id']}';
          counts[k] = (counts[k] ?? 0) + 1;
        }
      }
    } catch (_) {
      error = 'Load nahi hua. Internet check karke RETRY dabayein.';
    }
    if (!mounted) return;
    if (error != null) {
      setState(() => loading = false);
      return;
    }
    if (catId.isEmpty) {
      catId = live ? 'all' : (cats.isNotEmpty ? '${cats.first['category_id']}' : 'fav');
    }
    await select(catId);
  }

  Future<void> select(String id) async {
    final my = ++selGen;
    setState(() {
      catId = id;
      loading = true;
      error = null;
      q = '';
      sc.clear();
    });
    String? err;
    List res = [];
    try {
      if (id == 'fav') {
        res = favs.values.toList();
      } else if (id == 'recent') {
        res = List.of(recent);
      } else if (live) {
        res = id == 'all' ? allLive : allLive.where((x) => '${x['category_id']}' == id).toList();
      } else {
        res = await s.list(itemA[t]!, '&category_id=$id', 120);
      }
    } catch (_) {
      err = 'Load nahi hua. Category dobara dabayein.';
    }
    if (!mounted || my != selGen) return;
    items = res;
    error = err;
    loading = false;
    recompute();
  }

  void recompute() {
    var l = q.isEmpty
        ? items
        : items.where((i) => '${i['name']}'.toLowerCase().contains(q.toLowerCase())).toList();
    if (sortAz) {
      l = List.of(l)
        ..sort((a, b) => '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()));
    }
    setState(() => shown = l);
  }

  Future<void> toggleFav(Map i) async {
    final k = idOf(i);
    if (favs.containsKey(k)) {
      favs.remove(k);
    } else {
      favs[k] = i;
    }
    if (catId == 'fav') items = favs.values.toList();
    recompute();
    final pr = await SharedPreferences.getInstance();
    await pr.setStringList('fav_$t', favs.values.map((e) => jsonEncode(e)).toList());
  }

  Future<void> addRecent(Map i) async {
    recent.removeWhere((x) => idOf(x) == idOf(i));
    recent.insert(0, i);
    if (recent.length > 30) recent.removeRange(30, recent.length);
    final pr = await SharedPreferences.getInstance();
    await pr.setStringList('recent_live', recent.map((e) => jsonEncode(e)).toList());
  }

  // ---- live preview ----
  Future<void> stopPreview() async {
    pgen++;
    final o = pv;
    if (mounted) {
      setState(() {
        pv = null;
        pLoading = false;
      });
    }
    await disposeLater(o);
  }

  Future<void> startPreview(Map i, {bool alt = false}) async {
    final my = ++pgen;
    final old = pv;
    setState(() {
      pv = null;
      pLoading = true;
      pErr = null;
    });
    await disposeLater(old);
    if (!mounted || my != pgen) return;
    final c = VideoPlayerController.networkUrl(
        Uri.parse(s.liveUrl(idOf(i), alt ? 'ts' : 'm3u8')));
    try {
      await c.initialize();
      if (!mounted || my != pgen) {
        await c.dispose();
        return;
      }
      await c.play();
      setState(() {
        pv = c;
        pLoading = false;
      });
    } catch (_) {
      await c.dispose();
      if (!mounted || my != pgen) return;
      if (!alt) {
        startPreview(i, alt: true);
      } else {
        setState(() {
          pLoading = false;
          pErr = 'Play nahi ho saka. Dusra channel try karein.';
        });
      }
    }
  }

  Future<void> fullscreen() async {
    final cur = sel;
    if (cur == null) return;
    var idx = shown.indexWhere((x) => idOf(x) == idOf(cur));
    final List src = idx >= 0 ? List.of(shown) : [cur];
    if (idx < 0) idx = 0;
    final list = [
      for (final x in src) Pi('${x['name']}', s.liveUrl(idOf(x)), s.liveUrl(idOf(x), 'ts'))
    ];
    // Max connection 1 hoti hai, isliye preview band karke fullscreen kholte hain
    await stopPreview();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Player(list, idx, true, onIndex: (n) {
          sel = src[n] as Map;
          addRecent(sel!);
        }),
      ),
    );
    if (mounted && sel != null) startPreview(sel!);
  }

  void onTapItem(Map i) {
    if (live) {
      if (sel != null && idOf(sel!) == idOf(i) && (pv != null || pLoading)) {
        fullscreen();
        return;
      }
      sel = i;
      addRecent(i);
      startPreview(i);
    } else if (t == 'movie') {
      final url = s.movieUrl(idOf(i), '${i['container_extension'] ?? 'mp4'}');
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => Player([Pi('${i['name']}', url)], 0, false)));
    } else {
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => SeriesPage(s, idOf(i), '${i['name']}')));
    }
  }

  void switchTo(String type) =>
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => Browse(s, type)));

  // ---- UI ----
  Widget tab(String label, String type) {
    final on = type == t;
    return InkWell(
      onTap: on ? null : () => switchTo(type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: on ? accent : Colors.transparent, width: 3))),
        child: Text(label,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: on ? Colors.white : Colors.white54)),
      ),
    );
  }

  Widget topBar() => SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            logoImg(36),
            Expanded(
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                tab('Live', 'live'),
                tab('Movies', 'movie'),
                tab('Series', 'series'),
              ]),
            ),
            rb(Icons.home, () => Navigator.popUntil(context, (r) => r.isFirst)),
            rb(Icons.search, () {
              setState(() => searching = !searching);
              if (!searching) {
                q = '';
                sc.clear();
                recompute();
              }
            }, on: searching),
            rb(Icons.sort_by_alpha, () {
              sortAz = !sortAz;
              recompute();
            }, on: sortAz),
            rb(Icons.refresh, () {
              s.clear();
              reload();
            }),
            rb(Icons.logout, () => doLogout(context)),
          ]),
        ),
      );

  Widget searchBar() => searching
      ? Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: sc,
            autofocus: true,
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search',
                isDense: true,
                border: OutlineInputBorder()),
            onChanged: (v) {
              q = v;
              recompute();
            },
          ),
        )
      : const SizedBox.shrink();

  Widget body(Widget Function() ok) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(error!, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          TextButton(onPressed: reload, child: const Text('RETRY')),
        ]),
      );
    }
    if (shown.isEmpty) return const Center(child: Text('Kuch nahi mila'));
    return ok();
  }

  Widget catPane() {
    final List all = [
      if (live) <String, dynamic>{'category_id': 'all', 'category_name': 'ALL', 'count': allLive.length},
      <String, dynamic>{'category_id': 'fav', 'category_name': 'FAVOURITES', 'count': favs.length},
      if (live)
        <String, dynamic>{
          'category_id': 'recent',
          'category_name': 'RECENTLY WATCHED',
          'count': recent.length
        },
      ...cats,
    ];
    return ListView.builder(
      itemCount: all.length,
      itemBuilder: (_, n) {
        final k = all[n] as Map;
        final id = '${k['category_id']}';
        final cnt = k['count'] ?? counts[id];
        return ListTile(
          autofocus: n == 0,
          dense: true,
          selected: id == catId,
          selectedColor: accent,
          selectedTileColor: Colors.white10,
          title: Text('${k['category_name']}', maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: cnt == null
              ? null
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: Colors.white12, borderRadius: BorderRadius.circular(10)),
                  child: Text('$cnt', style: const TextStyle(fontSize: 12)),
                ),
          onTap: () => select(id),
        );
      },
    );
  }

  Widget livePane() => Column(children: [
        searchBar(),
        Expanded(
          child: body(() => ListView.builder(
                itemCount: shown.length,
                itemBuilder: (_, n) {
                  final i = shown[n] as Map;
                  final on = sel != null && idOf(sel!) == idOf(i);
                  return ListTile(
                    dense: true,
                    selected: on,
                    selectedColor: accent,
                    selectedTileColor: Colors.white10,
                    leading: SizedBox(width: 44, height: 44, child: thumb(imgOf(i))),
                    title: Text('${i['name']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(favs.containsKey(idOf(i)) ? Icons.favorite : Icons.favorite_border,
                          size: 20, color: Colors.pinkAccent),
                      onPressed: () => toggleFav(i),
                    ),
                    onTap: () => onTapItem(i),
                  );
                },
              )),
        ),
      ]);

  Widget previewContent() {
    final v = pv;
    if (v != null) {
      return ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: v,
        builder: (_, val, __) => Stack(children: [
          Center(
            child: AspectRatio(
                aspectRatio: val.aspectRatio == 0 ? 16 / 9 : val.aspectRatio, child: VideoPlayer(v)),
          ),
          if (val.isBuffering) const Center(child: CircularProgressIndicator()),
        ]),
      );
    }
    if (pLoading) return const Center(child: CircularProgressIndicator());
    return Center(
        child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(pErr ?? 'Please Select Channel To Play', textAlign: TextAlign.center),
    ));
  }

  Widget previewPane() => Column(children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: InkWell(
            onTap: sel == null ? null : fullscreen,
            child: Container(color: Colors.black, child: previewContent()),
          ),
        ),
        Expanded(
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(12)),
            child: Center(
              child: Text(
                sel == null
                    ? 'No Channel Selected'
                    : '${sel!['name']}\n\nFullscreen ke liye same channel par dobara OK / tap karein',
                textAlign: TextAlign.center,
                style: TextStyle(color: sel == null ? Colors.white70 : Colors.white),
              ),
            ),
          ),
        ),
      ]);

  Widget gridPane() => Column(children: [
        searchBar(),
        Expanded(
          child: body(() => GridView.builder(
                padding: const EdgeInsets.all(10),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 130,
                    childAspectRatio: 0.58,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10),
                itemCount: shown.length,
                itemBuilder: (_, n) {
                  final i = shown[n] as Map;
                  final img = imgOf(i);
                  return FocusCard(
                    margin: EdgeInsets.zero,
                    radius: 10,
                    onTap: () => onTapItem(i),
                    onLong: () => toggleFav(i),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(
                        child: Stack(fit: StackFit.expand, children: [
                          img.isEmpty
                              ? const Icon(Icons.movie, size: 40)
                              : Image.network(img,
                                  fit: BoxFit.cover,
                                  cacheWidth: 220,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.movie, size: 40)),
                          if (favs.containsKey(idOf(i)))
                            const Positioned(
                                top: 4,
                                right: 4,
                                child: Icon(Icons.favorite, size: 18, color: Colors.pinkAccent)),
                        ]),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text('${i['name']}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ]),
                  );
                },
              )),
        ),
      ]);

  @override
  Widget build(BuildContext c) {
    final w = MediaQuery.of(c).size.width;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          topBar(),
          const Divider(height: 1),
          Expanded(
            child: Row(children: [
              SizedBox(width: w * 0.26, child: catPane()),
              const VerticalDivider(width: 1),
              if (live) ...[
                Expanded(flex: 11, child: livePane()),
                const VerticalDivider(width: 1),
                Expanded(flex: 10, child: previewPane()),
              ] else
                Expanded(child: gridPane()),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ---------------- Series episodes ----------------
class SeriesPage extends StatelessWidget {
  final Session s;
  final String id, name;
  const SeriesPage(this.s, this.id, this.name, {super.key});

  Future<List<MapEntry<String, List>>> load() async {
    final r = await http
        .get(Uri.parse(s.api('get_series_info', '&series_id=$id')))
        .timeout(const Duration(seconds: 30));
    final e = (jsonDecode(r.body) as Map)['episodes'];
    if (e is Map) return e.entries.map((x) => MapEntry('${x.key}', x.value as List)).toList();
    if (e is List) return [for (var i = 0; i < e.length; i++) MapEntry('${i + 1}', e[i] as List)];
    return [];
  }

  Widget season(BuildContext c, MapEntry<String, List> se) {
    final eps = se.value;
    final list = [
      for (final e in eps)
        Pi('${e['title'] ?? name}',
            s.seriesUrl('${e['id']}', '${e['container_extension'] ?? 'mp4'}'))
    ];
    return ExpansionTile(
      title: Text('Season ${se.key}'),
      children: [
        for (var n = 0; n < eps.length; n++)
          ListTile(
            title: Text('${eps[n]['title'] ?? eps[n]['id']}'),
            onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => Player(list, n, false))),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: Text(name)),
        body: FutureBuilder<List<MapEntry<String, List>>>(
          future: load(),
          builder: (c, snap) {
            if (snap.hasError) return const Center(child: Text('Load nahi hua'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            return ListView(children: [for (final se in snap.data!) season(c, se)]);
          },
        ),
      );
}

// ---------------- Player ----------------
class Pi {
  final String title, url;
  final String? alt;
  const Pi(this.title, this.url, [this.alt]);
}

class Player extends StatefulWidget {
  final List<Pi> items;
  final int index;
  final bool live;
  final ValueChanged<int>? onIndex;
  const Player(this.items, this.index, this.live, {this.onIndex, super.key});
  @override
  State<Player> createState() => _PlayerState();
}

class _PlayerState extends State<Player> {
  VideoPlayerController? vc;
  late int idx;
  String? err;
  bool show = true, loading = true;
  Timer? hideT, osdT;
  int gen = 0, rep = 0;
  BoxFit fit = BoxFit.contain;
  String? osd;
  IconData osdIcon = Icons.info;
  double volume = 0.5, bright = 0.5, accum = 0;
  int dragMode = 0; // 1 = volume (left), 2 = brightness (right)
  bool hOn = false;
  double hdx = 0;
  Duration hBase = Duration.zero;
  int hSec = 0;

  Pi get cur => widget.items[idx];

  @override
  void initState() {
    super.initState();
    idx = widget.index;
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    nat('getVolume').then((v) {
      if (v is double) volume = v;
    });
    nat('getBrightness').then((v) {
      if (v is double) bright = v;
    });
    play(cur.url, cur.alt);
  }

  @override
  void dispose() {
    gen++;
    hideT?.cancel();
    osdT?.cancel();
    vc?.dispose();
    WakelockPlus.disable();
    nat('resetBrightness');
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    super.dispose();
  }

  Future<void> play(String url, String? alt) async {
    final my = ++gen;
    final old = vc;
    setState(() {
      vc = null;
      loading = true;
      err = null;
    });
    await disposeLater(old);
    if (!mounted || my != gen) return;
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await c.initialize();
      if (!mounted || my != gen) {
        await c.dispose();
        return;
      }
      c.addListener(() {
        if (mounted) setState(() {});
      });
      await c.play();
      setState(() {
        vc = c;
        loading = false;
      });
      poke();
    } catch (_) {
      await c.dispose();
      if (!mounted || my != gen) return;
      if (alt != null) {
        play(alt, null);
      } else {
        setState(() {
          loading = false;
          err = 'Play nahi ho saka. Dobara try karein.';
        });
      }
    }
  }

  void poke() {
    setState(() => show = true);
    hideT?.cancel();
    hideT = Timer(const Duration(seconds: 4), () {
      if (mounted && vc?.value.isPlaying == true) setState(() => show = false);
    });
  }

  void showOsd(IconData icon, String text) {
    setState(() {
      osdIcon = icon;
      osd = text;
    });
    osdT?.cancel();
    osdT = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => osd = null);
    });
  }

  void toggle() {
    final v = vc;
    if (v == null) return;
    v.value.isPlaying ? v.pause() : v.play();
    poke();
  }

  Future<void> seek(int sec) async {
    final v = vc;
    if (v == null || widget.live) {
      poke();
      return;
    }
    var t = v.value.position + Duration(seconds: sec);
    if (t < Duration.zero) t = Duration.zero;
    if (t > v.value.duration) t = v.value.duration;
    await v.seekTo(t);
    showOsd(sec > 0 ? Icons.fast_forward : Icons.fast_rewind, '${sec > 0 ? '+' : ''}$sec s');
    poke();
  }

  void zap(int d) {
    final n = idx + d;
    if (n < 0 || n >= widget.items.length) {
      poke();
      return;
    }
    idx = n;
    widget.onIndex?.call(idx);
    play(cur.url, cur.alt);
  }

  // ---- gestures ----
  void vStart(DragStartDetails d, double w) {
    dragMode = d.localPosition.dx < w / 2 ? 1 : 2;
    accum = dragMode == 1 ? volume : bright;
  }

  void vUpdate(DragUpdateDetails d, double h) {
    accum = (accum - d.delta.dy / (h * 0.7)).clamp(0.0, 1.0).toDouble();
    if (dragMode == 1) {
      volume = accum;
      nat('setVolume', volume);
      showOsd(volume == 0 ? Icons.volume_off : Icons.volume_up, 'Volume ${(volume * 100).round()}%');
    } else {
      bright = accum;
      nat('setBrightness', bright < 0.02 ? 0.02 : bright);
      showOsd(Icons.brightness_6, 'Brightness ${(bright * 100).round()}%');
    }
  }

  Duration hTarget(VideoPlayerController v) {
    var t = hBase + Duration(seconds: hSec);
    if (t < Duration.zero) t = Duration.zero;
    if (t > v.value.duration) t = v.value.duration;
    return t;
  }

  void hStart(DragStartDetails d) {
    hOn = !widget.live && vc != null;
    hdx = 0;
    hSec = 0;
    hBase = vc?.value.position ?? Duration.zero;
  }

  void hUpdate(DragUpdateDetails d, double w) {
    final v = vc;
    if (!hOn || v == null) return;
    hdx += d.delta.dx;
    hSec = (hdx / w * 240).round(); // poori screen ka swipe = 4 minute
    showOsd(hSec >= 0 ? Icons.fast_forward : Icons.fast_rewind,
        '${hSec >= 0 ? '+' : ''}$hSec s   ${fmt(hTarget(v))}');
  }

  void hEnd() {
    final v = vc;
    if (!hOn || v == null) return;
    hOn = false;
    v.seekTo(hTarget(v));
    poke();
  }

  // ---- remote / keyboard ----
  KeyEventResult onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    rep = e is KeyDownEvent ? 0 : rep + 1;
    final k = e.logicalKey;
    final step = 10 * (1 + rep ~/ 6); // button dabaye rakhne par tez
    final st = step > 120 ? 120 : step;
    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.mediaPlayPause) {
      if (e is KeyDownEvent) toggle();
    } else if (k == LogicalKeyboardKey.mediaPlay) {
      vc?.play();
      poke();
    } else if (k == LogicalKeyboardKey.mediaPause) {
      vc?.pause();
      poke();
    } else if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.mediaRewind) {
      seek(-st);
    } else if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.mediaFastForward) {
      seek(st);
    } else if (k == LogicalKeyboardKey.arrowUp ||
        k == LogicalKeyboardKey.channelUp ||
        k == LogicalKeyboardKey.mediaTrackPrevious) {
      if (e is KeyDownEvent) zap(-1);
    } else if (k == LogicalKeyboardKey.arrowDown ||
        k == LogicalKeyboardKey.channelDown ||
        k == LogicalKeyboardKey.mediaTrackNext) {
      if (e is KeyDownEvent) zap(1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void cycleFit() {
    fit = fit == BoxFit.contain
        ? BoxFit.cover
        : fit == BoxFit.cover
            ? BoxFit.fill
            : BoxFit.contain;
    showOsd(Icons.aspect_ratio,
        fit == BoxFit.contain ? 'Fit' : fit == BoxFit.cover ? 'Zoom' : 'Stretch');
    poke();
  }

  Widget overlay(VideoPlayerController? v) {
    final size = v?.value.size;
    return ExcludeFocus(
      child: Column(children: [
        Container(
          color: Colors.black54,
          padding: const EdgeInsets.fromLTRB(8, 10, 16, 10),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
            if (widget.live)
              Container(
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration:
                    BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(6)),
                child: const Text('LIVE', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            Expanded(
              child: Text(cur.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            if (size != null && size.width > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    border: Border.all(color: Colors.white38),
                    borderRadius: BorderRadius.circular(12)),
                child: Text('${size.width.toInt()}x${size.height.toInt()}',
                    style: const TextStyle(fontSize: 12)),
              ),
          ]),
        ),
        const Spacer(),
        Container(
          color: Colors.black54,
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (!widget.live && v != null)
              Row(children: [
                Text(fmt(v.value.position), style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 8),
                Expanded(
                  child: VideoProgressIndicator(v,
                      allowScrubbing: true, colors: const VideoProgressColors(playedColor: accent)),
                ),
                const SizedBox(width: 8),
                Text(fmt(v.value.duration), style: const TextStyle(fontSize: 12)),
              ]),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(icon: const Icon(Icons.aspect_ratio), onPressed: cycleFit),
              IconButton(icon: const Icon(Icons.skip_previous), onPressed: () => zap(-1)),
              if (!widget.live)
                IconButton(icon: const Icon(Icons.replay_10), onPressed: () => seek(-10)),
              IconButton(
                iconSize: 44,
                icon: Icon(v?.value.isPlaying == true ? Icons.pause_circle : Icons.play_circle),
                onPressed: toggle,
              ),
              if (!widget.live)
                IconButton(icon: const Icon(Icons.forward_10), onPressed: () => seek(10)),
              IconButton(icon: const Icon(Icons.skip_next), onPressed: () => zap(1)),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget video(VideoPlayerController v) {
    final sz = v.value.size;
    return SizedBox.expand(
      child: FittedBox(
        fit: fit,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: sz.width == 0 ? 16 : sz.width,
          height: sz.height == 0 ? 9 : sz.height,
          child: VideoPlayer(v),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    final v = vc;
    final hasErr = err != null || v?.value.hasError == true;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: onKey,
        child: LayoutBuilder(
          builder: (ctx, cons) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => show ? setState(() => show = false) : poke(),
            onVerticalDragStart: (d) => vStart(d, cons.maxWidth),
            onVerticalDragUpdate: (d) => vUpdate(d, cons.maxHeight),
            onHorizontalDragStart: hStart,
            onHorizontalDragUpdate: (d) => hUpdate(d, cons.maxWidth),
            onHorizontalDragEnd: (_) => hEnd(),
            child: Stack(children: [
              if (v != null && v.value.isInitialized) video(v),
              if (loading || (v != null && v.value.isBuffering))
                const Center(child: CircularProgressIndicator()),
              if (hasErr) Center(child: Text(err ?? 'Stream mein error aaya')),
              if (show || hasErr) Positioned.fill(child: overlay(v)),
              if (osd != null)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                        color: Colors.black87, borderRadius: BorderRadius.circular(12)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(osdIcon),
                      const SizedBox(width: 10),
                      Text(osd!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
