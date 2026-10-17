import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'core.dart';

// Opens the built-in player, or an external app when selected in Settings.
// Returns true when the built-in player was used.
Future<bool> playItems(BuildContext c, Session s, List<Pi> list, int idx, bool live,
    {ValueChanged<int>? onIndex, VideoPlayerController? initial}) async {
  if (Cfg.playerMode == 'external') {
    final pi = list[idx];
    final pkg = Cfg.externalApp == 'vlc'
        ? 'org.videolan.vlc'
        : (Cfg.externalApp == 'mx' ? 'com.mxtech.videoplayer.ad' : '');
    final ok = await nat('openExternal', {'url': pi.url, 'title': pi.title, 'pkg': pkg});
    if (ok == true) return false;
    if (c.mounted) {
      ScaffoldMessenger.of(c).showSnackBar(
          const SnackBar(content: Text('External player not found. Using the built-in player.')));
    }
  }
  if (!c.mounted) return false;
  await Navigator.push(
      c, MaterialPageRoute(builder: (_) => Player(s, list, idx, live, onIndex: onIndex, initial: initial)));
  return true;
}

class Player extends StatefulWidget {
  final Session s;
  final List<Pi> items;
  final int index;
  final bool live;
  final ValueChanged<int>? onIndex;
  final VideoPlayerController? initial;
  const Player(this.s, this.items, this.index, this.live,
      {this.onIndex, this.initial, super.key});
  @override
  State<Player> createState() => _PlayerState();
}

class _PlayerState extends State<Player> {
  VideoPlayerController? vc;
  late int idx;
  String? err;
  bool show = true, loading = true, muted = false;
  Timer? hideT, osdT;
  int gen = 0, rep = 0;
  late BoxFit fit;
  String? osd;
  IconData osdIcon = Icons.info;
  double volume = 0.5, bright = 0.5, accum = 0, speed = 1.0;
  int dragMode = 0; // 1 = volume (left side), 2 = brightness (right side)
  bool hOn = false;
  double hdx = 0;
  Duration hBase = Duration.zero;
  int hSec = 0;
  List<String> epg = [];
  String? menu; // null | main | speed | audio | fit
  List audioTracks = [];
  String audioSel = '';

  Pi get cur => widget.items[idx];

