import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'core.dart';
import 'extra.dart';
import 'fx.dart';
import 'main.dart';

// ---------------- Account Info ----------------
class AccountPage extends StatefulWidget {
  final Session s;
  const AccountPage(this.s, {super.key});
  @override
  State<AccountPage> createState() => _AccountState();
}

class _AccountState extends State<AccountPage> {
  Session get s => widget.s;
  bool busy = false;

  DateTime? dt(dynamic v) {
    final n = int.tryParse('${v ?? ''}');
    return n == null || n == 0 ? null : DateTime.fromMillisecondsSinceEpoch(n * 1000);
  }

  String dmy(DateTime? d) => d == null ? '-' : '${two(d.day)}-${two(d.month)}-${d.year}';

  Future<void> refresh() async {
    setState(() => busy = true);
    // tryLogin makes a throw-away Session that would replace the global one
    final keep = gSession;
    final n = await tryLogin(s.user, s.pass);
    gSession = keep;
    if (n != null) {
      s.info
        ..clear()
        ..addAll(n.info);
    }
    if (mounted) setState(() => busy = false);
  }

  Widget chip(IconData i, String t, Color col) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: col.withAlpha(35),
            border: Border.all(color: col.withAlpha(140), width: 1.5),
            borderRadius: BorderRadius.circular(30)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 20, color: col),
          const SizedBox(width: 6),
          Text(t, style: TextStyle(fontSize: 14, color: col)),
        ]),
      );

  Widget bar(double v) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
            value: v.clamp(0.0, 1.0).toDouble(), minHeight: 7, backgroundColor: Colors.white12, color: accent),
      );

  Widget small(String t) =>
      Text(t, style: const TextStyle(fontSize: 13, letterSpacing: 2, color: Colors.white60));

  @override
  Widget build(BuildContext c) {
    final joined = dt(s.info['created_at']);
    final exp = dt(s.info['exp_date']);
    final now = DateTime.now();
    String days;
    double prog = 0;
    if (exp == null) {
      days = 'Unlimited';
      prog = 1;
    } else {
      final d = exp.difference(now).inHours / 24;
      final n = d <= 0 ? 0 : d.ceil();
      days = n == 1 ? '1 day' : '$n days';
      if (joined != null) {
        final total = exp.difference(joined).inSeconds;
        if (total > 0) prog = now.difference(joined).inSeconds / total;
      }
    }
    final active = int.tryParse('${s.info['active_cons'] ?? 0}') ?? 0;
    final maxc = int.tryParse('${s.info['max_connections'] ?? 1}') ?? 1;
    final trial = '${s.info['is_trial']}' == '1';
    final status = clean(s.info['status']).isEmpty ? 'Active' : clean(s.info['status']);
    // The panel often sends the words "API Message" itself: show the heading only once
    final msg = clean(s.info['message'])
        .replaceFirst(RegExp(r'^\s*api message\s*', caseSensitive: false), '')
        .trim();
    final letter = s.user.isEmpty ? '?' : s.user.substring(0, 1).toUpperCase();

    final left = Container(
      width: 200,
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF3A2220), Color(0xFF2B1B22)]),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Stack(children: [
          Container(
            width: 96,
            height: 96,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFF8A3D), Color(0xFFFF4D7A), Color(0xFFB83CC0)])),
            child: Text(letter, style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold)),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF2EC27E),
                  border: Border.all(color: const Color(0xFF2B1B22), width: 3)),
              child: const Icon(Icons.person, size: 18),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        Text(s.user,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
          chip(Icons.check_circle, trial ? 'Trial' : 'Paid', const Color(0xFF2EC27E)),
          chip(Icons.verified, status, const Color(0xFF4C8DFF)),
        ]),
      ]),
    );

    final right = Padding(
      padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(days, style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w600)),
        const Text('remaining on your subscription',
            style: TextStyle(fontSize: 18, color: Colors.white60)),
        const SizedBox(height: 22),
        Row(children: [
          small('JOINED'),
          const SizedBox(width: 16),
          Expanded(child: bar(prog)),
          const SizedBox(width: 16),
          small('EXPIRES'),
        ]),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(dmy(joined), style: const TextStyle(fontSize: 16, color: Colors.white70)),
          Text(exp == null ? 'Never' : dmy(exp),
              style: const TextStyle(fontSize: 16, color: Colors.white70)),
        ]),
        const SizedBox(height: 22),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              small('CONNECTIONS'),
              const SizedBox(height: 6),
              Text('$active / $maxc', style: const TextStyle(fontSize: 28)),
              const SizedBox(height: 10),
              SizedBox(width: 190, child: bar(maxc == 0 ? 0 : active / maxc)),
            ]),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              small('PLAN'),
              const SizedBox(height: 6),
              Text(trial ? 'Trial' : 'Paid',
                  style: TextStyle(
                      fontSize: 28, color: trial ? Colors.orangeAccent : const Color(0xFF2EC27E))),
            ]),
          ),
        ]),
        const SizedBox(height: 20),
        const Divider(color: Colors.white24, height: 1),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              margin: const EdgeInsets.only(top: 8),
              width: 7,
              height: 7,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white54)),
          const SizedBox(width: 14),
          Expanded(
            child: Text(msg.isEmpty ? 'API Message' : 'API Message\n$msg',
                style: const TextStyle(fontSize: 18)),
          ),
        ]),
      ]),
    );

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(children: [
              logoImg(44),
              const Expanded(
                child: Center(
                  child: Text('ACCOUNT INFO',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w500, letterSpacing: 1.5)),
                ),
              ),
              rb(Icons.arrow_back, () => Navigator.pop(c)),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(children: [
                Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: IntrinsicHeight(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      left,
                      Expanded(child: right),
                    ]),
                  ),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: GradBtn('Refresh', refresh, busy: busy)),
                  const SizedBox(width: 14),
                  Expanded(child: GradBtn('Log out', () => doLogout(c), outline: true)),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ---------------- Install EPG ----------------
