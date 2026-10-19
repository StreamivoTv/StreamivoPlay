import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'core.dart';
import 'player.dart';

// ---------------- Channel picker (shared) ----------------
Future<It?> pickChannel(BuildContext c, Session s) async {
  if (s.live.total == 0) {
    try {
      await s.live.start();
    } catch (_) {}
  }
  if (!c.mounted) return null;
  return showDialog<It>(context: c, builder: (d) => _Picker(s.live.all));
}

class _Picker extends StatefulWidget {
  final List<It> all;
  const _Picker(this.all);
  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  String q = '';
  @override
  Widget build(BuildContext c) {
    final ql = q.toLowerCase().trim();
    final res = <It>[];
    for (final i in widget.all) {
      if (ql.isEmpty || i.ln.contains(ql)) {
        res.add(i);
        if (res.length >= 80) break;
      }
    }
    return Dialog(
      backgroundColor: card,
      child: SizedBox(
        width: 460,
        height: 340,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => q = v),
              decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search channel...',
                  border: OutlineInputBorder()),
            ),
          ),
          Expanded(
            child: widget.all.isEmpty
                ? const Center(child: Text('No channels loaded yet. Please wait and try again.'))
                : ListView.builder(
                    itemCount: res.length,
                    itemBuilder: (_, n) => ListTile(
                      dense: true,
                      title: Text(res[n].name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(context, res[n]),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }
}

// ---------------- Multiscreen (4 channels at once) ----------------
class MultiScreen extends StatefulWidget {
  final Session s;
  const MultiScreen(this.s, {super.key});
  @override
  State<MultiScreen> createState() => _MultiState();
}

class _MultiState extends State<MultiScreen> {
  final vc = List<VideoPlayerController?>.filled(4, null);
  final names = List<String>.filled(4, '');
  final busy = List<bool>.filled(4, false);
  final errs = List<String?>.filled(4, null);
  final gen = List<int>.filled(4, 0);
  int audio = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final n = int.tryParse('${widget.s.info['max_connections'] ?? 1}') ?? 1;
      if (mounted && n < 2) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Your plan allows $n connection(s). Extra screens may not play.')));
      }
    });
  }

  @override
  void dispose() {
    for (final c in vc) {
      c?.dispose();
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    super.dispose();
  }

  Future<void> assign(int k) async {
    final it = await pickChannel(context, widget.s);
    if (it == null || !mounted) return;
    await load(k, it);
  }

  Future<void> load(int k, It it) async {
    final my = ++gen[k];
    final old = vc[k];
    setState(() {
      vc[k] = null;
      busy[k] = true;
      errs[k] = null;
      names[k] = it.name;
    });
    await disposeLater(old);
    if (!mounted || my != gen[k]) return;
    final pi = livePiOf(widget.s, it.id, it.name);
    for (final url in [pi.url, pi.alt]) {
      if (url == null) continue;
      final c = VideoPlayerController.networkUrl(Uri.parse(url), httpHeaders: ua);
      try {
        await c.initialize().timeout(const Duration(seconds: 25));
        if (!mounted || my != gen[k]) {
          await c.dispose();
          return;
        }
        await c.setVolume(k == audio ? 1 : 0);
        await c.play();
        setState(() {
          vc[k] = c;
          busy[k] = false;
        });
        return;
      } catch (_) {
        try {
          await c.dispose();
        } catch (_) {}
      }
    }
    if (mounted && my == gen[k]) {
      setState(() {
        busy[k] = false;
        errs[k] = 'Unable to play this channel';
      });
    }
  }

  Future<void> clear(int k) async {
    gen[k]++;
    final old = vc[k];
    setState(() {
      vc[k] = null;
      busy[k] = false;
      names[k] = '';
    });
    await disposeLater(old);
  }

  void setAudio(int k) {
    audio = k;
    for (var i = 0; i < 4; i++) {
      vc[i]?.setVolume(i == k ? 1 : 0);
    }
    setState(() {});
  }

  Widget cell(int k) {
    final c = vc[k];
    final on = k == audio && c != null;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(3),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: on ? accent : Colors.white12, width: on ? 2 : 1),
        ),
        child: InkWell(
          onTap: () => c == null ? assign(k) : setAudio(k),
          child: Stack(fit: StackFit.expand, children: [
            if (c != null && c.value.isInitialized)
              Center(
                child: AspectRatio(
                  aspectRatio: c.value.aspectRatio <= 0 ? 16 / 9 : c.value.aspectRatio,
                  child: VideoPlayer(c),
                ),
              ),
            if (busy[k]) const Center(child: CircularProgressIndicator()),
            if (c == null && !busy[k])
              Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.add_circle_outline, size: 34, color: Colors.white54),
                  const SizedBox(height: 6),
                  Text(errs[k] ?? 'Add channel', style: const TextStyle(color: Colors.white54)),
                ]),
              ),
            if (c != null)
              Positioned(
                left: 8,
                top: 6,
                right: 8,
                child: Row(children: [
                  Expanded(
                    child: Text(names[k],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            shadows: [Shadow(blurRadius: 4, color: Colors.black)])),
                  ),
                  Icon(on ? Icons.volume_up : Icons.volume_off, size: 16),
                  const SizedBox(width: 8),
                  GestureDetector(onTap: () => assign(k), child: const Icon(Icons.swap_horiz, size: 18)),
                  const SizedBox(width: 8),
                  GestureDetector(onTap: () => clear(k), child: const Icon(Icons.close, size: 18)),
                ]),
              ),
          ]),
        ),
      ),
    );
  }

  Widget grid() {
    Widget r(List<int> ks, [int flex = 1]) =>
        Expanded(flex: flex, child: Row(children: [for (final k in ks) cell(k)]));
    switch (Cfg.layout) {
      case 1:
        return Column(children: [r([0], 3), r([1, 2, 3], 2)]);
      case 2:
        return Column(children: [r([0]), r([1, 2])]);
      case 3:
        return Column(children: [r([0, 1]), r([2])]);
      case 4:
        return SizedBox.expand(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [cell(0), cell(1)]));
      case 5:
        return Column(children: [r([0]), r([1])]);
      default:
        return Column(children: [r([0, 1]), r([2, 3])]);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(children: [
            grid(),
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Center(child: rb(Icons.arrow_back, () => Navigator.pop(c))),
            ),
          ]),
        ),
      );
}