  @override
  void initState() {
    super.initState();
    idx = widget.index;
    fit = fitOf(Cfg.fit);
    inPip.addListener(onPip);
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    nat('getVolume').then((v) {
      if (v is double) volume = v;
    });
    nat('getBrightness').then((v) {
      if (v is double) bright = v;
    });
    loadEpg();
    final pre = widget.initial;
    if (pre != null && pre.value.isInitialized) {
      // Continue the stream that is already playing (no reload)
      vc = pre;
      loading = false;
      pre.addListener(() {
        if (mounted) setState(() {});
      });
      if (!pre.value.isPlaying) pre.play();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) poke();
      });
    } else {
      play(cur.url, cur.alt);
    }
  }

  @override
  void dispose() {
    gen++;
    inPip.removeListener(onPip);
    hideT?.cancel();
    osdT?.cancel();
    vc?.dispose();
    WakelockPlus.disable();
    nat('resetBrightness');
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    super.dispose();
  }

  void onPip() {
    if (mounted) setState(() {});
  }

  void toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));
  }

  void loadEpg() {
    epg = [];
    if (!widget.live || cur.id == null) return;
    final id = cur.id!;
    widget.s.epg(id).then((l) {
      if (mounted && cur.id == id) setState(() => epg = l);
    });
  }

  String lastErr = '';

  Future<void> play(String url, String? alt, {int attempt = 0}) async {
    final my = ++gen;
    final old = vc;
    setState(() {
      vc = null;
      loading = true;
      err = null;
    });
    await disposeLater(old);
    if (!mounted || my != gen) return;
    final real = widget.live ? url : await resolveFinal(url);
    if (!mounted || my != gen) return;
    final c = VideoPlayerController.networkUrl(Uri.parse(real),
        httpHeaders: attempt == 1 ? const <String, String>{} : ua);
    try {
      await c.initialize().timeout(const Duration(seconds: 40));
      if (!mounted || my != gen) {
        await c.dispose();
        return;
      }
      c.addListener(() {
        if (mounted) setState(() {});
      });
      await c.play();
      if (speed != 1.0 && !widget.live) await c.setPlaybackSpeed(speed);
      if (muted) await c.setVolume(0);
      setState(() {
        vc = c;
        loading = false;
      });
      poke();
    } catch (e) {
      try {
        await c.dispose();
      } catch (_) {}
      if (!mounted || my != gen) return;
      lastErr = '$e';
      if (attempt == 0 && !widget.live) {
        // second try without custom headers
        play(url, alt, attempt: 1);
      } else if (alt != null) {
        play(alt, null);
      } else {
        var m = lastErr.replaceAll('\n', ' ');
        if (m.length > 160) m = m.substring(0, 160);
        setState(() {
          loading = false;
          err = 'Unable to play this stream. Please try again.\n$m';
        });
      }
    }
  }

  void poke() {
    setState(() => show = true);
    hideT?.cancel();
    hideT = Timer(const Duration(seconds: 5), () {
      if (mounted && menu == null && vc?.value.isPlaying == true) setState(() => show = false);
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

  void mute() {
    muted = !muted;
    vc?.setVolume(muted ? 0 : 1);
    showOsd(muted ? Icons.volume_off : Icons.volume_up, muted ? 'Muted' : 'Sound on');
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
    loadEpg();
    play(cur.url, cur.alt);
  }

  void setFit(BoxFit f) {
    setState(() {
      fit = f;
      menu = 'main';
    });
  }

  void cycleFit() {
    final f = fit == BoxFit.contain
        ? BoxFit.cover
        : (fit == BoxFit.cover ? BoxFit.fill : BoxFit.contain);
    setState(() => fit = f);
    showOsd(Icons.fit_screen, f == BoxFit.contain ? 'Fit' : (f == BoxFit.cover ? 'Zoom' : 'Stretch'));
    poke();
  }

  String get fitName => fit == BoxFit.contain ? 'Fit' : (fit == BoxFit.cover ? 'Zoom' : 'Stretch');

  void setSpeed(double x) {
    if (widget.live) {
      toast('Playback speed is not available for live streams.');
      return;
    }
    vc?.setPlaybackSpeed(x);
    setState(() {
      speed = x;
      menu = 'main';
    });
  }

  // ---- audio tracks (works only if the installed player engine supports it) ----
  String trackId(dynamic t) {
    try {
      return '${(t as dynamic).id}';
    } catch (_) {
      return '';
    }
  }

  String trackLabel(dynamic t) {
    try {
      final d = t as dynamic;
      final l = '${d.label ?? ''}'.trim();
      final g = '${d.language ?? ''}'.trim();
      return l.isNotEmpty ? l : (g.isNotEmpty ? g : 'Track ${trackId(t)}');
    } catch (_) {
      return 'Track';
    }
  }

  Future<void> openAudio() async {
    final v = vc;
    if (v == null) return;
    try {
      final tr = await (v as dynamic).getAudioTracks();
      if (tr is List && tr.isNotEmpty) {
        setState(() {
          audioTracks = tr;
          menu = 'audio';
        });
      } else {
        toast('No other audio tracks found in this stream.');
      }
    } catch (_) {
      toast('Audio track selection is not supported on this device.');
    }
  }

  Future<void> pickAudio(dynamic t) async {
    final v = vc;
    if (v == null) return;
    try {
      if (t != null) {
        await (v as dynamic).selectAudioTrack(trackId(t));
        audioSel = trackId(t);
      } else {
        audioSel = '';
      }
      setState(() => menu = 'main');
    } catch (_) {
      toast('Could not switch the audio track.');
    }
  }

  // ---- touch gestures ----
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
    hOn = !widget.live && vc != null && menu == null;
    hdx = 0;
    hSec = 0;
    hBase = vc?.value.position ?? Duration.zero;
  }

  void hUpdate(DragUpdateDetails d, double w) {
    final v = vc;
    if (!hOn || v == null) return;
    hdx += d.delta.dx;
    hSec = (hdx / w * 240).round(); // a full-width swipe = 4 minutes
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
    if (menu != null) return KeyEventResult.ignored;
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    rep = e is KeyDownEvent ? 0 : rep + 1;
    final k = e.logicalKey;
    final step = 10 * (1 + rep ~/ 6); // faster while the button is held
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
    } else if (k == LogicalKeyboardKey.contextMenu) {
      if (e is KeyDownEvent) setState(() => menu = 'main');
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ---- UI ----
  int bufPct(VideoPlayerController v) {
    final b = v.value.buffered;
    if (b.isEmpty) return 0;
    final ahead = b.last.end - v.value.position;
    return (ahead.inMilliseconds / 100).clamp(0, 100).round();
  }

  Widget ctl(IconData i, VoidCallback? f, {double size = 26}) =>
      IconButton(icon: Icon(i), iconSize: size, onPressed: f);

  Widget overlay(VideoPlayerController? v) {
    final size = v?.value.size;
    final live = widget.live;
    final playing = v?.value.isPlaying == true;
    final now = epg.isNotEmpty && epg[0].isNotEmpty ? epg[0] : 'No Program Found';
    final next = epg.length > 1 && epg[1].isNotEmpty ? epg[1] : 'No Program Found';
    return ExcludeFocus(
      child: Column(children: [
        Container(
          decoration: const BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black87, Colors.transparent])),
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 16),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
            if (live)
              Container(
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration:
                    BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(6)),
                child: const Text('LIVE', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            Expanded(
              child: Text(cur.title,
                  textAlign: TextAlign.center,
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
          decoration: const BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent])),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (live) ...[
              Text('Now: $now',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.orange, fontSize: 16)),
              Text('Next: $next',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 4),
            ],
            Row(children: [
              Text(live ? '00:00' : fmt(v?.value.position ?? Duration.zero),
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 10),
              Expanded(
                child: live
                    ? Container(height: 3, color: Colors.white)
                    : (v == null
                        ? const SizedBox()
                        : VideoProgressIndicator(v,
                            allowScrubbing: true,
                            colors: const VideoProgressColors(playedColor: accent))),
              ),
              const SizedBox(width: 10),
              live
                  ? const Text('Live',
                      style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))
                  : Text(fmt(v?.value.duration ?? Duration.zero),
                      style: const TextStyle(fontSize: 13)),
            ]),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              ctl(Icons.fit_screen, cycleFit),
              ctl(Icons.picture_in_picture_alt, () => nat('enterPip')),
              ctl(Icons.skip_previous, () => zap(-1), size: 30),
              ctl(Icons.replay_10, live ? null : () => seek(-10)),
              IconButton(
                  iconSize: 54,
                  icon: Icon(playing ? Icons.pause_circle_outline : Icons.play_circle_outline),
                  onPressed: toggle),
              ctl(Icons.forward_10, live ? null : () => seek(10)),
              ctl(Icons.skip_next, () => zap(1), size: 30),
              ctl(muted ? Icons.volume_off : Icons.volume_up, mute),
              ctl(Icons.settings, () => setState(() => menu = 'main')),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget menuPanel(double h) {
    Widget hdr(String t) => ListTile(
          dense: true,
          leading: const Icon(Icons.arrow_back, size: 20),
          title: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)),
          onTap: () => setState(() => menu = 'main'),
        );
    Widget opt(String t, bool on, VoidCallback f, {bool first = false}) => ListTile(
          dense: true,
          autofocus: first,
          leading: on ? const Icon(Icons.check, size: 20) : const SizedBox(width: 20),
          title: Text(t),
          onTap: f,
        );
    Widget row(IconData i, String t, String v, VoidCallback f, {bool first = false}) => ListTile(
          dense: true,
          autofocus: first,
          leading: Icon(i, color: Colors.orange),
          title: Text(t),
          trailing: Text(v, style: const TextStyle(color: Colors.white60)),
          onTap: f,
        );
    final List<Widget> rows;
    switch (menu) {
      case 'speed':
        rows = [
          hdr('Playback speed'),
          for (final x in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
            opt(x == 1.0 ? 'Normal' : '${x}x', speed == x, () => setSpeed(x), first: x == 1.0),
        ];
        break;
      case 'audio':
        rows = [
          hdr('Audio track'),
          opt('Auto', audioSel.isEmpty, () => pickAudio(null), first: true),
          for (final t in audioTracks) opt(trackLabel(t), audioSel == trackId(t), () => pickAudio(t)),
        ];
        break;
      case 'fit':
        rows = [
          hdr('Video size'),
          opt('Fit', fit == BoxFit.contain, () => setFit(BoxFit.contain), first: true),
          opt('Zoom', fit == BoxFit.cover, () => setFit(BoxFit.cover)),
          opt('Stretch', fit == BoxFit.fill, () => setFit(BoxFit.fill)),
        ];
        break;
      default:
        rows = [
          row(Icons.speed, 'Playback speed', speed == 1.0 ? 'Normal' : '${speed}x',
              () => setState(() => menu = 'speed'),
              first: true),
          row(Icons.music_note, 'Audio track', audioSel.isEmpty ? 'Auto' : 'Selected', openAudio),
          row(Icons.closed_caption, 'Subtitles', 'Auto',
              () => toast('No subtitle tracks found in this stream.')),
          row(Icons.aspect_ratio, 'Video size', fitName, () => setState(() => menu = 'fit')),
        ];
    }
    final maxH = h - 110 < 120 ? 120.0 : h - 110;
    return Positioned(
      right: 16,
      bottom: 90,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 340, maxHeight: maxH),
        child: Material(
          color: const Color(0xF2202026),
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: rows)),
        ),
      ),
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
    final pip = inPip.value;
    final hasErr = err != null || v?.value.hasError == true;
    final h = MediaQuery.of(c).size.height;
    return PopScope(
      canPop: menu == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && menu != null) setState(() => menu = null);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          autofocus: true,
          onKeyEvent: onKey,
          child: LayoutBuilder(
            builder: (ctx, cons) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (menu != null) {
                  setState(() => menu = null);
                } else if (show) {
                  setState(() => show = false);
                } else {
                  poke();
                }
              },
              onVerticalDragStart: (d) => vStart(d, cons.maxWidth),
              onVerticalDragUpdate: (d) => vUpdate(d, cons.maxHeight),
              onHorizontalDragStart: hStart,
              onHorizontalDragUpdate: (d) => hUpdate(d, cons.maxWidth),
              onHorizontalDragEnd: (_) => hEnd(),
              child: Stack(children: [
                if (v != null && v.value.isInitialized) video(v),
                if (loading || (v != null && v.value.isBuffering))
                  const Center(child: CircularProgressIndicator()),
                if (hasErr)
                  Center(
                      child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Text(err ?? 'A stream error occurred.',
                              textAlign: TextAlign.center))),
                if (!pip && (show || hasErr)) Positioned.fill(child: overlay(v)),
                if (!pip && osd != null)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      decoration: BoxDecoration(
                          color: Colors.black87, borderRadius: BorderRadius.circular(12)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(osdIcon),
                        const SizedBox(width: 10),
                        Text(osd!,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ]),
                    ),
                  ),
                if (!pip && menu != null) menuPanel(h),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
