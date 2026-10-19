import 'package:flutter/material.dart';
import 'core.dart';
import 'detail.dart';

/// One page of the dashboard: "Recently Added Movies / Series" (swipe left-right for the next title).
/// The dashboard itself scrolls up and down between Home, Recent Movies and Recent Series.
class RecentSlides extends StatefulWidget {
  final Session s;
  final String type; // movie | series
  const RecentSlides(this.s, this.type, {super.key});
  @override
  State<RecentSlides> createState() => _RecentSlidesState();
}

class _RecentSlidesState extends State<RecentSlides> {
  Session get s => widget.s;
  bool get movie => widget.type == 'movie';
  Lib get lib => movie ? s.movie : s.series;
  List<It>? items;
  final pc = PageController();
  final Map<String, Map> info = {};
  final Set<String> favs = {};
  int cur = 0;

  @override
  void initState() {
    super.initState();
    lib.tick.addListener(check);
    check();
    loadFavs();
  }

  @override
  void dispose() {
    lib.tick.removeListener(check);
    pc.dispose();
    super.dispose();
  }

  // The list is built once, when the library has finished loading
  void check() {
    if (items != null || !lib.full || lib.total == 0) return;
    final l = lib.recentAdded();
    if (!mounted) return;
    setState(() => items = l);
    fetch(0);
    fetch(1);
  }

  Future<void> loadFavs() async {
    final l = await loadList('fav_${widget.type}');
    if (mounted) setState(() => favs.addAll(l.map((e) => e.id)));
  }

  Future<void> fetch(int i) async {
    final l = items;
    if (l == null || i >= l.length) return;
    final it = l[i];
    if (info.containsKey(it.id)) return;
    info[it.id] = {};
    try {
      final m = await s.infoOf(movie ? 'get_vod_info' : 'get_series_info',
          movie ? '&vod_id=${it.id}' : '&series_id=${it.id}');
      final x = m['info'];
      if (mounted && x is Map) setState(() => info[it.id] = x);
    } catch (_) {}
  }

  Future<void> fav(It it) async {
    final on = await toggleFavOf(widget.type, it);
    if (!mounted) return;
    setState(() => on ? favs.add(it.id) : favs.remove(it.id));
  }

  void watch(It it) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => DetailPage(s, it, widget.type)));
  }

  Widget slide(List<It> l, int i) {
    final it = l[i];
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
    final mq = MediaQuery.of(context);
    final f = mq.size.height / 480, w = mq.size.width;
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
        padding: EdgeInsets.fromLTRB(w * 0.085, 100 * f, w * 0.075, 20 * f),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Column(mainAxisSize: MainAxisSize.min, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 180 * f,
                height: 253 * f,
                child: poster.isEmpty
                    ? Container(color: card)
                    : Image.network(poster,
                        fit: BoxFit.cover,
                        cacheWidth: 300,
                        errorBuilder: (_, __, ___) => Container(color: card)),
              ),
            ),
            SizedBox(height: 10 * f),
            Row(mainAxisSize: MainAxisSize.min, children: [
              for (var k = 0; k < 5; k++)
                Icon(Icons.star, size: 17 * f, color: k < stars ? Colors.amber : Colors.white24),
            ]),
          ]),
          SizedBox(width: 26 * f),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(cat.isEmpty ? it.name : '${it.name}  \u2022  $cat',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 22 * f, fontWeight: FontWeight.bold)),
                ),
                InkResponse(
                  onTap: () => fav(it),
                  child: Icon(favs.contains(it.id) ? Icons.favorite : Icons.favorite_border,
                      size: 46 * f, color: favs.contains(it.id) ? Colors.pinkAccent : Colors.white),
                ),
              ]),
              SizedBox(height: 6 * f),
              Text(plot,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 18 * f, color: Colors.white70, height: 1.2)),
              const Spacer(),
              SizedBox(width: 266 * f, child: GradBtn('Watch Now', () => watch(it), icon: Icons.play_arrow, height: 52 * f)),
            ]),
          ),
        ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext c) {
    final title = movie ? 'Recently Added Movies' : 'Recently Added Series';
    final l = items;
    if (l == null || l.isEmpty) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500)),
          const SizedBox(height: 16),
          const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 3, color: accent)),
        ]),
      );
    }
    final f = MediaQuery.of(c).size.height / 480;
    final start = (cur ~/ 11) * 11;
    final end = (start + 11) < l.length ? start + 11 : l.length;
    return Container(
      color: Colors.black,
      child: Stack(children: [
        PageView.builder(
          controller: pc,
          itemCount: l.length,
          onPageChanged: (i) {
            setState(() => cur = i);
            fetch(i);
            fetch(i + 1);
          },
          itemBuilder: (_, i) => slide(l, i),
        ),
        Positioned(
          top: 18 * f,
          left: 0,
          right: 0,
          child: Column(children: [
            Text(title, style: TextStyle(fontSize: 25 * f, fontWeight: FontWeight.w500)),
            SizedBox(height: 8 * f),
            Container(width: 280 * f, height: 2, color: Colors.white54),
          ]),
        ),
        Positioned(
          bottom: 12 * f,
          left: 0,
          right: 0,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var k = start; k < end; k++)
                Container(
                  margin: EdgeInsets.symmetric(horizontal: 8 * f),
                  width: (k == cur ? 17 : 12) * f,
                  height: (k == cur ? 17 : 12) * f,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: k == cur ? Colors.lightBlueAccent : Colors.white70),
                ),
            ]),
            const SizedBox(height: 4),
            Text('${cur + 1} of ${l.length} Records',
                style: TextStyle(fontSize: 18 * f, fontWeight: FontWeight.w500)),
          ]),
        ),
      ]),
    );
  }
}
