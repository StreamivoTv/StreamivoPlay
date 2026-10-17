import 'package:flutter/material.dart';
import 'core.dart';

class _Item {
  final IconData icon;
  final String title, sub;
  final VoidCallback onTap;
  _Item(this.icon, this.title, this.sub, this.onTap);
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsPage> {
  Future<String?> pick(String title, List<List<String>> opts, String cur) => showDialog<String>(
        context: context,
        builder: (d) => SimpleDialog(
          title: Text(title),
          children: [
            for (final o in opts)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(d, o[0]),
                child: Row(children: [
                  Icon(o[0] == cur ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: o[0] == cur ? accent : Colors.white54),
                  const SizedBox(width: 12),
                  Expanded(child: Text(o[1])),
                ]),
              ),
          ],
        ),
      );

  void info(String title, String msg) => showDialog(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(title),
          content: Text(msg),
          actions: [
            TextButton(autofocus: true, onPressed: () => Navigator.pop(d), child: const Text('OK'))
          ],
        ),
      );

  void soon(String title) => info(title, 'This feature is coming soon.');

  Future<void> general() async {
    await showDialog(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d2, set) => SimpleDialog(
          title: const Text('General Settings'),
          children: [
            SimpleDialogOption(
              onPressed: () async {
                Cfg.autoLogin = !Cfg.autoLogin;
                await Cfg.save();
                set(() {});
              },
              child: Text('Auto login on startup: ${Cfg.autoLogin ? 'On' : 'Off'}'),
            ),
            SimpleDialogOption(
              onPressed: () async {
                Cfg.startScreen = Cfg.startScreen == 'live' ? 'home' : 'live';
                await Cfg.save();
                set(() {});
              },
              child: Text('Start screen: ${Cfg.startScreen == 'live' ? 'Live TV' : 'Home'}'),
            ),
            const SimpleDialogOption(child: Text('Language: English')),
            const SimpleDialogOption(child: Text('Theme: Dark')),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> choose(String title, List<List<String>> opts, String cur, void Function(String) set) async {
    final v = await pick(title, opts, cur);
    if (v == null) return;
    set(v);
    await Cfg.save();
    if (mounted) setState(() {});
  }

  String label(List<List<String>> opts, String key) {
    for (final o in opts) {
      if (o[0] == key) return o[1];
    }
    return key;
  }

  static const playerOpts = [
    ['builtin', 'Built-in'],
    ['external', 'External player'],
  ];
  static const extOpts = [
    ['ask', 'Ask every time'],
    ['vlc', 'VLC'],
    ['mx', 'MX Player'],
  ];
  static const fmtOpts = [
    ['default', 'Default'],
    ['m3u8', 'HLS (.m3u8)'],
    ['ts', 'MPEGTS (.ts)'],
  ];
  static const fitOpts = [
    ['contain', 'Fit'],
    ['cover', 'Zoom'],
    ['fill', 'Stretch'],
  ];

  List<_Item> items() => [
        _Item(Icons.tune, 'General Settings', 'Language, theme and startup', general),
        _Item(Icons.play_circle_outline, 'Player Selection', label(playerOpts, Cfg.playerMode),
            () => choose('Player Selection', playerOpts, Cfg.playerMode, (v) => Cfg.playerMode = v)),
        _Item(Icons.settings_suggest, 'Player Settings', 'Video size: ${label(fitOpts, Cfg.fit)}',
            () => choose('Default video size', fitOpts, Cfg.fit, (v) => Cfg.fit = v)),
        _Item(Icons.open_in_new, 'External Players', label(extOpts, Cfg.externalApp),
            () => choose('External Players', extOpts, Cfg.externalApp, (v) => Cfg.externalApp = v)),
        _Item(Icons.table_chart_outlined, 'Stream Format', label(fmtOpts, Cfg.liveFormat),
            () => choose('Stream Format', fmtOpts, Cfg.liveFormat, (v) => Cfg.liveFormat = v)),
        _Item(Icons.history, 'Catchup Stream Format', 'Coming soon', () => soon('Catchup Stream Format')),
        _Item(Icons.grid_view, 'Multi-screen', 'Coming soon', () => soon('Multi-screen')),
        _Item(Icons.view_agenda_outlined, 'EPG Source', 'Where guide data comes from',
            () => info('EPG Source', 'Guide data (Now / Next) is loaded from your provider.')),
        _Item(Icons.schedule, 'EPG Time Shift', 'Coming soon', () => soon('EPG Time Shift')),
        _Item(Icons.timeline, 'EPG Timeline', 'Coming soon', () => soon('EPG Timeline')),
      ];

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
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)),
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
                  radius: 16,
                  onTap: it.onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(0x33FF6A4D),
                        child: Icon(it.icon, color: accent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(it.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                            Text(it.sub,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, color: Colors.white60)),
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
            child: Text('Streamivo v1.0.0', style: TextStyle(color: Colors.white38, fontSize: 12)),
          ),
        ]),
      ),
    );
  }
}
