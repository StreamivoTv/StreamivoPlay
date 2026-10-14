import 'dart:async';
import 'dart:convert';
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

class Session {
  final String host, user, pass;
  final Map info;
  Session(this.host, this.user, this.pass, this.info);
  String get u => Uri.encodeComponent(user);
  String get p => Uri.encodeComponent(pass);
  String api(String action, [String extra = '']) =>
      '$host/player_api.php?username=$u&password=$p&action=$action$extra';
  Future<List> list(String action, [String extra = '']) async {
    final r = await http
        .get(Uri.parse(api(action, extra)))
        .timeout(const Duration(seconds: 60));
    final d = jsonDecode(r.body);
    return d is List ? d : [];
  }

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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
          // Remote se focus hone par highlight dikhe
          focusColor: const Color(0x59FF6A4D),
          appBarTheme: const AppBarTheme(backgroundColor: bg, elevation: 0),
        ),
        home: const Splash(),
      );
}

Widget logoImg(double s) => ClipRRect(
      borderRadius: BorderRadius.circular(s * 0.2),
      child: Image.asset('assets/logo.png', width: s, height: s),
    );

// Gradient button (remote focus par safed border)
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
          height: 52,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFFF6A4D), Color(0xFFFF4D7A)]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: f ? Colors.white : Colors.transparent, width: 3),
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

// Home ke bade cards (remote focus par bade + border)
class FocusCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool autofocus;
  const FocusCard({required this.child, required this.onTap, this.autofocus = false, super.key});
  @override
  State<FocusCard> createState() => _FocusCardState();
}

class _FocusCardState extends State<FocusCard> {
  bool f = false;
  @override
  Widget build(BuildContext c) => AnimatedScale(
        scale: f ? 1.05 : 1,
        duration: const Duration(milliseconds: 120),
        child: InkWell(
          autofocus: widget.autofocus,
          onTap: widget.onTap,
          onFocusChange: (v) => setState(() => f = v),
          focusColor: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            height: 150,
            margin: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: f ? accent : Colors.white12, width: f ? 3 : 1),
            ),
            child: widget.child,
          ),
        ),
      );
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
            logoImg(180),
            const SizedBox(height: 24),
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
    final wide = MediaQuery.of(c).size.width > 700;
    final form = Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(20)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Login to your account',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          TextField(
            controller: u,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.person_outline),
                labelText: 'USERNAME',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: p,
            obscureText: hide,
            onSubmitted: (_) => go(),
            decoration: InputDecoration(
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
              padding: const EdgeInsets.only(top: 12),
              child: Text(err!, style: const TextStyle(color: Colors.redAccent)),
            ),
          const SizedBox(height: 20),
          GradBtn('LOGIN', go, busy: busy),
        ],
      ),
    );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: wide
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    logoImg(260),
                    const SizedBox(width: 48),
                    SizedBox(width: 420, child: form),
                  ])
                : Column(children: [
                    logoImg(150),
                    const SizedBox(height: 24),
                    SizedBox(width: double.infinity, child: form),
                  ]),
          ),
        ),
      ),
    );
  }
}

// ---------------- Home / Dashboard ----------------
class Home extends StatelessWidget {
  final Session s;
  const Home(this.s, {super.key});

  String expiry() {
    final e = s.info['exp_date'];
    if (e == null) return 'Unlimited';
    final n = int.tryParse('$e');
    if (n == null) return '$e';
    final d = DateTime.fromMillisecondsSinceEpoch(n * 1000);
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }

  Future<void> logout(BuildContext c) async {
    final pr = await SharedPreferences.getInstance();
    await pr.remove('u');
    await pr.remove('p');
    if (c.mounted) {
      Navigator.pushAndRemoveUntil(
          c, MaterialPageRoute(builder: (_) => const Login()), (_) => false);
    }
  }

  Widget tile(BuildContext c, String t, IconData i, Color col, String type,
          {bool first = false}) =>
      Expanded(
        child: FocusCard(
          autofocus: first,
          onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => Browse(s, type))),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(i, size: 52, color: col),
            const SizedBox(height: 10),
            Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ]),
        ),
      );

  Widget stat(String k, String v) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: const TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1)),
          const SizedBox(height: 4),
          Text(v, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ],
      );

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(
          leading: Padding(padding: const EdgeInsets.all(8), child: logoImg(36)),
          title: const Text('Streamivo'),
          actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => logout(c))],
        ),
        body: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            Row(children: [
              tile(c, 'Live TV', Icons.live_tv, Colors.redAccent, 'live', first: true),
              tile(c, 'Movies', Icons.movie, Colors.lightBlueAccent, 'movie'),
              tile(c, 'Series', Icons.video_library, Colors.purpleAccent, 'series'),
            ]),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(20)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('DASHBOARD',
                    style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 2)),
                const SizedBox(height: 6),
                Text(s.user, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Wrap(spacing: 36, runSpacing: 12, children: [
                  stat('CONNECTIONS',
                      '${s.info['active_cons'] ?? 0}/${s.info['max_connections'] ?? 1}'),
                  stat('STATUS', '${s.info['status'] ?? ''}'),
                  stat('EXPIRY DATE', expiry()),
                ]),
              ]),
            ),
          ]),
        ),
      );
}