// ---------------- EPG Timeline + Catch Up ----------------
String _two(int n) => n.toString().padLeft(2, '0');
String _hm(DateTime d) {
  if (!Cfg.h12) return '${_two(d.hour)}:${_two(d.minute)}';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${_two(d.minute)} ${d.hour < 12 ? 'AM' : 'PM'}';
}
const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _dm(DateTime d) => '${_wd[d.weekday - 1]} ${d.day} ${_mo[d.month - 1]}';

class EpgTimeline extends StatefulWidget {
  final Session s;
  final bool catchup;
  const EpgTimeline(this.s, {this.catchup = false, super.key});
  @override
  State<EpgTimeline> createState() => _EpgState();
}

class _EpgState extends State<EpgTimeline> {
  It? ch;
  bool loading = false;
  String? err;
  List<Map> rows = [];
  final sc = ScrollController();
  static const rowH = 66.0;

  int ts(dynamic v) => int.tryParse('$v') ?? 0;
  int get shiftSec => Cfg.epgShift * 3600;
  int get nowSec => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  @override
  void dispose() {
    sc.dispose();
    super.dispose();
  }

  Future<void> choose() async {
    final it = await pickChannel(context, widget.s);
    if (it == null || !mounted) return;
    setState(() {
      ch = it;
      loading = true;
      err = null;
      rows = [];
    });
    try {
      final m = await widget.s.infoOf('get_simple_data_table', '&stream_id=${it.id}');
      final l = m['epg_listings'];
      final out = <Map>[];
      if (l is List) {
        for (final e in l) {
          if (e is Map) out.add(e);
        }
      }
      out.sort((a, b) => ts(a['start_timestamp']).compareTo(ts(b['start_timestamp'])));
      final hrs = int.tryParse(Cfg.gs('epg_hours', '0')) ?? 0;
      final shown = hrs <= 0
          ? out
          : out.where((e) {
              final a = ts(e['start_timestamp']) + shiftSec, b = ts(e['stop_timestamp']) + shiftSec;
              return b > nowSec - hrs * 3600 && a < nowSec + hrs * 3600;
            }).toList();
      if (!mounted) return;
      setState(() {
        rows = shown;
        loading = false;
      });
      var cur = shown.indexWhere((e) =>
          ts(e['start_timestamp']) + shiftSec <= nowSec && ts(e['stop_timestamp']) + shiftSec > nowSec);
      if (cur < 0) cur = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (sc.hasClients) sc.jumpTo((cur > 0 ? cur - 1 : 0) * rowH);
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          err = 'Could not load the guide for this channel.';
        });
      }
    }
  }

  void open(Map e) {
    final start = ts(e['start_timestamp']), stop = ts(e['stop_timestamp']);
    final title = b64d('${e['title'] ?? ''}');
    final desc = b64d('${e['description'] ?? ''}');
    final isNow = start + shiftSec <= nowSec && stop + shiftSec > nowSec;
    final past = stop + shiftSec <= nowSec;
    final c = ch!;
    if (isNow) {
      playItems(context, widget.s, [livePiOf(widget.s, c.id, c.name)], 0, true, kind: 'guide');
      return;
    }
    final arch = '${e['has_archive']}' == '1';
    if (past && (arch || widget.catchup)) {
      final mins = ((stop - start) / 60).ceil().clamp(1, 600).toInt();
      final url = widget.s.catchupUrl(c.id, '${e['start'] ?? ''}', mins);
      playItems(context, widget.s, [Pi(title.isEmpty ? c.name : title, url)], 0, false,
          kind: 'catchup');
      return;
    }
    final s0 = DateTime.fromMillisecondsSinceEpoch((start + shiftSec) * 1000);
    final s1 = DateTime.fromMillisecondsSinceEpoch((stop + shiftSec) * 1000);
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title.isEmpty ? 'Programme' : title),
        content: Text('${_dm(s0)}  ${_hm(s0)} - ${_hm(s1)}'
            '${desc.isEmpty ? '' : '\n\n$desc'}'
            '${past ? '\n\nCatch-up is not available for this programme.' : ''}'),
        actions: [
          TextButton(autofocus: true, onPressed: () => Navigator.pop(d), child: const Text('OK'))
        ],
      ),
    );
  }

  Widget row(Map e) {
    final start = ts(e['start_timestamp']), stop = ts(e['stop_timestamp']);
    final s0 = DateTime.fromMillisecondsSinceEpoch((start + shiftSec) * 1000);
    final s1 = DateTime.fromMillisecondsSinceEpoch((stop + shiftSec) * 1000);
    final isNow = start + shiftSec <= nowSec && stop + shiftSec > nowSec;
    final past = stop + shiftSec <= nowSec;
    final arch = '${e['has_archive']}' == '1' || widget.catchup;
    final title = b64d('${e['title'] ?? ''}');
    return SizedBox(
      height: rowH,
      child: ListTile(
        dense: true,
        selected: isNow,
        selectedTileColor: Colors.white10,
        selectedColor: accent,
        leading: SizedBox(
          width: Cfg.h12 ? 150 : 86,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_dm(s0), style: const TextStyle(fontSize: 11, color: Colors.white54)),
            Text('${_hm(s0)} - ${_hm(s1)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ),
        title: Text(title.isEmpty ? '(No title)' : title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: isNow ? const Text('LIVE NOW') : null,
        trailing: isNow
            ? const Icon(Icons.live_tv)
            : (past && arch ? const Icon(Icons.history, color: accent) : null),
        onTap: () => open(e),
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    Widget body;
    if (ch == null) {
      body = Center(
        child: FilledButton.icon(
            onPressed: choose, icon: const Icon(Icons.search), label: const Text('Choose a channel')),
      );
    } else if (loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (err != null) {
      body = Center(child: Text(err!));
    } else if (rows.isEmpty) {
      body = const Center(child: Text('No guide data for this channel.'));
    } else {
      body = ListView.builder(
        controller: sc,
        itemExtent: rowH,
        itemCount: rows.length,
        itemBuilder: (_, n) => row(rows[n]),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(children: [
              rb(Icons.arrow_back, () => Navigator.pop(c)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.catchup ? 'CATCH UP' : 'EPG TIMELINE',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  Text(
                      ch == null
                          ? 'Pick a channel to see its guide'
                          : '${ch!.name}   (time shift ${Cfg.epgShift >= 0 ? '+' : ''}${Cfg.epgShift} h)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: Colors.white60)),
                ]),
              ),
              rb(Icons.swap_horiz, choose),
            ]),
          ),
          Expanded(child: body),
        ]),
      ),
    );
  }
}