Future<void> installEpgDialog(BuildContext c, Session s) =>
    showDialog(context: c, barrierDismissible: false, builder: (d) => _EpgInstall(s));

int _count(List<int> b, List<int> p) {
  var n = 0;
  for (var i = 0; i <= b.length - p.length; i++) {
    if (b[i] != p[0]) continue;
    var ok = true;
    for (var j = 1; j < p.length; j++) {
      if (b[i + j] != p[j]) {
        ok = false;
        break;
      }
    }
    if (ok) {
      n++;
      i += p.length - 1;
    }
  }
  return n;
}

class _EpgInstall extends StatefulWidget {
  final Session s;
  const _EpgInstall(this.s);
  @override
  State<_EpgInstall> createState() => _EpgInstallState();
}

class _EpgInstallState extends State<_EpgInstall> {
  String status = 'Connecting...';
  int bytes = 0, chans = 0, progs = 0;
  bool done = false, failed = false, cancel = false;
  HttpClient? hc;

  @override
  void initState() {
    super.initState();
    run();
  }

  @override
  void dispose() {
    cancel = true;
    hc?.close(force: true);
    super.dispose();
  }

  String mb(int b) => '${(b / 1048576).toStringAsFixed(1)} MB';

  Future<void> run() async {
    final s = widget.s;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    hc = client;
    try {
      final u = Uri.parse('${s.host}/xmltv.php?username=${s.u}&password=${s.p}');
      final rq = await client.getUrl(u);
      ua.forEach((k, v) => rq.headers.set(k, v));
      final rs = await rq.close().timeout(const Duration(seconds: 30));
      if (rs.statusCode != 200) throw Exception('HTTP ${rs.statusCode}');
      var dir = await nat('cacheDir');
      if (dir is! String || dir.isEmpty) dir = Directory.systemTemp.path;
      final f = File('$dir/epg_${s.user.hashCode.abs()}.xml');
      final sink = f.openWrite();
      final pProg = '<programme '.codeUnits, pChan = '<channel '.codeUnits;
      var tail = <int>[];
      final sw = Stopwatch()..start();
      if (mounted) setState(() => status = 'Downloading guide...');
      await for (final chunk in rs) {
        if (cancel) break;
        sink.add(chunk);
        bytes += chunk.length;
        final buf = <int>[...tail, ...chunk];
        progs += _count(buf, pProg);
        chans += _count(buf, pChan);
        tail = buf.length > 10 ? buf.sublist(buf.length - 10) : buf;
        if (sw.elapsedMilliseconds > 250 && mounted) {
          sw.reset();
          setState(() {});
        }
      }
      await sink.close();
      if (cancel) return;
      if (progs == 0) throw Exception('No guide data found');
      await Cfg.ps('epg_info', '${DateTime.now().millisecondsSinceEpoch}|$chans|$progs|$bytes');
      if (mounted) {
        setState(() {
          done = true;
          status = 'EPG installed';
        });
      }
    } catch (e) {
      if (mounted && !cancel) {
        setState(() {
          failed = true;
          status = 'Could not install the guide. Your provider may not offer an XMLTV guide.';
        });
      }
    } finally {
      client.close(force: true);
    }
  }

  @override
  Widget build(BuildContext c) {
    final running = !done && !failed;
    return FxDialog(
      label: 'GUIDE',
      title: 'Install EPG',
      width: 480,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(status, style: TextStyle(fontSize: 17, color: failed ? Colors.redAccent : Colors.white)),
        const SizedBox(height: 14),
        if (running)
          const LinearProgressIndicator(color: accent, backgroundColor: Colors.white12, minHeight: 6),
        if (running || done)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('${mb(bytes)}   ·   $chans channels   ·   $progs programmes',
                style: const TextStyle(fontSize: 15, color: Colors.white60)),
          ),
      ]),
      actions: [
        if (running)
          FxBtn('Cancel', () {
            cancel = true;
            hc?.close(force: true);
            Navigator.pop(c);
          }, autofocus: true)
        else ...[
          FxBtn('Close', () => Navigator.pop(c), autofocus: true),
          if (done)
            FxBtn('Open Timeline', () {
              final nav = Navigator.of(c);
              nav.pop();
              nav.push(MaterialPageRoute(builder: (_) => EpgTimeline(widget.s)));
            }, primary: true),
        ],
      ],
    );
  }
}
