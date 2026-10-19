import 'dart:io';
import 'package:flutter/material.dart';
import 'core.dart';
import 'extra.dart';
import 'fx.dart';

class _Item {
  final IconData icon;
  final String title, sub;
  final VoidCallback onTap;
  _Item(this.icon, this.title, this.sub, this.onTap);
}

void _snack(BuildContext c, String m) {
  if (!c.mounted) return;
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));
}

// ---------------- Parental control (also opened from the home screen) ----------------
Future<void> parentalDialog(BuildContext c) async {
  if (Cfg.gs('pin').isNotEmpty) {
    final ok = await verifyPin(c);
    if (!c.mounted) return;
    if (!ok) {
      _snack(c, 'Wrong PIN');
      return;
    }
    final act = await pickFx(
        c,
        'Parental Control',
        const [
          ['change', 'Change PIN'],
          ['remove', 'Remove PIN'],
        ],
        '');
    if (act == null || !c.mounted) return;
    if (act == 'remove') {
      await Cfg.ps('pin', '');
      _snack(c, 'PIN removed');
      return;
    }
  }
  if (!c.mounted) return;
  final n = await showDialog<String>(context: c, builder: (d) => const _NewPin());
  if (n != null) {
    await Cfg.ps('pin', n);
    _snack(c, 'PIN saved. Adult categories now need this PIN.');
  }
}

class _NewPin extends StatefulWidget {
  const _NewPin();
  @override
  State<_NewPin> createState() => _NewPinState();
}

class _NewPinState extends State<_NewPin> {
  final a = TextEditingController(), b = TextEditingController();
  String? err;

  @override
  void dispose() {
    a.dispose();
    b.dispose();
    super.dispose();
  }

  void save() {
    final x = a.text.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(x)) {
      setState(() => err = 'The PIN must be exactly 4 digits.');
      return;
    }
    if (x != b.text.trim()) {
      setState(() => err = 'The two PINs do not match.');
      return;
    }
    Navigator.pop(context, x);
  }

  @override
  Widget build(BuildContext c) => FxDialog(
        label: 'PARENTAL CONTROL',
        title: 'Set PIN',
        width: 440,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Adult categories (XXX, 18+, Adult) will ask for this PIN.',
              style: TextStyle(color: Colors.white70)),
          fxLabel('New PIN'),
          fxInput(a, '4 digits', obscure: true, type: TextInputType.number, maxLen: 4, autofocus: true),
          fxLabel('Confirm PIN'),
          fxInput(b, '4 digits',
              obscure: true, type: TextInputType.number, maxLen: 4, onSubmit: (_) => save()),
          if (err != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(err!, style: const TextStyle(color: Colors.redAccent)),
            ),
        ]),
        actions: [
          FxBtn('Cancel', () => Navigator.pop(c)),
          FxBtn('Save', save, primary: true),
        ],
      );
}

// ---------------- Speed test ----------------
class _SpeedDlg extends StatefulWidget {
  const _SpeedDlg();
  @override
  State<_SpeedDlg> createState() => _SpeedState();
}

class _SpeedState extends State<_SpeedDlg> {
  bool running = false, stop = false;
  double mbps = 0;
  String status = 'Tap Start to test the connection to your server.';
  HttpClient? hc;

  @override
  void dispose() {
    stop = true;
    hc?.close(force: true);
    super.dispose();
  }

