import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'core.dart';
import 'detail.dart';
import 'main.dart';
import 'player.dart';
import 'settings.dart';

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
  Lib get lib => t == 'live' ? s.live : (t == 'movie' ? s.movie : s.series);

  List<It> items = [], shown = [], recent = [];
  Map<String, It> favs = {};
  String catId = '', q = '', catQ = '';
  bool loading = true, sortAz = false, searching = false;
  String? error;
  int selGen = 0;
  Timer? deb;
  final sc = TextEditingController(), csc = TextEditingController();

  // live preview
  VideoPlayerController? pv;
  It? sel;
  bool pLoading = false;
  String? pErr;
  int pgen = 0;
  List<String> epg = [];

  bool get prompt => !live && catId == 'all' && q.isEmpty;
  bool get showSearch => !live || searching;

  @override
  void initState() {
    super.initState();
    init();
  }

  @override
  void dispose() {
    pgen++;
    pv?.dispose();
    deb?.cancel();
    sc.dispose();
    csc.dispose();
    super.dispose();
  }

  Future<void> init() async {
    final fl = await loadList('fav_$t');
    for (final i in fl) {
      favs[i.id] = i;
    }
    recent = await loadList('recent_$t');
    await load();
  }

  Future<void> load({bool force = false}) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (force) {
        final job = lib.start(force: true);
        if (live) await job;
      }
      if (lib.cats.isEmpty) await lib.loadCats();
      if (live) {
        await lib.start();
        if (lib.failed && lib.total == 0) throw Exception('live');
      } else {
        lib.start();
      }
    } catch (_) {
      error = 'Failed to load. Check your internet connection and tap RETRY.';
    }
    if (!mounted) return;
    if (error != null) {
      setState(() => loading = false);
      return;
    }
    if (catId.isEmpty) catId = 'all';
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
    List<It> res = [];
    try {
      if (id == 'fav') {
        res = favs.values.toList();
      } else if (id == 'recent') {
        res = List<It>.of(recent);
      } else if (id == 'all') {
        res = live ? lib.all : <It>[];
      } else if (id == 'added') {
        res = lib.recentAdded();
      } else {
        res = await lib.cat(id);
      }
    } catch (_) {
      err = 'Failed to load this category. Tap RETRY.';
    }
    if (!mounted || my != selGen) return;
    items = res;
    error = err;
    loading = false;
    recompute();
  }

  void recompute() {
    List<It> l;
    if (!live && catId == 'all') {
      l = q.isEmpty ? <It>[] : lib.search(q);
    } else if (q.isEmpty) {
      l = items;
    } else {
      final lq = q.toLowerCase();
      l = items.where((i) => i.ln.contains(lq)).toList();
    }
    if (sortAz) {
      l = List<It>.of(l)..sort((a, b) => a.ln.compareTo(b.ln));
    }
    setState(() => shown = l);
  }

  void onQuery(String v) {
    deb?.cancel();
    deb = Timer(const Duration(milliseconds: 250), () {
      q = v.trim();
      recompute();
    });
  }

  Future<void> toggleFav(It i) async {
    if (favs.containsKey(i.id)) {
      favs.remove(i.id);
    } else {
      favs[i.id] = i;
    }
    if (catId == 'fav') items = favs.values.toList();
    recompute();
    await saveList('fav_$t', favs.values.toList());
  }

  Future<void> addRecent(It i) async {
    recent.removeWhere((x) => x.id == i.id);
    recent.insert(0, i);
    if (recent.length > 30) recent.removeRange(30, recent.length);
    await saveList('recent_$t', recent);
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

  Future<void> startPreview(It i, {bool second = false}) async {
    final my = ++pgen;
    final old = pv;
    setState(() {
      pv = null;
      pLoading = true;
      pErr = null;
    });
    await disposeLater(old);
    if (!mounted || my != pgen) return;
    final pi = livePiOf(s, i.id, i.name);
    final url = second ? pi.alt : pi.url;
    if (url == null) {
      setState(() {
        pLoading = false;
        pErr = 'Unable to play this channel. Try another one.';
      });
      return;
    }
    final c = VideoPlayerController.networkUrl(Uri.parse(url), httpHeaders: ua);
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
      if (!second && pi.alt != null) {
        startPreview(i, second: true);
      } else {
        setState(() {
          pLoading = false;
          pErr = 'Unable to play this channel. Try another one.';
        });
      }
    }
  }

  void loadEpg(It i) {
    setState(() => epg = []);
    s.epg(i.id).then((l) {
      if (mounted && sel != null && sel!.id == i.id) setState(() => epg = l);
    });
  }

  Future<void> fullscreen() async {
    final cur = sel;
    if (cur == null) return;
    var idx = shown.indexWhere((x) => x.id == cur.id);
    final src = idx >= 0 ? List<It>.of(shown) : <It>[cur];
    if (idx < 0) idx = 0;
    final list = [for (final x in src) livePiOf(s, x.id, x.name)];
    // Hand the already-running preview to the player so it does not reload
    VideoPlayerController? carry;
    if (Cfg.playerMode != 'external' && pv != null && pv!.value.isInitialized) {
      pgen++;
      carry = pv;
      setState(() {
        pv = null;
        pLoading = false;
      });
    } else {
      await stopPreview();
    }
    if (!mounted) return;
    final builtin = await playItems(context, s, list, idx, true, initial: carry, onIndex: (n) {
      sel = src[n];
      addRecent(src[n]);
    });
    if (mounted && builtin && sel != null) startPreview(sel!);
  }

  Future<void> openDetail(It i) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => DetailPage(s, i, t)));
    final fl = await loadList('fav_$t');
    favs = {for (final x in fl) x.id: x};
    recent = await loadList('recent_$t');
    if (!mounted) return;
    if (catId == 'fav') items = favs.values.toList();
    if (catId == 'recent') items = List<It>.of(recent);
    recompute();
  }

  void onTapItem(It i) {
    if (live) {
      if (sel != null && sel!.id == i.id && (pv != null || pLoading)) {
        fullscreen();
        return;
      }
      setState(() => sel = i);
      addRecent(i);
      startPreview(i);
      loadEpg(i);
    } else {
      openDetail(i);
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
              if (!live) return;
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
            rb(Icons.refresh, () => load(force: true)),
            rb(Icons.settings,
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()))),
            rb(Icons.logout, () => doLogout(context)),
          ]),
        ),
      );

  Widget field(TextEditingController c, String hint, ValueChanged<String> f, {bool auto = false}) =>
      Padding(
        padding: const EdgeInsets.all(8),
        child: TextField(
          controller: c,
          autofocus: auto,
          onChanged: f,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: hint,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );

  Widget badge(String txt) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(10)),
        child: Text(txt, style: const TextStyle(fontSize: 12)),
      );

  Widget body(Widget Function() ok) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(error!, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: () => load(force: false), child: const Text('RETRY')),
        ]),
      );
    }
    if (prompt) {
      return Center(
        child: Text(t == 'movie' ? 'Search in movies' : 'Search in series',
            style: const TextStyle(fontSize: 32, color: Colors.white70)),
      );
    }
    if (shown.isEmpty) return const Center(child: Text('Nothing found'));
    return ok();
  }

  Widget catPane() => ValueListenableBuilder<int>(
        valueListenable: lib.tick,
        builder: (_, __, ___) {
          final cq = catQ.toLowerCase();
          final rows = <Map<String, dynamic>>[
            if (cq.isEmpty)
              <String, dynamic>{
                'id': 'all',
                'name': 'ALL',
                'icon': Icons.apps,
                'col': Colors.blueAccent,
                'n': lib.total
              },
            if (cq.isEmpty)
              <String, dynamic>{
                'id': 'fav',
                'name': 'FAVOURITES',
                'icon': Icons.favorite,
                'col': Colors.pinkAccent
              },
            if (cq.isEmpty)
              <String, dynamic>{
                'id': 'recent',
                'name': 'RECENTLY WATCHED',
                'icon': Icons.history,
                'col': Colors.orange
              },
            if (cq.isEmpty && !live)
              <String, dynamic>{
                'id': 'added',
                'name': 'RECENTLY ADDED',
                'icon': Icons.add_box,
                'col': Colors.green,
                'n': lib.total == 0 ? null : (lib.total < 100 ? lib.total : 100)
              },
            for (final c in lib.cats)
              if (cq.isEmpty || '${c['category_name']}'.toLowerCase().contains(cq))
                <String, dynamic>{
                  'id': '${c['category_id']}',
                  'name': '${c['category_name']}',
                  'n': lib.count('${c['category_id']}')
                },
          ];
          return Column(children: [
            field(csc, 'Search here...', (v) => setState(() => catQ = v.trim())),
            Expanded(
              child: ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, k) {
                  final r = rows[k];
                  final id = r['id'] as String;
                  final ic = r['icon'] as IconData?;
                  final cnt = r['n'];
                  return ListTile(
                    autofocus: k == 0,
                    dense: true,
                    selected: id == catId,
                    selectedColor: accent,
                    selectedTileColor: Colors.white10,
                    leading: ic == null
                        ? null
                        : CircleAvatar(
                            radius: 14,
                            backgroundColor: r['col'] as Color,
                            child: Icon(ic, size: 16, color: Colors.white)),
                    title: Text(r['name'] as String, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: cnt == null ? null : badge('$cnt'),
                    onTap: () => select(id),
                  );
                },
              ),
            ),
          ]);
        },
      );

  Widget livePane() => Column(children: [
        if (showSearch) field(sc, 'Search here...', onQuery, auto: true),
        Expanded(
          child: body(() => ListView.builder(
                itemCount: shown.length,
                itemBuilder: (_, n) {
                  final i = shown[n];
                  final on = sel != null && sel!.id == i.id;
                  return ListTile(
                    dense: true,
                    selected: on,
                    selectedColor: accent,
                    selectedTileColor: Colors.white10,
                    leading: SizedBox(width: 44, height: 44, child: thumb(i.icon)),
                    title: Text(i.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(favs.containsKey(i.id) ? Icons.favorite : Icons.favorite_border,
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
      ),
    );
  }

  Widget previewPane() {
    final now = epg.isNotEmpty && epg[0].isNotEmpty ? epg[0] : 'No Program Found';
    final next = epg.length > 1 && epg[1].isNotEmpty ? epg[1] : 'No Program Found';
    return Column(children: [
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
          child: sel == null
              ? const Center(child: Text('No Channel Selected', style: TextStyle(color: Colors.white70)))
              : SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(sel!.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('Now: $now',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.orange, fontSize: 13)),
                    Text('Next: $next',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 10),
                    const Text('Press OK or tap the same channel again to open it in fullscreen.',
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ]),
                ),
        ),
      ),
    ]);
  }

  Widget gridPane() => Column(children: [
        field(sc, 'Search here...', onQuery),
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
                  final i = shown[n];
                  return FocusCard(
                    margin: EdgeInsets.zero,
                    radius: 10,
                    onTap: () => onTapItem(i),
                    onLong: () => toggleFav(i),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(
                        child: Stack(fit: StackFit.expand, children: [
                          i.icon.isEmpty
                              ? const Icon(Icons.movie, size: 40)
                              : Image.network(i.icon,
                                  fit: BoxFit.cover,
                                  cacheWidth: 220,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.movie, size: 40)),
                          if (favs.containsKey(i.id))
                            const Positioned(
                                top: 4,
                                right: 4,
                                child: Icon(Icons.favorite, size: 18, color: Colors.pinkAccent)),
                        ]),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(i.name,
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
