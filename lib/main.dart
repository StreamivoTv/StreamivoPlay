import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'browse.dart';
import 'core.dart';
import 'settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = (d) => Material(
        color: bg,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text('Error: ${d.exceptionAsString()}',
                style: const TextStyle(color: Colors.white70)),
          ),
        ),
      );
  runApp(const Boot());
}

/// Shows something immediately (no black screen), then initialises.
class Boot extends StatefulWidget {
  const Boot({super.key});
  @override
  State<Boot> createState() => _BootState();
}

class _BootState extends State<Boot> {
  bool ready = false;
  String? err;

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    try {
      try {
        await SystemChrome.setPreferredOrientations(
            [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      } catch (_) {}
      initNative();
      try {
        isTv = (await nat('isTv').timeout(const Duration(seconds: 3))) == true;
      } catch (_) {}
      try {
        await Cfg.load().timeout(const Duration(seconds: 5));
      } catch (_) {}
      if (mounted) setState(() => ready = true);
    } catch (e, st) {
      if (mounted) setState(() => err = '$e\n$st');
    }
  }

  @override
  Widget build(BuildContext c) {
    if (ready) return const StreamivoApp();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: bg,
        body: Center(
          child: err != null
              ? Padding(
                  padding: const EdgeInsets.all(20),
                  child: SingleChildScrollView(
                      child: Text(err!, style: const TextStyle(color: Colors.white70))))
              : const CircularProgressIndicator(color: accent),
        ),
      ),
    );
  }
}

Future<void> doLogout(BuildContext c) async {
  final pr = await SharedPreferences.getInstance();
  await pr.remove('u');
  await pr.remove('p');
  if (c.mounted) {
    Navigator.pushAndRemoveUntil(c, MaterialPageRoute(builder: (_) => const Login()), (_) => false);
  }
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

// ---------------- Splash ----------------
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

  String? bootErr;

  Future<void> boot() async {
    String? u, pw;
    try {
      final pr = await SharedPreferences.getInstance().timeout(const Duration(seconds: 5));
      u = pr.getString('u');
      pw = pr.getString('p');
    } catch (e) {
      bootErr = '$e';
    }
    if (!mounted) return;
    final go = Cfg.autoLogin && u != null && pw != null;
    Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => go ? Setup(user: u, pass: pw) : const Login()));
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

// ---------------- "Setting up your library" ----------------
class Setup extends StatefulWidget {
  final Session? session;
  final String? user, pass;
  const Setup({this.session, this.user, this.pass, super.key});
  @override
  State<Setup> createState() => _SetupState();
}

