import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'dart:math' as math;
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart'
    show VideoPlayerPlatform;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'core.dart';

// ---- decoder choice (applied through the fvp engine before a video is opened) ----
String _appliedDec = 'auto';
int _activePlayers = 0;

List<String> _decList(String m) => m == 'hw'
    ? ['AMediaCodec']
    : (m == 'sw' ? ['FFmpeg', 'dav1d'] : ['AMediaCodec', 'FFmpeg', 'dav1d']);

void _applyDecoder(String m) {
  if (m == _appliedDec) return;
  try {
    fvp.registerWith(options: {
      'platforms': ['android'],
      'video.decoders': _decList(m),
      'audio.decoders': ['FFmpeg'],
      // look at less of the stream before starting playback (faster start)
      'player': {'avformat.probesize': '1000000', 'avformat.analyzeduration': '1000000'},
    });
    _appliedDec = m;
  } catch (_) {}
}

// Opens the built-in player, or an external app when selected in Settings.
// Returns true when the built-in player was used.
Future<bool> playItems(BuildContext c, Session s, List<Pi> list, int idx, bool live,
    {ValueChanged<int>? onIndex, VideoPlayerController? initial, String kind = '', bool keepAlive = false}) async {
  final kd = kind.isEmpty ? (live ? 'live' : 'movie') : kind;
  if (Cfg.gs('pl_$kd', Cfg.playerMode) == 'external') {
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
      c,
      MaterialPageRoute(
          builder: (_) => Player(s, list, idx, live,
              onIndex: onIndex, initial: initial, kind: kd, keepAlive: keepAlive)));
  return true;
}

// Stream handed back by the player to the screen that opened it (see Player.keepAlive)
VideoPlayerController? liveHandBack;

class Player extends StatefulWidget {
  final Session s;
  final List<Pi> items;
  final int index;
  final bool live;
  final String kind;
  final ValueChanged<int>? onIndex;
  final VideoPlayerController? initial;
  // true: when the player closes, the running stream is given back to the list screen
  // (through liveHandBack) instead of being closed, so the list does not reload it
  final bool keepAlive;
  const Player(this.s, this.items, this.index, this.live,
      {this.onIndex, this.initial, this.kind = '', this.keepAlive = false, super.key});
  @override
  State<Player> createState() => _PlayerState();
}

class _PlayerState extends State<Player> {
  VideoPlayerController? vc;
  late int idx;
  String? err;
  bool show = true, loading = true, muted = false, scrub = false;
  double scrubVal = 0;
  Timer? hideT, osdT, pillT, speedT;
  int gen = 0, rep = 0;
  int sizeMode = 0; // 0 Fit | 1 Fixed Width | 2 Fixed Height | 3 Fill Parent
  static const sizeNames = ['Fit', 'Fixed Width', 'Fixed Height', 'Fill Parent'];
  static const sizeFits = [BoxFit.contain, BoxFit.fitWidth, BoxFit.fitHeight, BoxFit.fill];
  String? osd, pill;
  IconData osdIcon = Icons.info;
  int vol30 = 10, bri30 = 20; // FileX style 0-30 scales
  double gain = 1.0, accum = 0, speed = 1.0;
  bool osdLvl = false;
  Color osdCol = const Color(0xFFD81B4A);
  int dragMode = 0; // 1 = volume (right side), 2 = brightness (left side)
  bool hOn = false;
  double hdx = 0;
  Duration hBase = Duration.zero;
  int hSec = 0;
  List<String> epg = [];
  String? menu; // null | main | speed | audio | sub | repeat | dec

  // tracks / subtitles / repeat / decoder
  List<Map<String, String>> audioTracks = [], subTracks = [];
  String audioSel = '', audioLabel = '';
  String subSel = 'auto', subLabel = '';
  String repMode = 'off'; // off | one | ab
  Duration? abA, abB, resumeAt;
  String? decOverride;
  bool decRetried = false;

  // loading box (id, speed, percent)
  double kbps = -1;
  int pctHold = 0; // shown percent only goes up while one load/buffer is running
  DateTime loadStart = DateTime.now();
  bool wasBusy = false;
  Duration lastBuf = Duration.zero;
  DateTime lastAt = DateTime.now();

  Pi get cur => widget.items[idx];