// ---------------- Live / Movies / Series list ----------------
class Browse extends StatefulWidget {
  final Session s;
  final String type; // live | movie | series
  const Browse(this.s, this.type, {super.key});
  @override
  State<Browse> createState() => _BrowseState();
}

class _BrowseState extends State<Browse> {
  List cats = [], items = [];
  String catId = '';
  bool loading = true;
  String q = '';
  final sc = TextEditingController();
  Map<String, Map> favs = {};

  Session get s => widget.s;
  String get t => widget.type;
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

  Future<void> init() async {
    final pr = await SharedPreferences.getInstance();
    for (final x in pr.getStringList('fav_$t') ?? <String>[]) {
      final m = jsonDecode(x) as Map;
      favs[idOf(m)] = m;
    }
    try {
      cats = await s.list(catA[t]!);
    } catch (_) {}
    if (cats.isNotEmpty) {
      await load('${cats.first['category_id']}');
    } else if (mounted) {
      setState(() => loading = false);
    }
  }

  Future<void> load(String id) async {
    setState(() {
      catId = id;
      loading = true;
      q = '';
      sc.clear();
    });
    if (id == 'fav') {
      items = favs.values.toList();
    } else {
      try {
        items = await s.list(itemA[t]!, '&category_id=$id');
      } catch (_) {
        items = [];
      }
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> toggleFav(Map i) async {
    final k = idOf(i);
    setState(() {
      if (favs.containsKey(k)) {
        favs.remove(k);
      } else {
        favs[k] = i;
      }
    });
    final pr = await SharedPreferences.getInstance();
    await pr.setStringList('fav_$t', favs.values.map((e) => jsonEncode(e)).toList());
  }

  void open(Map i, List shown) {
    final name = '${i['name']}', id = idOf(i);
    Widget page;
    if (t == 'live') {
      // Poori list player ko dete hain taake remote ke up/down se channel badle
      final list = [
        for (final x in shown) Pi('${x['name']}', s.liveUrl(idOf(x)), s.liveUrl(idOf(x), 'ts'))
      ];
      page = Player(list, shown.indexOf(i), true);
    } else if (t == 'movie') {
      page = Player([Pi(name, s.movieUrl(id, '${i['container_extension'] ?? 'mp4'}'))], 0, false);
    } else {
      page = SeriesPage(s, id, name);
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext c) {
    final shown = q.isEmpty
        ? items
        : items.where((i) => '${i['name']}'.toLowerCase().contains(q.toLowerCase())).toList();
    final List all = [
      {'category_id': 'fav', 'category_name': 'FAVOURITES'},
      ...cats,
    ];
    return Scaffold(
      appBar: AppBar(
          title: Text(t == 'live' ? 'Live TV' : t == 'movie' ? 'Movies' : 'Series')),
      body: Row(children: [
        SizedBox(
          width: MediaQuery.of(c).size.width * 0.36,
          child: ListView(children: [
            for (var n = 0; n < all.length; n++)
              ListTile(
                autofocus: n == 1 || (n == 0 && all.length == 1),
                dense: true,
                selected: '${all[n]['category_id']}' == catId,
                selectedTileColor: Colors.white10,
                title: Text('${all[n]['category_name']}', maxLines: 2),
                onTap: () => load('${all[n]['category_id']}'),
              ),
          ]),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: TextField(
                controller: sc,
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search',
                    isDense: true,
                    border: OutlineInputBorder()),
                onChanged: (v) => setState(() => q = v),
              ),
            ),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (_, n) {
                        final i = shown[n] as Map;
                        final img = imgOf(i);
                        return ListTile(
                          leading: SizedBox(
                            width: 48,
                            height: 48,
                            child: img.isEmpty
                                ? const Icon(Icons.tv)
                                : Image.network(img,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.tv)),
                          ),
                          title: Text('${i['name']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            icon: Icon(
                                favs.containsKey(idOf(i)) ? Icons.favorite : Icons.favorite_border,
                                color: Colors.pinkAccent),
                            onPressed: () => toggleFav(i),
                          ),
                          onTap: () => open(i, shown),
                        );
                      },
                    ),
            ),
          ]),
        ),
      ]),
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
        Pi('${e['title'] ?? name}', s.seriesUrl('${e['id']}', '${e['container_extension'] ?? 'mp4'}'))
    ];
    return ExpansionTile(
      title: Text('Season ${se.key}'),
      children: [
        for (var n = 0; n < eps.length; n++)
          ListTile(
            title: Text('${eps[n]['title'] ?? eps[n]['id']}'),
            onTap: () => Navigator.push(
                c, MaterialPageRoute(builder: (_) => Player(list, n, false))),
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

// ---------------- Player (ExoPlayer + remote/touch controls) ----------------
class Pi {
  final String title, url;
  final String? alt;
  const Pi(this.title, this.url, [this.alt]);
}

class Player extends StatefulWidget {
  final List<Pi> items;
  final int index;
  final bool live;
  const Player(this.items, this.index, this.live, {super.key});
  @override
  State<Player> createState() => _PlayerState();
}

class _PlayerState extends State<Player> {
  VideoPlayerController? vc;
  late int idx;
  String? err;
  bool show = true, loading = true;
  Timer? hideT;
  int gen = 0;

  Pi get cur => widget.items[idx];

  @override
  void initState() {
    super.initState();
    idx = widget.index;
    WakelockPlus.enable();
    play(cur.url, cur.alt);
  }

  @override
  void dispose() {
    gen++;
    hideT?.cancel();
    vc?.dispose();
    WakelockPlus.disable();
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
    await old?.dispose();
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

  void toggle() {
    final v = vc;
    if (v == null) return;
    v.value.isPlaying ? v.pause() : v.play();
    poke();
  }

  Future<void> seek(int sec) async {
    final v = vc;
    if (v == null || widget.live) return;
    final pos = await v.position;
    if (pos != null) await v.seekTo(pos + Duration(seconds: sec));
    poke();
  }

  void zap(int d) {
    final n = idx + d;
    if (n < 0 || n >= widget.items.length) {
      poke();
      return;
    }
    idx = n;
    play(cur.url, cur.alt);
  }

  KeyEventResult onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.mediaPlayPause) {
      toggle();
    } else if (k == LogicalKeyboardKey.mediaPlay) {
      vc?.play();
      poke();
    } else if (k == LogicalKeyboardKey.mediaPause) {
      vc?.pause();
      poke();
    } else if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.mediaRewind) {
      seek(-10);
    } else if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.mediaFastForward) {
      seek(10);
    } else if (k == LogicalKeyboardKey.arrowUp ||
        k == LogicalKeyboardKey.channelUp ||
        k == LogicalKeyboardKey.mediaTrackPrevious) {
      zap(-1);
    } else if (k == LogicalKeyboardKey.arrowDown ||
        k == LogicalKeyboardKey.channelDown ||
        k == LogicalKeyboardKey.mediaTrackNext) {
      zap(1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Widget overlay(VideoPlayerController? v) => ExcludeFocus(
        child: Column(children: [
          Container(
            color: Colors.black54,
            padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
              Expanded(
                child: Text(cur.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              if (widget.live)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(6)),
                  child: const Text('LIVE', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
            ]),
          ),
          const Spacer(),
          Container(
            color: Colors.black54,
            padding: const EdgeInsets.all(12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (!widget.live && v != null)
                VideoProgressIndicator(v,
                    allowScrubbing: true,
                    colors: const VideoProgressColors(playedColor: accent)),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
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
              Text(
                widget.live
                    ? 'OK: Play/Pause    Up/Down: Channel badlein    Back: Wapas'
                    : 'OK: Play/Pause    Left/Right: 10 sec aage-peeche    Back: Wapas',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext c) {
    final v = vc;
    final hasErr = err != null || v?.value.hasError == true;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: onKey,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => show ? setState(() => show = false) : poke(),
          child: Stack(children: [
            Center(
              child: v != null && v.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: v.value.aspectRatio == 0 ? 16 / 9 : v.value.aspectRatio,
                      child: VideoPlayer(v))
                  : const SizedBox(),
            ),
            if (loading || (v != null && v.value.isBuffering))
              const Center(child: CircularProgressIndicator()),
            if (hasErr) Center(child: Text(err ?? 'Stream mein error aaya')),
            if (show || hasErr) Positioned.fill(child: overlay(v)),
          ]),
        ),
      ),
    );
  }
}
