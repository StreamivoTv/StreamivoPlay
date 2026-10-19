import 'dart:async';
import 'package:flutter/material.dart';
import 'core.dart';
import 'detail.dart';
import 'main.dart';

/// "Recently Added Movies / Series" shown right after login: poster, story, rating,
/// Watch Now and favourite. It moves on by itself (movies -> series -> dashboard) and can be skipped.
class RecentShow extends StatefulWidget {
  final Session s;
  final String type; // movie | series
  const RecentShow(this.s, this.type, {super.key});
  @override
  State<RecentShow> createState() => _RecentShowState();
}

class _RecentShowState extends State<RecentShow> {
  Session get s => widget.s;
  bool get movie => widget.type == 'movie';
  Lib get lib => movie ? s.movie : s.series;
  late final List<It> items = lib.recentAdded();
  final pc = PageController();
  final Map<String, Map> info = {};
  final Set<String> favs = {};
  int cur = 0, ticks = 0;
  Timer? t;

  @override
  void initState() {
    super.initState();
    if (items.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => next());
      return;
    }
    loadFavs();
    fetch(0);
    fetch(1);
    t = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      ticks++;
      if (ticks >= 3) {
        next();
      } else {
        pc.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    t?.cancel();
    pc.dispose();
    super.dispose();
  }

  Future<void> loadFavs() async {
    final l = await loadList('fav_${widget.type}');
    if (mounted) setState(() => favs.addAll(l.map((e) => e.id)));
  }

  Future<void> fetch(int i) async {
    if (i >= items.length) return;
    final it = items[i];
    if (info.containsKey(it.id)) return;
    info[it.id] = {};
    try {
      final m = await s.infoOf(movie ? 'get_vod_info' : 'get_series_info',
          movie ? '&vod_id=${it.id}' : '&series_id=${it.id}');
      final x = m['info'];
      if (mounted && x is Map) setState(() => info[it.id] = x);
    } catch (_) {}
  }

  void next() {
    t?.cancel();
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (movie && s.series.full && s.series.total > 0) {
      nav.pushReplacement(MaterialPageRoute(builder: (_) => RecentShow(s, 'series')));
    } else {
      openHome(nav, s);
    }
  }

  void skip() {
    t?.cancel();
    openHome(Navigator.of(context), s);
  }

  Future<void> fav(It it) async {
    final on = await toggleFavOf(widget.type, it);
    if (!mounted) return;
    setState(() => on ? favs.add(it.id) : favs.remove(it.id));
  }

  Future<void> watch(It it) async {
    t?.cancel();
    await Navigator.push(context, MaterialPageRoute(builder: (_) => DetailPage(s, it, widget.type)));
  }

  Widget slide(int i) {
    final it = items[i];
    final inf = info[it.id] ?? const {};
    final plot = clean(inf['plot'] ?? inf['description']);
    var back = '';
    final bp = inf['backdrop_path'];
    if (bp is List && bp.isNotEmpty) {
      back = clean(bp.first);
    } else if (bp is String) {
      back = clean(bp);
    }
    final poster = it.icon.isNotEmpty ? it.icon : clean(inf['movie_image'] ?? inf['cover']);
    final r5 = double.tryParse(clean(inf['rating_5based'])) ??
        ((double.tryParse(clean(inf['rating'])) ?? 0) / 2);
    final stars = r5.round().clamp(0, 5);
    final cat = lib.catName(it.cat);
    final bgUrl = back.isNotEmpty ? back : poster;
    return Stack(fit: StackFit.expand, children: [
      if (bgUrl.isNotEmpty)
        Image.network(bgUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox())
      else
        const SizedBox(),
      const DecoratedBox(
        decoration: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xE6000000), Color(0x99000000), Color(0x40000000)])),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(44, 62, 44, 56),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Column(mainAxisSize: MainAxisSize.min, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 120,
                height: 175,
                child: poster.isEmpty
                    ? Container(color: card)
                    : Image.network(poster,
                        fit: BoxFit.cover,
                        cacheWidth: 300,
                        errorBuilder: (_, __, ___) => Container(color: card)),
              ),
            ),
            const SizedBox(height: 8),
            Row(mainAxisSize: MainAxisSize.min, children: [
              for (var k = 0; k < 5; k++)
                Icon(Icons.star, size: 18, color: k < stars ? Colors.amber : Colors.white24),
            ]),
          ]),
          const SizedBox(width: 22),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(cat.isEmpty ? it.name : '${it.name}  \u2022  $cat',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                ),
                InkResponse(
                  onTap: () => fav(it),
                  child: Icon(favs.contains(it.id) ? Icons.favorite : Icons.favorite_border,
                      size: 38, color: favs.contains(it.id) ? Colors.pinkAccent : Colors.white),
                ),
              ]),
              const SizedBox(height: 6),
              Text(plot,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: Colors.white70, height: 1.25)),
              const Spacer(),
              SizedBox(width: 190, child: GradBtn('Watch Now', () => watch(it), icon: Icons.play_arrow, height: 42)),
            ]),
          ),
        ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext c) {
    if (items.isEmpty) return const Scaffold(backgroundColor: Colors.black);
    final start = (cur ~/ 11) * 11;
    final end = (start + 11) < items.length ? start + 11 : items.length;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) skip();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          PageView.builder(
            controller: pc,
            itemCount: items.length,
            onPageChanged: (i) {
              setState(() => cur = i);
              fetch(i);
              fetch(i + 1);
            },
            itemBuilder: (_, i) => slide(i),
          ),
          Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: Column(children: [
              Text(movie ? 'Recently Added Movies' : 'Recently Added Series',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              Container(width: 230, height: 2, color: Colors.white54),
            ]),
          ),
          Positioned(
            top: 8,
            right: 14,
            child: TextButton(
                onPressed: skip,
                child: const Text('SKIP', style: TextStyle(color: Colors.white70, letterSpacing: 1.5))),
          ),
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var k = start; k < end; k++)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    width: k == cur ? 14 : 9,
                    height: k == cur ? 14 : 9,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: k == cur ? Colors.lightBlueAccent : Colors.white70),
                  ),
              ]),
              const SizedBox(height: 4),
              Text('${cur + 1} of ${items.length} Records',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            ]),
          ),
        ]),
      ),
    );
  }
}