  @override
  void initState() {
    super.initState();
    idx = widget.index;
    sizeMode = 3; // always open in Fill Parent (user can still change it from the player)
    subSel = Cfg.gb(widget.live ? 'sub_live' : 'sub_vod', true) ? 'auto' : 'off';
    uiBusy++; // background indexing waits while the player is open
    _activePlayers++;
    inPip.addListener(onPip);
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    nat('getVolume').then((v) {
      if (v is double) vol30 = (v * 15).round().clamp(0, 15).toInt();
    });
    nat('getBrightness').then((v) {
      if (v is double) bri30 = (math.pow(v.clamp(0.0, 1.0), 1 / 0.6) * 30).round().clamp(0, 30).toInt();
    });
    speedT = Timer.periodic(const Duration(seconds: 1), (_) => sampleSpeed());
    loadEpg();
    final pre = widget.initial;
    if (pre != null && pre.value.isInitialized) {
      // Continue the stream that is already playing (no reload)
      vc = pre;
      loading = false;
      pre.addListener(onVc);
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
    uiBusy--;
    _activePlayers--;
    inPip.removeListener(onPip);
    hideT?.cancel();
    osdT?.cancel();
    pillT?.cancel();
    speedT?.cancel();
    final lv = vc;
    if (widget.keepAlive && lv != null && lv.value.isInitialized && !lv.value.hasError && err == null) {
      lv.removeListener(onVc);
      liveHandBack = lv;
    } else {
      lv?.dispose();
    }
    WakelockPlus.enable(); // keep the screen on after the player closes too
    nat('resetBrightness');
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (_appliedDec != 'auto') {
      // give the old video time to close, then put the engine back to its normal setting
      Future<void>.delayed(const Duration(milliseconds: 1500), () {
        if (_activePlayers == 0) _applyDecoder('auto');
      });
    }
    super.dispose();
  }

  void onPip() {
    if (mounted) setState(() {});
  }

  void onVc() {
    if (!mounted) return;
    final v = vc;
    if (repMode == 'ab' && v != null && abA != null && abB != null) {
      if (v.value.position >= abB!) v.seekTo(abA!);
    }
    setState(() {});
  }

  void showPill(String m) {
    if (!mounted) return;
    setState(() => pill = m);
    pillT?.cancel();
    pillT = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => pill = null);
    });
  }

  void toast(String m) => showPill(m);

  void loadEpg() {
    epg = [];
    if (!widget.live || cur.id == null) return;
    final id = cur.id!;
    widget.s.epg(id).then((l) {
      if (mounted && cur.id == id) setState(() => epg = l);
    });
  }

  // ---- download speed (estimated from how fast the buffer grows) ----
  void sampleSpeed() {
    if (!mounted) return;
    final v = vc;
    final now = DateTime.now();
    if (v == null || !v.value.isInitialized || v.value.buffered.isEmpty) {
      lastAt = now;
      return;
    }
    final end = v.value.buffered.last.end;
    final dur = v.value.duration.inMilliseconds;
    final secs = now.difference(lastAt).inMilliseconds / 1000.0;
    final grownMs = (end - lastBuf).inMilliseconds;
    if (secs > 0) {
      double? inst;
      if (!widget.live && resolvedSize > 0 && dur > 0) {
        inst = (grownMs > 0 ? grownMs : 0) * (resolvedSize / dur) / secs / 1024.0;
      } else {
        // live: no file size, so estimate from how many seconds of video arrived
        // and a typical bitrate for the picture height
        final hh = v.value.size.height;
        final rate = hh >= 1000 ? 650.0 : (hh >= 700 ? 420.0 : (hh >= 500 ? 220.0 : 120.0)); // KB per video second
        final got = (grownMs > 0 ? grownMs : 0) / 1000.0;
        inst = got * rate / secs;
      }
      if (inst != null) kbps = kbps < 0 ? inst : (kbps * 0.5 + inst * 0.5);
    }
    lastBuf = end;
    lastAt = now;
    if (loading || v.value.isBuffering) setState(() {});
  }

  String get speedText {
    if (kbps <= 0) return '0.0 KB/s';
    return kbps >= 1024
        ? '${(kbps / 1024).toStringAsFixed(2)} MB/s'
        : '${kbps.toStringAsFixed(1)} KB/s';
  }

  String lastErr = '';

  String get decMode {
    final k = widget.live ? 'dec_live' : 'dec_vod';
    final chosen = Cfg.gs('${k}_p', '');
    if (chosen.isNotEmpty) return chosen;
    final st = Cfg.gs(k, widget.live ? 'auto' : 'hw');
    // "hw" is the stored default: hardware decoder first (engine default), no forced switch
    return st == 'hw' ? 'hwdef' : st;
  }

  String get decShown {
    switch (decMode) {
      case 'hw':
      case 'hwdef':
        return 'Hardware';
      case 'sw':
        return 'Software';
      default:
        return 'Auto';
    }
  }

  Future<void> play(String url, String? alt, {int attempt = 0}) async {
    final my = ++gen;
    final old = vc;
    setState(() {
      vc = null;
      loading = true;
      err = null;
      kbps = -1;
      pctHold = 0;
      loadStart = DateTime.now();
      lastBuf = Duration.zero;
    });
    await disposeLater(old);
    if (!mounted || my != gen) return;
    final real = widget.live ? url : await resolveFinal(url);
    if (!mounted || my != gen) return;
    final dm = decOverride ?? decMode;
    _applyDecoder(dm == 'hwdef' ? 'auto' : dm);
    final c = VideoPlayerController.networkUrl(Uri.parse(real),
        httpHeaders: attempt == 1 ? const <String, String>{} : ua);
    try {
      await c.initialize().timeout(const Duration(seconds: 25));
      if (!mounted || my != gen) {
        await c.dispose();
        return;
      }
      c.addListener(onVc);
      // show the picture the moment it is ready; everything else is applied while it plays
      setState(() {
        vc = c;
        loading = false;
      });
      unawaited(c.play());
      applyGain(c);
      poke();
      applySubs();
      if (speed != 1.0 && !widget.live) unawaited(c.setPlaybackSpeed(speed));
      if (repMode == 'one') unawaited(c.setLooping(true));
      final ra = resumeAt;
      if (ra != null && !widget.live) {
        resumeAt = null;
        unawaited(c.seekTo(ra));
      }
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
      } else if (dm == 'hw' && !decRetried) {
        // hardware-only failed: fall back to the automatic decoder once
        decRetried = true;
        decOverride = 'auto';
        play(cur.url, cur.alt);
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
      if (mounted && menu == null && !scrub && vc?.value.isPlaying == true) {
        setState(() => show = false);
      }
    });
  }

  void showOsd(IconData icon, String text) {
    setState(() {
      osdIcon = icon;
      osd = text;
      osdLvl = false;
    });
    osdT?.cancel();
    osdT = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => osd = null);
    });
  }

  void toggle() {
    final v = vc;
    if (v == null) {
      // the play button also works while the stream is still opening: after an error, or when
      // opening is taking long, it starts the stream again; otherwise it just says so
      // (no "please wait" message any more: it just retries quietly when needed)
      final waited = DateTime.now().difference(loadStart).inSeconds;
      if (err != null || waited >= 6) play(cur.url, cur.alt);
      poke();
      return;
    }
    v.value.isPlaying ? v.pause() : v.play();
    poke();
  }

  // Volume above the phone's maximum is added as player gain (the same idea as FileX's 0-30 scale)
  void applyGain(VideoPlayerController c) {
    final g = muted ? 0.0 : gain;
    try {
      if (g > 1.0) {
        VideoPlayerPlatform.instance.setVolume(c.textureId, g).catchError((_) {});
      } else {
        c.setVolume(g);
      }
    } catch (_) {
      try {
        c.setVolume(g > 1.0 ? 1.0 : g);
      } catch (_) {}
    }
  }

  void mute() {
    muted = !muted;
    final c = vc;
    if (c != null) applyGain(c);
    showLevel(muted ? Icons.volume_off : Icons.volume_up, muted ? 0 : vol30, true);
    poke();
  }

  // small FileX style pill: icon + number (0-30), red for volume, dark for brightness
  void showLevel(IconData icon, int n, bool isVol) {
    setState(() {
      osdIcon = icon;
      osd = '$n';
      osdLvl = true;
      osdCol = isVol ? const Color(0xFFD81B4A) : const Color(0xFF1E1E24);
    });
    osdT?.cancel();
    osdT = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => osd = null);
    });
  }

  void setVol(int l) {
    vol30 = l.clamp(0, 30).toInt();
    // 0-15: phone volume; 16-30: phone stays at maximum and the player adds gain
    nat('setVolume', (vol30 / 15.0).clamp(0.0, 1.0));
    gain = vol30 <= 15 ? 1.0 : 1.0 + (vol30 - 15) * 0.08;
    muted = false;
    final c = vc;
    if (c != null) applyGain(c);
    showLevel(vol30 == 0 ? Icons.volume_off : Icons.volume_up, vol30, true);
  }

  void setBri(int l) {
    bri30 = l.clamp(0, 30).toInt();
    // 30 is full brightness; the curve makes the low numbers brighter than a straight line
    final b = bri30 == 0 ? 0.02 : math.pow(bri30 / 30.0, 0.6).toDouble();
    nat('setBrightness', b);
    showLevel(Icons.brightness_7, bri30, false);
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
    abA = null;
    abB = null;
    if (repMode == 'ab') repMode = 'off';
    decOverride = null;
    decRetried = false;
    play(cur.url, cur.alt);
  }

  // The first button cycles the picture size, like the reference player
  void cycleFit() {
    setState(() => sizeMode = (sizeMode + 1) % sizeNames.length);
    showPill(sizeNames[sizeMode]);
    poke();
  }

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

  // ---- audio / subtitle tracks (uses what the installed player engine offers) ----
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
      return l.isNotEmpty ? l : (g.isNotEmpty ? langName(g) : 'Track ${trackId(t)}');
    } catch (_) {
      return 'Track';
    }
  }

  static const _langs = {
    'en': 'English', 'eng': 'English', 'ur': 'Urdu', 'urd': 'Urdu', 'hi': 'Hindi',
    'hin': 'Hindi', 'ar': 'Arabic', 'ara': 'Arabic', 'es': 'Spanish', 'spa': 'Spanish',
    'fr': 'French', 'fra': 'French', 'fre': 'French', 'de': 'German', 'ger': 'German',
    'deu': 'German', 'tr': 'Turkish', 'tur': 'Turkish', 'pa': 'Punjabi', 'pan': 'Punjabi',
  };

  String langName(String code) => _langs[code.toLowerCase()] ?? code;

  String trackName(String title, String lang, int i) {
    final ln = lang.isEmpty ? '' : langName(lang);
    if (title.isNotEmpty && ln.isNotEmpty && title.toLowerCase() != ln.toLowerCase()) {
      return '$title - $ln';
    }
    if (title.isNotEmpty) return title;
    if (ln.isNotEmpty) return ln;
    return 'Track ${i + 1}';
  }

  Future<List<Map<String, String>>> tracks(String kind) async {
    final v = vc;
    final out = <Map<String, String>>[];
    if (v == null) return out;
    try {
      final mi = await (v as dynamic).getMediaInfo();
      final l = kind == 'audio' ? mi?.audio : mi?.subtitle;
      if (l is List) {
        for (var i = 0; i < l.length; i++) {
          final t = l[i] as dynamic;
          var id = '$i';
          try {
            id = '${t.index}';
          } catch (_) {}
          var lang = '', title = '';
          try {
            final md = t.metadata;
            if (md is Map) {
              lang = '${md['language'] ?? ''}'.trim();
              title = '${md['title'] ?? ''}'.trim();
            }
          } catch (_) {}
          out.add({'id': id, 'label': trackName(title, lang, i), 'lang': lang});
        }
      }
    } catch (_) {}
    if (out.isEmpty && kind == 'audio') {
      try {
        final tr = await (v as dynamic).getAudioTracks();
        if (tr is List) {
          for (final t in tr) {
            out.add({'id': trackId(t), 'label': trackLabel(t), 'lang': ''});
          }
        }
      } catch (_) {}
    }
    return out;
  }

  Future<void> openAudio() async {
    audioTracks = await tracks('audio');
    if (mounted) setState(() => menu = 'audio');
  }

  Future<void> openSubs() async {
    subTracks = await tracks('subtitle');
    if (mounted) setState(() => menu = 'sub');
  }

  Future<void> _selAudio(dynamic v, String id) async {
    try {
      await v.setAudioTracks(<int>[int.parse(id)]);
    } catch (_) {
      await v.selectAudioTrack(id);
    }
  }

  Future<void> pickAudio(Map<String, String>? t) async {
    final v = vc;
    if (v == null) return;
    try {
      if (t == null) {
        audioSel = '';
        audioLabel = '';
        if (audioTracks.isNotEmpty) await _selAudio(v, audioTracks.first['id']!);
      } else {
        await _selAudio(v, t['id']!);
        audioSel = t['id']!;
        audioLabel = t['label']!;
      }
    } catch (_) {
      toast('Could not switch the audio track.');
    }
    if (mounted) setState(() => menu = 'main');
  }

  // Applies the subtitle choice to the video (Off / Auto = preferred language / one track)
  Future<void> applySubs() async {
    final v = vc;
    if (v == null) return;
    try {
      if (subSel == 'off') {
        await (v as dynamic).setSubtitleTracks(<int>[]);
      } else if (subSel == 'auto') {
        final l = await tracks('subtitle');
        if (l.isEmpty) return;
        final want = Cfg.gs('os_lang', 'en').toLowerCase();
        var pickIt = l.first;
        for (final t in l) {
          final lg = (t['lang'] ?? '').toLowerCase();
          if (lg.isNotEmpty && (lg == want || lg.startsWith(want) || want.startsWith(lg))) {
            pickIt = t;
            break;
          }
        }
        await (v as dynamic).setSubtitleTracks(<int>[int.parse(pickIt['id']!)]);
      } else {
        await (v as dynamic).setSubtitleTracks(<int>[int.parse(subSel)]);
      }
    } catch (_) {}
  }

  Future<void> pickSub(String id, String label) async {
    subSel = id;
    subLabel = label;
    await applySubs();
    if (mounted) setState(() => menu = 'main');
  }

  // ---- repeat ----
  void pickRepeat(String m) {
    final v = vc;
    if (m == 'ab') {
      final pos = v?.value.position ?? Duration.zero;
      if (repMode != 'ab' || abB != null) {
        repMode = 'ab';
        abA = pos;
        abB = null;
        v?.setLooping(false);
        setState(() => menu = null);
        showPill('A set at ${fmt(pos)}. Choose A-B Loop again to set B');
      } else {
        if (pos > abA!) {
          abB = pos;
          showPill('A-B loop on');
          v?.seekTo(abA!);
        } else {
          showPill('B must be after A');
        }
        setState(() => menu = null);
      }
      return;
    }
    repMode = m;
    abA = null;
    abB = null;
    v?.setLooping(m == 'one');
    setState(() => menu = 'main');
  }

  // ---- decoder ----
  Future<void> pickDecoder(String m) async {
    final v = vc;
    final k = widget.live ? 'dec_live' : 'dec_vod';
    await Cfg.ps('${k}_p', m);
    decOverride = null;
    decRetried = false;
    setState(() => menu = null);
    if (widget.live) {
      play(cur.url, cur.alt);
    } else {
      resumeAt = v?.value.position;
      play(cur.url, cur.alt);
    }
  }

  // ---- touch gestures ----
  void vStart(DragStartDetails d, double w) {
    dragMode = d.localPosition.dx < w / 2 ? 2 : 1;
    accum = (dragMode == 1 ? vol30 : bri30) / 30.0;
  }

  void vUpdate(DragUpdateDetails d, double h) {
    accum = (accum - d.delta.dy / (h * 0.55)).clamp(0.0, 1.0).toDouble();
    final l = (accum * 30).round();
    if (dragMode == 1) {
      if (l != vol30 || osd == null) setVol(l);
    } else {
      if (l != bri30 || osd == null) setBri(l);
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
  // Starts at 0%. It only grows when data really arrives (seconds of video buffered ahead of the
  // playhead), so it follows the connection speed. It never goes backwards during one load.
  int bufPct(VideoPlayerController? v) {
    final busyNow = loading || (v != null && v.value.isBuffering);
    if (busyNow && !wasBusy) {
      pctHold = 0;
      loadStart = DateTime.now();
    }
    wasBusy = busyNow;
    var p = 0;
    if (v != null && v.value.isInitialized) {
      final b = v.value.buffered;
      final ahead = b.isEmpty ? Duration.zero : b.last.end - v.value.position;
      final target = widget.live ? 1500 : 3000; // ms of video that counts as 100% (starts fast)
      p = (ahead.inMilliseconds * 100 / target).clamp(0, 100).round();
    }
    if (p > pctHold) pctHold = p;
    return pctHold;
  }

  String get idLabel {
    final k = widget.kind;
    if (k == 'series') return 'Episode ID';
    if (k == 'movie') return 'Movie ID';
    if (widget.live) return 'Channel ID';
    return 'Stream ID';
  }

  Widget ctl(IconData i, VoidCallback? f, double k, {Color? color, double size = 24}) => IconButton(
        icon: Icon(i, color: color ?? (f == null ? Colors.white30 : Colors.white)),
        iconSize: size * k,
        padding: EdgeInsets.all(8 * k),
        constraints: const BoxConstraints(),
        onPressed: f,
      );

  Widget seekBar(VideoPlayerController? v, double k) {
    final dur = v?.value.duration.inMilliseconds ?? 0;
    final pos = v?.value.position.inMilliseconds ?? 0;
    final ok = v != null && v.value.isInitialized && dur > 0;
    final val = scrub ? scrubVal : (ok ? (pos / dur).clamp(0.0, 1.0).toDouble() : 0.0);
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: const Color(0xFF55AEE8),
        inactiveTrackColor: Colors.white,
        thumbColor: scrub ? const Color(0xFFFFEB7A) : const Color(0xFF55AEE8),
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6 * k),
        overlayShape: SliderComponentShape.noOverlay,
        trackShape: const RectangularSliderTrackShape(),
      ),
      child: Slider(
        value: val,
        onChangeStart: ok
            ? (x) {
                scrub = true;
                scrubVal = x;
                hideT?.cancel();
              }
            : null,
        onChanged: ok ? (x) => setState(() => scrubVal = x) : null,
        onChangeEnd: ok
            ? (x) {
                v!.seekTo(Duration(milliseconds: (x * dur).round()));
                setState(() => scrub = false);
                poke();
              }
            : null,
      ),
    );
  }

  Widget overlay(VideoPlayerController? v, double w, double k) {
    final size = v?.value.size;
    final live = widget.live;
    final playing = v?.value.isPlaying == true;
    final now = epg.isNotEmpty && epg[0].isNotEmpty ? epg[0] : 'No Program Found';
    final next = epg.length > 1 && epg[1].isNotEmpty ? epg[1] : 'No Program Found';
    final pos = v?.value.position ?? Duration.zero;
    final dur = v?.value.duration ?? Duration.zero;
    final txt = TextStyle(fontSize: 13 * k, color: Colors.white);
    return ExcludeFocus(
      child: Column(children: [
        // ---- top: back arrow, title, EXO resolution badge ----
        Container(
          decoration: const BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent])),
          padding: EdgeInsets.fromLTRB(w * 0.06, 10 * k, w * 0.03, 10 * k),
          child: Row(children: [
            IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white70),
                iconSize: 26 * k,
                onPressed: () => Navigator.pop(context)),
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
                  style: TextStyle(fontSize: 15 * k, fontWeight: FontWeight.bold)),
            ),
            if (size != null && size.width > 0)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12 * k, vertical: 5 * k),
                decoration: BoxDecoration(
                    color: const Color(0xFF4A2A10),
                    border: Border.all(color: const Color(0xFFA85A1F)),
                    borderRadius: BorderRadius.circular(20 * k)),
                child: Text('EXO: ${size.width.toInt()}x${size.height.toInt()}',
                    style: TextStyle(
                        fontSize: 12 * k,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFFF1DFCB))),
              )
            else
              SizedBox(width: 48 * k),
          ]),
        ),
        const Spacer(),
        // ---- bottom: seek bar and the control row ----
        Container(
          decoration: const BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black54, Colors.transparent])),
          padding: EdgeInsets.fromLTRB(w * 0.07, 8 * k, w * 0.07, 12 * k),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (live) ...[
              Text('Now: $now',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.orange, fontSize: 15 * k)),
              Text('Next: $next',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15 * k)),
              SizedBox(height: 4 * k),
            ],
            Row(children: [
              Text(live ? '00:00' : fmt(scrub ? Duration(milliseconds: (scrubVal * dur.inMilliseconds).round()) : pos),
                  style: txt),
              SizedBox(width: 6 * k),
              Expanded(
                child: live
                    ? Container(height: 3, color: Colors.white)
                    : seekBar(v, k),
              ),
              SizedBox(width: 6 * k),
              live
                  ? Text('Live',
                      style: TextStyle(
                          color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13 * k))
                  : Text(fmt(dur), style: txt),
            ]),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: w * 0.05),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                ctl(Icons.aspect_ratio, cycleFit, k),
                ctl(Icons.picture_in_picture_alt, () => nat('enterPip'), k),
                ctl(Icons.memory, () => setState(() => menu = 'dec'), k),
                ctl(Icons.skip_previous, () => zap(-1), k, size: 26),
                ctl(Icons.replay_30, live ? null : () => seek(-30), k, size: 28),
                InkResponse(
                  onTap: toggle,
                  child: Container(
                    width: 38 * k,
                    height: 38 * k,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: Icon(playing ? Icons.pause : Icons.play_arrow,
                        color: Colors.black, size: 26 * k),
                  ),
                ),
                ctl(Icons.forward_30, live ? null : () => seek(30), k, size: 28),
                ctl(Icons.skip_next, () => zap(1), k, size: 26),
                ctl(muted ? Icons.volume_off : Icons.volume_up, mute, k, color: Colors.white70),
                ctl(Icons.high_quality, () {
                  final z = v?.value.size;
                  showPill(z != null && z.width > 0
                      ? 'Quality ${z.width.toInt()}x${z.height.toInt()}'
                      : 'Quality: loading');
                }, k),
                ctl(Icons.settings, () => setState(() => menu = 'main'), k),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget menuPanel(double w, double h, double k) {
    final rowH = 42 * k;
    final fs = 14 * k;
    Widget hdr(String t, {String? to = 'main'}) => Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: rowH,
            child: ListTile(
              contentPadding: EdgeInsets.symmetric(horizontal: 12 * k),
              minLeadingWidth: 24 * k,
              leading: Icon(Icons.skip_previous, size: 20 * k),
              title: Text(t, style: TextStyle(fontWeight: FontWeight.bold, fontSize: fs)),
              onTap: () => setState(() => menu = to),
            ),
          ),
          const Divider(height: 1, color: Colors.white24),
        ]);
    Widget opt(String t, bool on, VoidCallback f, {bool first = false}) => SizedBox(
          height: rowH,
          child: ListTile(
            autofocus: first,
            contentPadding: EdgeInsets.symmetric(horizontal: 12 * k),
            minLeadingWidth: 30 * k,
            leading: SizedBox(width: 30 * k, child: on ? Icon(Icons.check, size: 22 * k) : null),
            title: Text(t, style: TextStyle(fontSize: fs), maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: f,
          ),
        );
    Widget row(Widget icon, String t, String v, VoidCallback f, {bool first = false}) => SizedBox(
          height: rowH,
          child: ListTile(
            autofocus: first,
            contentPadding: EdgeInsets.symmetric(horizontal: 12 * k),
            minLeadingWidth: 28 * k,
            leading: icon,
            title: Text(t, style: TextStyle(fontSize: fs)),
            trailing: Text(v, style: TextStyle(fontSize: fs, color: Colors.white60)),
            onTap: f,
          ),
        );
    final List<Widget> rows;
    var width = 320 * k;
    var left = false;
    switch (menu) {
      case 'speed':
        rows = [
          hdr('Playback speed'),
          for (final x in const [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0])
            opt(x == 1.0 ? 'Normal' : '${x}x', speed == x, () => setSpeed(x), first: x == 1.0),
        ];
        break;
      case 'audio':
        rows = [
          hdr('Audio track'),
          opt('Auto', audioSel.isEmpty, () => pickAudio(null), first: true),
          for (final t in audioTracks) opt(t['label']!, audioSel == t['id'], () => pickAudio(t)),
        ];
        break;
      case 'sub':
        rows = [
          hdr('Subtitles'),
          opt('Off', subSel == 'off', () => pickSub('off', 'Off')),
          opt('Auto', subSel == 'auto', () => pickSub('auto', 'Auto'), first: true),
          for (final t in subTracks) opt(t['label']!, subSel == t['id'], () => pickSub(t['id']!, t['label']!)),
        ];
        break;
      case 'repeat':
        rows = [
          hdr('Repeat'),
          opt('Off', repMode == 'off', () => pickRepeat('off'), first: true),
          opt('Repeat one', repMode == 'one', () => pickRepeat('one')),
          opt('A-B Loop', repMode == 'ab', () => pickRepeat('ab')),
        ];
        break;
      case 'dec':
        left = true;
        final m = decMode;
        rows = [
          hdr(widget.live ? 'Live Player Decoder' : 'VOD Player Decoder', to: null),
          opt('Auto', m == 'auto', () => pickDecoder('auto')),
          opt('Hardware only', m == 'hw' || m == 'hwdef', () => pickDecoder('hw'), first: true),
          opt('Software preferred', m == 'sw', () => pickDecoder('sw')),
        ];
        break;
      default:
        width = 240 * k;
        rows = [
          row(Icon(Icons.speed, color: Colors.white54, size: 24 * k), 'Playback speed',
              speed == 1.0 ? 'Normal' : '${speed}x', () => setState(() => menu = 'speed'),
              first: true),
          row(Icon(Icons.music_note, color: const Color(0xFFFB8C00), size: 26 * k), 'Audio track',
              audioSel.isEmpty ? 'Auto' : audioLabel, openAudio),
          row(
              CircleAvatar(
                  radius: 13 * k,
                  backgroundColor: const Color(0xFFF57C00),
                  child: Text('CC',
                      style: TextStyle(
                          fontSize: 10 * k, fontWeight: FontWeight.bold, color: Colors.white))),
              'Subtitles',
              subSel == 'off' ? 'Off' : (subSel == 'auto' ? 'Auto' : subLabel),
              openSubs),
          row(Icon(Icons.repeat, size: 24 * k), 'Repeat',
              repMode == 'off' ? 'Off' : (repMode == 'one' ? 'One' : 'A-B'),
              () => setState(() => menu = 'repeat')),
          row(Icon(Icons.memory, size: 24 * k), 'Decoder:', decShown,
              () => setState(() => menu = 'dec')),
        ];
    }
    final maxH = h - 40 * k < 120 ? 120.0 : h - 40 * k;
    return Positioned(
      right: left ? null : 48 * k,
      left: left ? w * 0.27 : null,
      bottom: 52 * k,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, minWidth: width, maxHeight: maxH),
        child: Material(
          color: const Color(0xFF212121),
          borderRadius: BorderRadius.circular(12 * k),
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
        fit: sizeFits[sizeMode],
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: sz.width == 0 ? 16 : sz.width,
          height: sz.height == 0 ? 9 : sz.height,
          child: VideoPlayer(v),
        ),
      ),
    );
  }

  // ID, speed and percent while the video is loading or buffering
  Widget loadBox(VideoPlayerController? v, double k) {
    final id = cur.id;
    return Center(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 28 * k, vertical: 18 * k),
        decoration: BoxDecoration(
            color: const Color(0xFF1E2029),
            border: Border.all(color: const Color(0xFF2E303A)),
            borderRadius: BorderRadius.circular(14 * k)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (id != null && id.isNotEmpty)
            Text('$idLabel: $id',
                style: TextStyle(fontSize: 15 * k, fontWeight: FontWeight.bold, color: Colors.white)),
          SizedBox(height: 6 * k),
          Text(speedText, style: TextStyle(fontSize: 14 * k, color: Colors.white)),
          SizedBox(height: 4 * k),
          Text('${bufPct(v)}%', style: TextStyle(fontSize: 14 * k, color: Colors.white)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    final v = vc;
    final pip = inPip.value;
    final hasErr = err != null || v?.value.hasError == true;
    final mq = MediaQuery.of(c).size;
    final h = mq.height, w = mq.width;
    final k = (h / 360).clamp(0.9, 1.8).toDouble();
    final busy = loading || (v != null && v.value.isBuffering);
    final cap = (v != null && subSel != 'off') ? v.value.caption.text : '';
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
                if (!pip && cap.isNotEmpty)
                  Positioned(
                    left: 40,
                    right: 40,
                    bottom: show ? 110 * k : 24 * k,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                            color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                        child: Text(cap,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16 * k, color: Colors.white)),
                      ),
                    ),
                  ),
                if (busy && !hasErr && !pip) loadBox(v, k),
                if (hasErr)
                  Center(
                      child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Text(err ?? 'A stream error occurred.',
                              textAlign: TextAlign.center))),
                if (!pip && (show || hasErr)) Positioned.fill(child: overlay(v, w, k)),
                if (!pip && Cfg.gb('dbg_overlay', false) && v != null && v.value.isInitialized)
                  Positioned(
                    left: 10,
                    top: 10,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      color: Colors.black54,
                      child: Text(
                          '${v.value.size.width.toInt()}x${v.value.size.height.toInt()}   '
                          'pos ${fmt(v.value.position)}   '
                          'buf ${v.value.buffered.isEmpty ? '-' : fmt(v.value.buffered.last.end)}'
                          '${v.value.isBuffering ? '   buffering' : ''}',
                          style: const TextStyle(fontSize: 12, color: Colors.greenAccent)),
                    ),
                  ),
                if (!pip && osd != null && osdLvl)
                  Align(
                    alignment: const Alignment(0, -0.42),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12 * k, vertical: 5 * k),
                      decoration: BoxDecoration(
                          color: osdCol, borderRadius: BorderRadius.circular(20 * k)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(osdIcon, size: 15 * k, color: Colors.white),
                        SizedBox(width: 6 * k),
                        Text(osd!,
                            style: TextStyle(
                                fontSize: 13 * k, fontWeight: FontWeight.bold, color: Colors.white)),
                      ]),
                    ),
                  ),
                if (!pip && osd != null && !osdLvl)
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
                if (!pip && pill != null)
                  Align(
                    alignment: const Alignment(0, -0.45),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 22 * k, vertical: 9 * k),
                      decoration: BoxDecoration(
                          color: const Color(0xCC5B5B3B),
                          borderRadius: BorderRadius.circular(22 * k)),
                      child: Text(pill!, style: TextStyle(fontSize: 14 * k, color: Colors.white)),
                    ),
                  ),
                if (!pip && menu != null) menuPanel(w, h, k),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