  Future<void> run() async {
    final s = gSession;
    if (s == null) {
      setState(() => status = 'Please log in first.');
      return;
    }
    setState(() {
      running = true;
      mbps = 0;
      status = 'Testing...';
    });
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    hc = client;
    var bytes = 0;
    final sw = Stopwatch()..start();
    try {
      final rq = await client.getUrl(Uri.parse(s.api('get_vod_streams')));
      ua.forEach((k, v) => rq.headers.set(k, v));
      final rs = await rq.close().timeout(const Duration(seconds: 20));
      var last = 0;
      await for (final ch in rs) {
        bytes += ch.length;
        final ms = sw.elapsedMilliseconds;
        if (ms - last > 300 && mounted) {
          last = ms;
          setState(() => mbps = bytes * 8 / (ms / 1000) / 1e6);
        }
        if (ms > 8000 || stop) break;
      }
      final secs = sw.elapsedMilliseconds / 1000;
      final r = secs <= 0 ? 0.0 : bytes * 8 / secs / 1e6;
      if (!mounted) return;
      setState(() {
        running = false;
        mbps = r;
        status = bytes < 300000
            ? 'The test file was small, so this result may be low.'
            : (r >= 25
                ? 'Excellent - fine for 4K'
                : r >= 8
                    ? 'Good - fine for HD'
                    : r >= 3
                        ? 'OK - SD quality'
                        : 'Slow - streams may buffer');
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          running = false;
          status = 'The test failed. Check your internet connection.';
        });
      }
    } finally {
      client.close(force: true);
    }
  }

  @override
  Widget build(BuildContext c) => FxDialog(
        label: 'NETWORK',
        title: 'Speed Test',
        width: 440,
        child: Column(children: [
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(mbps.toStringAsFixed(1),
                style: const TextStyle(fontSize: 56, fontWeight: FontWeight.bold)),
            const Padding(
              padding: EdgeInsets.only(bottom: 10, left: 6),
              child: Text('Mbps', style: TextStyle(fontSize: 20, color: accent)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(status, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
          if (running)
            const Padding(
              padding: EdgeInsets.only(top: 14),
              child: LinearProgressIndicator(color: accent, backgroundColor: Colors.white12),
            ),
        ]),
        actions: [
          FxBtn('Close', () => Navigator.pop(c)),
          FxBtn(running ? 'Testing...' : 'Start', () {
            if (!running) run();
          }, primary: true),
        ],
      );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsPage> {
  static const _playerChoices = [
    ['builtin', 'ExoPlayer (Built-in)'],
    ['external', 'External player'],
  ];
  static const _kinds = [
    ['live', 'LIVE'],
    ['movie', 'MOVIES'],
    ['series', 'SERIES'],
    ['rec', 'RECORDINGS'],
    ['guide', 'LIVE TV WITH GUIDE'],
    ['catchup', 'CATCH UP'],
  ];
  static const _extOpts = [
    ['ask', 'Ask every time'],
    ['vlc', 'VLC'],
    ['mx', 'MX Player'],
  ];
  static const _fmtOpts = [
    ['default', 'Default'],
    ['m3u8', 'HLS (.m3u8)'],
    ['ts', 'MPEGTS (.ts)'],
  ];
  static const _cuOpts = [
    ['ts', 'MPEGTS (.ts)'],
    ['m3u8', 'HLS (.m3u8)'],
  ];
  static const _fitOpts = [
    ['contain', 'Fit'],
    ['cover', 'Zoom'],
    ['fill', 'Stretch'],
  ];
  static const _loadOpts = [
    ['detailed', 'Detailed (speed & buffer info)'],
    ['simple', 'Simple (logo only)'],
  ];
  static const _dispOpts = [
    ['auto', 'Automatic'],
    ['phone', 'Phone (compact)'],
    ['tv', 'TV (large)'],
  ];
  static const _timeOpts = [
    ['24', '24-hour (14:30)'],
    ['12', '12-hour (2:30 PM)'],
  ];
  static const _liveDec = [
    ['auto', 'Auto'],
    ['hw', 'Hardware only'],
    ['sw', 'Software only'],
  ];
  static const _vodDec = [
    ['hw', 'Hardware only'],
    ['auto', 'Auto'],
    ['sw', 'Software only'],
  ];
  static const _hoursOpts = [
    ['0', 'Everything available'],
    ['6', '6 hours'],
    ['12', '12 hours'],
    ['24', '24 hours'],
    ['48', '2 days'],
  ];
  static const _subLangs = [
    ['en', 'English'],
    ['ur', 'Urdu'],
    ['hi', 'Hindi'],
    ['ar', 'Arabic'],
    ['es', 'Spanish'],
    ['fr', 'French'],
    ['tr', 'Turkish'],
  ];
  static final _shiftOpts = [
    for (var h = -12; h <= 12; h++) ['$h', h == 0 ? 'No shift' : '${h > 0 ? '+' : ''}$h hours']
  ];
  static const _changelog = [
    ['1.1.0', 'New home screen, account info page, series page with episode list, full settings, multi-screen layouts, parental PIN, speed test.'],
    ['1.0.0', 'First release.'],
  ];

  String label(List<List<String>> opts, String key) {
    for (final o in opts) {
      if (o[0] == key) return o[1];
    }
    return key;
  }

  void info(String title, String msg) => showDialog(
        context: context,
        builder: (d) => FxDialog(
          label: '',
          title: title,
          width: 460,
          child: Text(msg, style: const TextStyle(fontSize: 16, height: 1.4)),
          actions: [FxBtn('OK', () => Navigator.pop(d), autofocus: true, primary: true)],
        ),
      );

  Future<void> choose(
      String title, List<List<String>> opts, String cur, void Function(String) set) async {
    final v = await pickFx(context, title, opts, cur);
    if (v == null) return;
    set(v);
    await Cfg.save();
    if (mounted) setState(() {});
  }

  Widget sel(BuildContext dc, void Function(void Function()) set, String title,
          List<List<String>> opts, String cur, void Function(String) onPick) =>
      FxSelect(label(opts, cur), () async {
        final v = await pickFx(dc, title, opts, cur);
        if (v != null) set(() => onPick(v));
      });

  // ---- General Settings ----
  Future<void> general() async {
    final uaC = TextEditingController(text: ua['User-Agent'] ?? defaultUa);
    var load = Cfg.gs('cfg_load', 'detailed'),
        disp = Cfg.gs('cfg_disp', 'auto'),
        tf = Cfg.gs('cfg_time', '24');
    var auto = Cfg.autoLogin, start = Cfg.startScreen == 'live';
    await showDialog(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d2, set) => FxDialog(
          label: 'APP',
          title: 'General Settings',
          width: 640,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  fxLabel('Set User Agent'),
                  fxInput(uaC, defaultUa),
                ]),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  fxLabel('Select Your Preferred Language'),
                  FxSelect('English',
                      () => pickFx(d2, 'Language', const [['en', 'English']], 'en')),
                ]),
              ),
            ]),
            fxLabel('Loading Screen'),
            sel(d2, set, 'Loading Screen', _loadOpts, load, (v) => load = v),
            fxLabel('Display mode'),
            sel(d2, set, 'Display mode', _dispOpts, disp, (v) => disp = v),
            fxLabel('Time format'),
            sel(d2, set, 'Time format', _timeOpts, tf, (v) => tf = v),
            const SizedBox(height: 8),
            FxCheck('Auto login on startup', auto, (v) => set(() => auto = v)),
            FxCheck('Open Live TV on start', start, (v) => set(() => start = v)),
          ]),
          actions: [
            FxBtn('Cancel', () => Navigator.pop(d)),
            FxBtn('Save', () async {
              final u = uaC.text.trim();
              await Cfg.ps('cfg_ua', u);
              ua['User-Agent'] = u.isEmpty ? defaultUa : u;
              await Cfg.ps('cfg_load', load);
              await Cfg.ps('cfg_disp', disp);
              await Cfg.ps('cfg_time', tf);
              Cfg.autoLogin = auto;
              Cfg.startScreen = start ? 'live' : 'home';
              await Cfg.save();
              uiTick.value++;
              if (d.mounted) Navigator.pop(d);
            }, primary: true),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  // ---- Player Selection ----
  Future<void> playerSelect() async {
    String cur(String k) => Cfg.gs('pl_$k', Cfg.playerMode);
    await showDialog(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d2, set) {
          Widget col(List<String> k) => Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  fxLabel(k[1]),
                  FxSelect(label(_playerChoices, cur(k[0])), () async {
                    final v = await pickFx(d2, 'Player', _playerChoices, cur(k[0]));
                    if (v != null) {
                      await Cfg.ps('pl_${k[0]}', v);
                      set(() {});
                    }
                  }),
                ]),
              );
          Widget pair(int i) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                col(_kinds[i]),
                const SizedBox(width: 16),
                col(_kinds[i + 1]),
              ]);
          return FxDialog(
            label: 'DEFAULTS',
            title: 'Player Selection',
            width: 680,
            child: Column(children: [pair(0), pair(2), pair(4)]),
            actions: [
              FxBtn('Back', () => Navigator.pop(d)),
              FxBtn('Reset', () async {
                for (final k in _kinds) {
                  await Cfg.ps('pl_${k[0]}', 'builtin');
                }
                set(() {});
              }, primary: true),
            ],
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }

  // ---- Player Settings ----
  Future<void> playerSettings() async {
    var live = Cfg.gs('dec_live', 'auto'), vod = Cfg.gs('dec_vod', 'hw'), fit = Cfg.fit;
    var dbg = Cfg.gb('dbg_overlay', false), ls = Cfg.gb('sub_live', true), vs = Cfg.gb('sub_vod', true);
    await showDialog(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d2, set) => FxDialog(
          label: 'PLAYER',
          title: 'Player Settings',
          width: 640,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            fxLabel('Live Player Decoder'),
            sel(d2, set, 'Live Player Decoder', _liveDec, live, (v) => live = v),
            fxLabel('VOD Player Decoder'),
            sel(d2, set, 'VOD Player Decoder', _vodDec, vod, (v) => vod = v),
            fxLabel('Default video size'),
            sel(d2, set, 'Default video size', _fitOpts, fit, (v) => fit = v),
            const SizedBox(height: 8),
            FxCheck('Player debug overlay', dbg, (v) => set(() => dbg = v)),
            FxCheck('Live subtitles', ls, (v) => set(() => ls = v)),
            FxCheck('VOD subtitles', vs, (v) => set(() => vs = v)),
          ]),
          actions: [
            FxBtn('Cancel', () => Navigator.pop(d)),
            FxBtn('Save', () async {
              await Cfg.ps('dec_live', live);
              await Cfg.ps('dec_vod', vod);
              Cfg.fit = fit;
              await Cfg.save();
              await Cfg.pb('dbg_overlay', dbg);
              await Cfg.pb('sub_live', ls);
              await Cfg.pb('sub_vod', vs);
              if (d.mounted) Navigator.pop(d);
            }, primary: true),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  // ---- Multi-screen ----
  Future<int?> layoutChooser(BuildContext c, int cur) => showDialog<int>(
        context: c,
        builder: (d) => FxDialog(
          label: 'MULTI-SCREEN',
          title: 'Choose Multi-Screen Layout',
          width: 640,
          child: GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 1.35,
            children: [
              for (var i = 0; i < 6; i++)
                InkWell(
                  autofocus: i == cur,
                  onTap: () => Navigator.pop(d, i),
                  borderRadius: BorderRadius.circular(20),
                  focusColor: Colors.white12,
                  child: Container(
                    decoration: BoxDecoration(
                      color: fxFieldBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: i == cur ? accent : Colors.transparent, width: 2),
                    ),
                    child: Center(child: LayoutThumb(i, width: 84)),
                  ),
                ),
            ],
          ),
          actions: [FxBtn('Close', () => Navigator.pop(d))],
        ),
      );

  Future<void> multi() async {
    var pickN = Cfg.layout;
    await showDialog(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d2, set) => FxDialog(
          label: 'LAYOUT',
          title: 'Multi-Screen Settings',
          width: 600,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: const Color(0xFF222226), borderRadius: BorderRadius.circular(20)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Choose Multi-Screen Layout', style: TextStyle(fontSize: 17)),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: 150,
                    child: FxBtn('Select', () async {
                      final r = await layoutChooser(d2, pickN);
                      if (r != null) set(() => pickN = r);
                    }, primary: true),
                  ),
                ]),
              ),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                    color: const Color(0xFF15161C),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24)),
                child: LayoutThumb(pickN, width: 84),
              ),
            ]),
          ),
          actions: [
            FxBtn('Cancel', () => Navigator.pop(d)),
            FxBtn('Save', () async {
              await Cfg.ps('cfg_layout', '$pickN');
              if (d.mounted) Navigator.pop(d);
            }, primary: true),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  // ---- TMDB ----
  Future<void> tmdbDialog() async {
    var on = Cfg.gb('tmdb_on', true);
    final keyC = TextEditingController(text: Cfg.gs('tmdb_key'));
    await showDialog(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d2, set) => FxDialog(
          label: 'ARTWORK',
          title: 'TMDB Posters',
          width: 560,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FxCheck('Use TMDB for missing posters and cast photos', on, (v) => set(() => on = v),
                boxFirst: true),
            fxLabel('Custom API Key (optional)'),
            fxInput(keyC, 'Leave blank to use the app default'),
          ]),
          actions: [
            FxBtn('Cancel', () => Navigator.pop(d)),
            FxBtn('Save', () async {
              await Cfg.pb('tmdb_on', on);
              await Cfg.ps('tmdb_key', keyC.text.trim());
              if (d.mounted) Navigator.pop(d);
            }, primary: true),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  // ---- OpenSubtitles ----
  Future<void> subsDialog() async {
    var on = Cfg.gb('os_on', false), lang = Cfg.gs('os_lang', 'en');
    final userC = TextEditingController(text: Cfg.gs('os_user'));
    final passC = TextEditingController(text: Cfg.gs('os_pass'));
    final keyC = TextEditingController(text: Cfg.gs('os_key'));
    await showDialog(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d2, set) => FxDialog(
          label: 'SUBTITLES',
          title: 'OpenSubtitles',
          width: 600,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(
                'Search and download subtitles from OpenSubtitles inside the player. Enter your opensubtitles.com account below.',
                style: TextStyle(color: Colors.white70, height: 1.35)),
            const SizedBox(height: 8),
            FxCheck('Enable OpenSubtitles', on, (v) => set(() => on = v), boxFirst: true),
            fxLabel('Username'),
            fxInput(userC, 'opensubtitles.com username'),
            fxLabel('Password'),
            fxInput(passC, 'opensubtitles.com password', obscure: true),
            fxLabel('Subtitle language'),
            sel(d2, set, 'Subtitle language', _subLangs, lang, (v) => lang = v),
            fxLabel('Custom API Key (optional)'),
            fxInput(keyC, 'Leave blank to use the app default'),
          ]),
          actions: [
            FxBtn('Cancel', () => Navigator.pop(d)),
            FxBtn('Save', () async {
              await Cfg.pb('os_on', on);
              await Cfg.ps('os_user', userC.text.trim());
              await Cfg.ps('os_pass', passC.text);
              await Cfg.ps('os_lang', lang);
              await Cfg.ps('os_key', keyC.text.trim());
              if (d.mounted) Navigator.pop(d);
            }, primary: true),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  // ---- Automation ----
  Future<void> automation() async {
    var c1 = Cfg.gb('auto_content', true), c2 = Cfg.gb('auto_epg', true);
    await showDialog(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d2, set) => FxDialog(
          label: 'BACKGROUND TASKS',
          title: 'Automation',
          width: 540,
          child: Column(children: [
            FxCheck('Auto-Update Channels & Movies daily', c1, (v) => set(() => c1 = v), boxFirst: true),
            FxCheck('Auto-Update EPG', c2, (v) => set(() => c2 = v), boxFirst: true),
          ]),
          actions: [
            FxBtn('Cancel', () => Navigator.pop(d)),
            FxBtn('Save', () async {
              await Cfg.pb('auto_content', c1);
              await Cfg.pb('auto_epg', c2);
              if (d.mounted) Navigator.pop(d);
            }, primary: true),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  void version() => showDialog(
        context: context,
        builder: (d) => FxDialog(
          label: 'ABOUT',
          title: 'Version History',
          width: 560,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final v in _changelog)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('v${v[0]}${v[0] == appVersion ? '  (current)' : ''}',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: accent)),
                  const SizedBox(height: 4),
                  Text(v[1], style: const TextStyle(color: Colors.white70, height: 1.35)),
                ]),
              ),
          ]),
          actions: [FxBtn('Close', () => Navigator.pop(d), autofocus: true, primary: true)],
        ),
      );

  void needLogin() => info('Not ready', 'Please log in first.');

  List<_Item> items() {
    final allBuiltin = _kinds.every((k) => Cfg.gs('pl_${k[0]}', Cfg.playerMode) == 'builtin');
    final shift = Cfg.epgShift;
    final tmdbSub = Cfg.gb('tmdb_on', true)
        ? 'On · ${Cfg.gs('tmdb_key').trim().isEmpty ? 'default key' : 'custom key'}'
        : 'Off';
    final osSub = Cfg.gb('os_on', false) && Cfg.gs('os_user').isNotEmpty
        ? 'Enabled · ${Cfg.gs('os_user')}'
        : 'Not connected';
    return [
      _Item(Icons.tune, 'General Settings', 'Language, display and startup', general),
      _Item(Icons.play_circle_outline, 'Player Selection',
          allBuiltin ? 'ExoPlayer (Built-in)' : 'Customised', playerSelect),
      _Item(Icons.settings_suggest, 'Player Settings', 'Decoder, subtitles and debug', playerSettings),
      _Item(Icons.open_in_new, 'External Players', label(_extOpts, Cfg.externalApp),
          () => choose('External Players', _extOpts, Cfg.externalApp, (v) => Cfg.externalApp = v)),
      _Item(Icons.table_chart_outlined, 'Stream Format', label(_fmtOpts, Cfg.liveFormat),
          () => choose('Stream Format', _fmtOpts, Cfg.liveFormat, (v) => Cfg.liveFormat = v)),
      _Item(Icons.history, 'Catchup Stream Format', label(_cuOpts, Cfg.catchupFmt),
          () => choose('Catchup Stream Format', _cuOpts, Cfg.catchupFmt, (v) => Cfg.catchupFmt = v)),
      _Item(Icons.grid_view, 'Multi-screen', '${layoutRects(Cfg.layout).length} windows', multi),
      _Item(Icons.view_agenda_outlined, 'EPG Source', 'Where guide data comes from', () {
        final g = gSession;
        showDialog(
          context: context,
          builder: (d) => FxDialog(
            label: 'GUIDE',
            title: 'EPG Source',
            width: 480,
            child: const Text(
                'Guide data (Now / Next and the timeline) is loaded from your provider.',
                style: TextStyle(fontSize: 16, height: 1.4)),
            actions: [
              FxBtn('Close', () => Navigator.pop(d)),
              FxBtn('Open Timeline', () {
                Navigator.pop(d);
                if (g == null) return needLogin();
                Navigator.push(context, MaterialPageRoute(builder: (_) => EpgTimeline(g)));
              }, primary: true),
            ],
          ),
        );
      }),
      _Item(Icons.schedule, 'EPG Time Shift',
          shift == 0 ? 'Correct guide times' : '${shift > 0 ? '+' : ''}$shift hours',
          () => choose('EPG Time Shift', _shiftOpts, '$shift', (v) => Cfg.epgShift = int.tryParse(v) ?? 0)),
      _Item(Icons.refresh, 'EPG Timeline', 'How much guide to load',
          () => choose('EPG Timeline', _hoursOpts, Cfg.gs('epg_hours', '0'),
              (v) => Cfg.ps('epg_hours', v))),
      _Item(Icons.image_outlined, 'TMDB Posters', tmdbSub, tmdbDialog),
      _Item(Icons.closed_caption_outlined, 'OpenSubtitles', osSub, subsDialog),
      _Item(Icons.shield_outlined, 'Parental Control',
          Cfg.gs('pin').isNotEmpty ? 'PIN set' : 'Not set', () async {
        await parentalDialog(context);
        if (mounted) setState(() {});
      }),
      _Item(Icons.bolt, 'Automation', 'Daily background updates', automation),
      _Item(Icons.speed, 'Speed Test', 'Run now', () => showDialog(context: context, builder: (d) => const _SpeedDlg())),
      _Item(Icons.upload_outlined, 'Version History', appVersion, version),
    ];
  }

  @override
  Widget build(BuildContext c) {
    final list = items();
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(children: [
              logoImg(40),
              const Expanded(
                child: Column(children: [
                  Text('SETTINGS',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, letterSpacing: 1.5)),
                  Text('Configure your app preferences',
                      style: TextStyle(fontSize: 13, color: Colors.white60)),
                ]),
              ),
              rb(Icons.arrow_back, () => Navigator.pop(c)),
            ]),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, mainAxisExtent: 84),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final it = list[i];
                return FocusCard(
                  autofocus: i == 0,
                  radius: 18,
                  onTap: it.onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(0x33FF6A4D),
                        child: Icon(it.icon, color: accent, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(it.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w500)),
                            Text(it.sub,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14, color: Colors.white60)),
                          ],
                        ),
                      ),
                    ]),
                  ),
                );
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('Streamivo OTT Player - v$appVersion',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
          ),
        ]),
      ),
    );
  }
}