class _SetupState extends State<Setup> {
  static const names = [
    'Checking servers',
    'Fetching config',
    'Loading categories',
    'Loading content',
    'Getting ready'
  ];
  int cur = 0;
  double pct = 0;
  String status = 'Connecting...';
  String? err;
  final List<double?> secs = List<double?>.filled(5, null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) run();
    });
  }

  void go(int step, double p, String st) {
    if (!mounted) return;
    setState(() {
      cur = step;
      pct = p;
      status = st;
    });
  }

  Future<void> run() async {
    final nav = Navigator.of(context);
    setState(() {
      err = null;
      cur = 0;
      pct = 0;
      status = 'Connecting...';
    });
    final sw = Stopwatch()..start();
    void done(int i) {
      secs[i] = sw.elapsedMilliseconds / 1000;
      sw.reset();
    }

    try {
      var s = widget.session;
      s ??= await tryLogin(widget.user ?? '', widget.pass ?? '');
      if (s == null) {
        if (mounted) {
          setState(() => err = 'Login failed. Check your username, password and internet connection.');
        }
        return;
      }
      final Session sess = s;
      done(0);
      go(1, 10, 'Reading account...');
      try {
        await sess.infoOf('', '');
      } catch (_) {}
      done(1);
      go(2, 25, 'Loading categories...');
      await Future.wait([sess.live.loadCats(), sess.movie.loadCats(), sess.series.loadCats()]);
      done(2);
      go(3, 45, 'Loading latest...');
      await sess.live.start();
      done(3);
      go(4, 95, 'Almost ready...');
      await Future.delayed(const Duration(milliseconds: 300));
      done(4);
      if (!mounted) return;
      setState(() => pct = 100);
      nav.pushReplacement(MaterialPageRoute(builder: (_) => Home(sess)));
      if (Cfg.startScreen == 'live') {
        nav.push(MaterialPageRoute(builder: (_) => Browse(sess, 'live')));
      }
    } catch (_) {
      if (mounted) {
        setState(() => err = 'Could not load your library. Check your internet connection.');
      }
    }
  }

  Widget stepRow(int i) {
    final isDone = i < cur;
    final isCur = i == cur && err == null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(children: [
        SizedBox(
          width: 34,
          height: 34,
          child: isDone
              ? const CircleAvatar(
                  backgroundColor: Color(0xFF2EC27E),
                  child: Icon(Icons.check, size: 20, color: Colors.white))
              : isCur
                  ? const Padding(
                      padding: EdgeInsets.all(4),
                      child: CircularProgressIndicator(strokeWidth: 3, color: accent))
                  : Container(
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24, width: 2))),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(names[i],
              style: TextStyle(
                  fontSize: 17, color: isDone || isCur ? Colors.white : Colors.white38)),
        ),
        if (secs[i] != null)
          Text('${secs[i]!.toStringAsFixed(1)} s',
              style: const TextStyle(color: Colors.white38, fontSize: 13)),
      ]),
    );
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Row(children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    logoImg(72),
                    const SizedBox(height: 14),
                    const Text('Setting up your library', style: TextStyle(fontSize: 22)),
                    const SizedBox(height: 6),
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('${pct.round()}',
                          style: const TextStyle(fontSize: 60, fontWeight: FontWeight.bold)),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12, left: 4),
                        child: Text('%', style: TextStyle(fontSize: 22, color: accent)),
                      ),
                    ]),
                    Text(err ?? status,
                        style: TextStyle(color: err != null ? Colors.redAccent : Colors.white70)),
                    if (err != null)
                      Row(children: [
                        TextButton(onPressed: run, child: const Text('RETRY')),
                        TextButton(
                            onPressed: () => Navigator.pushReplacement(
                                context, MaterialPageRoute(builder: (_) => const Login())),
                            child: const Text('LOGIN')),
                      ]),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [for (var i = 0; i < names.length; i++) stepRow(i)],
                ),
              ),
            ]),
          ),
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
      setState(() => err = 'Please enter your username and password.');
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
        err = 'Login failed.\n$loginDiag';
      });
      return;
    }
    final pr = await SharedPreferences.getInstance();
    await pr.setString('u', s.user);
    await pr.setString('p', s.pass);
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => Setup(session: s)));
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
              Flexible(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400), child: form)),
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

  @override
  void initState() {
    super.initState();
    // Movies and series are indexed in the background (counts, ALL and search)
    s.movie.start().then((_) => s.series.start());
  }

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
          actions: [
            TextButton(autofocus: true, onPressed: () => Navigator.pop(d), child: const Text('OK'))
          ],
        ),
      );

  void refreshAll() {
    s.live.start(force: true);
    s.movie.start(force: true).then((_) => s.series.start(force: true));
  }

  Widget sub(Lib l, String unit) => ValueListenableBuilder<int>(
        valueListenable: l.tick,
        builder: (_, __, ___) {
          var txt = l.total == 0 && !l.full ? 'Loading...' : '${l.total} $unit';
          if (!l.full && l.total > 0 && l.type != 'live') {
            txt += '  (${(l.progress * 100).round()}%)';
          }
          return Text(txt, style: const TextStyle(color: Colors.white54, fontSize: 13));
        },
      );

  Widget tile(String t, IconData i, Color col, String type, Widget subW, {bool first = false}) =>
      Expanded(
        child: FocusCard(
          autofocus: first,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Browse(s, type))),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(i, size: 56, color: col),
            const SizedBox(height: 8),
            Text(t, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            subW,
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
              rb(Icons.settings, () => Navigator.push(
                  c, MaterialPageRoute(builder: (_) => const SettingsPage()))),
              rb(Icons.refresh, refreshAll),
              rb(Icons.logout, () => doLogout(c)),
            ]),
            const SizedBox(height: 8),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                tile('Live TV', Icons.live_tv, Colors.redAccent, 'live', sub(s.live, 'Channels'),
                    first: true),
                tile('Movies', Icons.movie, Colors.lightBlueAccent, 'movie', sub(s.movie, 'Movies')),
                tile('Series', Icons.video_library, Colors.purpleAccent, 'series',
                    sub(s.series, 'Series')),
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
