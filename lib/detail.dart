import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'core.dart';
import 'fx.dart';
import 'main.dart';
import 'player.dart';
import 'settings.dart';

class _Ep {
  final String title, thumb, plot, dur, no;
  final Pi pi;
  const _Ep(this.title, this.thumb, this.plot, this.dur, this.no, this.pi);
}

String _hms(int s) {
  String t(int n) => n.toString().padLeft(2, '0');
  return '${t(s ~/ 3600)}:${t((s % 3600) ~/ 60)}:${t(s % 60)}';
}

class DetailPage extends StatefulWidget {
  final Session s;
  final It it;
  final String type; // movie | series
  const DetailPage(this.s, this.it, this.type, {super.key});
  @override
  State<DetailPage> createState() => _DetailState();
}

class _DetailState extends State<DetailPage> {
  Session get s => widget.s;
  It get it => widget.it;
  bool get isSeries => widget.type == 'series';

  Map info = {};
  Map<String, List> seasons = {};
  String season = '';
  String movieExt = '';
  bool loading = true, fav = false;
  String? error;
  List<Map> tmdb = [];
  Map<String, String> art = {};

  @override
  void initState() {
    super.initState();
    init();
  }

  void reload() {
    setState(() {
      loading = true;
      error = null;
      tmdb = [];
      art = {};
    });
    init();
  }

  Future<void> init() async {
    try {
      final m = await s.infoOf(isSeries ? 'get_series_info' : 'get_vod_info',
          isSeries ? '&series_id=${it.id}' : '&vod_id=${it.id}');
      info = m['info'] is Map ? m['info'] as Map : {};
      if (isSeries) {
        final e = m['episodes'];
        final tmp = <String, List>{};
        if (e is Map) {
          e.forEach((k, v) {
            if (v is List) tmp['$k'] = v;
          });
        } else if (e is List) {
          for (var i = 0; i < e.length; i++) {
            if (e[i] is List) tmp['${i + 1}'] = e[i] as List;
          }
        }
        final keys = tmp.keys.toList()
          ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
        seasons = {for (final k in keys) k: tmp[k]!};
        if (keys.isNotEmpty) season = keys.first;
      } else {
        final md = m['movie_data'];
        if (md is Map) movieExt = clean(md['container_extension']);
      }
    } catch (_) {
      error = 'Failed to load details.';
    }
    final fl = await loadList('fav_${widget.type}');
    fav = fl.any((x) => x.id == it.id);
    if (mounted) setState(() => loading = false);
    final tid = clean(info['tmdb_id'] ?? info['tmdb']);
    final kind = isSeries ? 'tv' : 'movie';
    final c = await tmdbCast(kind, tid);
    if (mounted && c.isNotEmpty) setState(() => tmdb = c);
    if (mounted && coverUrl.isEmpty) {
      final a = await tmdbArt(kind, tid, it.name);
      if (mounted && a.isNotEmpty) setState(() => art = a);
    }
  }

  String pick(List<String> keys) {
    for (final k in keys) {
      final v = clean(info[k]);
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  // Poster given by the provider (empty when there is none)
  String get coverUrl {
    final p = pick(isSeries ? ['cover', 'movie_image'] : ['movie_image', 'cover']);
    return p.isNotEmpty ? p : it.icon;
  }

  String get posterUrl => coverUrl.isNotEmpty ? coverUrl : (art['poster'] ?? '');

  String get back {
    final b = info['backdrop_path'];
    final v = b is List ? (b.isEmpty ? '' : clean(b.first)) : clean(b);
    return v.isNotEmpty ? v : (art['back'] ?? '');
  }

  String get year {
    final d = pick(['releasedate', 'releaseDate', 'release_date', 'year']);
    final m = RegExp(r'(19|20)\d{2}').firstMatch(d);
    if (m != null) return m.group(0)!;
    final n = RegExp(r'\(((?:19|20)\d{2})\)').firstMatch(it.name);
    return n?.group(1) ?? '';
  }

  String get duration {
    final d = pick(['duration']);
    if (d.isNotEmpty) return d;
    final r = pick(['episode_run_time']);
    return r.isEmpty ? '' : '$r min';
  }

  List<_Ep> eps(String k) {
    final out = <_Ep>[];
    for (final e in (seasons[k] ?? <dynamic>[])) {
      if (e is! Map) continue;
      final inf = e['info'] is Map ? e['info'] as Map : {};
      final n = clean(e['episode_num']).isEmpty ? '${out.length + 1}' : clean(e['episode_num']);
      var t = clean(e['title']);
      if (t.isEmpty) t = 'Episode $n';
      final x = clean(e['container_extension']);
      final xe = x.isEmpty ? 'mp4' : x;
      var dur = clean(inf['duration']);
      if (dur.isEmpty) dur = _hms(int.tryParse(clean(inf['duration_secs'])) ?? 0);
      out.add(_Ep(
          t,
          clean(inf['movie_image']),
          clean(inf['plot']),
          dur,
          n,
          Pi(t, s.seriesUrl('${e['id']}', xe),
              s.seriesUrl('${e['id']}', xe == 'mp4' ? 'mkv' : 'mp4'))));
    }
    return out;
  }

  Future<void> watch(List<Pi> list, int idx) async {
    await addRecentTo(widget.type, it);
    if (!mounted) return;
    await playItems(context, s, list, idx, false, kind: widget.type);
  }

  void watchNow() {
    if (isSeries) {
      if (seasons.isEmpty) return;
      final l = eps(seasons.keys.first);
      if (l.isNotEmpty) watch([for (final e in l) e.pi], 0);
    } else {
      final ext = movieExt.isEmpty ? it.ext : movieExt;
      final ex = ext.isEmpty ? 'mp4' : ext;
      watch([Pi(it.name, s.movieUrl(it.id, ex), s.movieUrl(it.id, ex == 'mp4' ? 'mkv' : 'mp4'))], 0);
    }
  }

  Future<void> toggleFav() async {
    final now = await toggleFavOf(widget.type, it);
    if (mounted) setState(() => fav = now);
  }

  String get playLabel {
    if (!isSeries) return 'Play';
    if (seasons.isEmpty) return 'Play S1 E1';
    final k = seasons.keys.first;
    final l = eps(k);
    return 'Play S$k E${l.isEmpty ? 1 : l.first.no}';
  }

  Widget castSection(String castNames) {
    final List<Map<String, String>> people = tmdb.isNotEmpty
        ? [
            for (final e in tmdb)
              {
                'name': clean(e['name']),
                'role': clean(e['character']),
                'photo': clean(e['profile_path']).isEmpty
                    ? ''
                    : 'https://image.tmdb.org/t/p/w185${e['profile_path']}',
              }
          ]
        : [
            for (final n in castNames.split(','))
              if (n.trim().isNotEmpty) {'name': n.trim(), 'role': '', 'photo': ''}
          ];
    if (people.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 22),
      const Text('Cast', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      SizedBox(
        height: 140,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: people.length,
          itemBuilder: (_, i) {
            final p = people[i];
            final photo = p['photo']!;
            final name = p['name']!;
            return SizedBox(
              width: 104,
              child: Column(children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: Colors.white12,
                  backgroundImage: photo.isEmpty ? null : NetworkImage(photo),
                  child: photo.isEmpty
                      ? Text(name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
                          style: const TextStyle(fontSize: 22))
                      : null,
                ),
                const SizedBox(height: 8),
                Text(name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                if (p['role']!.isNotEmpty)
                  Text(p['role']!,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.white54)),
              ]),
            );
          },
        ),
      ),
    ]);
  }

  Widget backdrop() {
    final b = back, p = posterUrl;
    final url = b.isNotEmpty ? b : p;
    if (url.isEmpty) return Opacity(opacity: 0.55, child: const NoPoster());
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
      child: Image.network(url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Opacity(opacity: 0.55, child: const NoPoster())),
    );
  }

  Widget seasonTabs() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final k in seasons.keys)
            InkWell(
              onTap: () => setState(() => season = k),
              focusColor: Colors.white12,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text.rich(TextSpan(children: [
                    TextSpan(
                        text: 'SEASON $k',
                        style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: season == k ? Colors.white : Colors.white60)),
                    TextSpan(
                        text: '  (${seasons[k]!.length})',
                        style: const TextStyle(fontSize: 15, color: Colors.white54)),
                  ])),
                  const SizedBox(height: 8),
                  Container(
                      height: 3,
                      width: 46,
                      color: season == k ? const Color(0xFFE53935) : Colors.transparent),
                ]),
              ),
            ),
        ]),
      );

  Widget epRow(List<_Ep> l, int i) {
    final e = l[i];
    final th = e.thumb.isNotEmpty ? e.thumb : posterUrl;
    return InkWell(
      onTap: () => watch([for (final x in l) x.pi], i),
      focusColor: Colors.white12,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white12))),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 170,
              height: 98,
              child: Stack(fit: StackFit.expand, children: [
                th.isEmpty
                    ? Container(color: card)
                    : Image.network(th,
                        fit: BoxFit.cover,
                        cacheWidth: 360,
                        errorBuilder: (_, __, ___) => Container(color: card)),
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: Colors.black87, borderRadius: BorderRadius.circular(8)),
                    child: Text('EP ${e.no}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 4),
              Row(children: [
                Text('Season $season', style: const TextStyle(fontSize: 14, color: Colors.white60)),
                Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 4,
                    height: 4,
                    color: Colors.white60),
                const Icon(Icons.schedule, size: 16, color: Colors.white60),
                const SizedBox(width: 4),
                Text(e.dur, style: const TextStyle(fontSize: 14, color: Colors.white60)),
              ]),
              const SizedBox(height: 4),
              Text(e.plot.isEmpty ? 'No description available.' : e.plot,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, color: Colors.white38)),
            ]),
          ),
          const SizedBox(width: 12),
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: fxGrad),
            child: const Icon(Icons.play_arrow, size: 26),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    final poster = posterUrl;
    final castNames = pick(['cast', 'actors']);
    final plot = pick(['plot', 'description']);
    final meta = isSeries
        ? [year, seasons.isEmpty ? '' : '${seasons.length} Seasons'].where((e) => e.isNotEmpty).join('·')
        : [year, duration].where((e) => e.isNotEmpty).join('·');
    final el = isSeries && season.isNotEmpty ? eps(season) : <_Ep>[];
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: Row(children: [
              rb(Icons.arrow_back, () => Navigator.pop(c)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(it.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18)),
              ),
              rb(Icons.home, () => Navigator.popUntil(c, (r) => r.isFirst)),
              rb(Icons.sync, reload),
              rb(Icons.settings,
                  () => Navigator.push(c, MaterialPageRoute(builder: (_) => const SettingsPage()))),
              rb(Icons.logout, () => doLogout(c)),
            ]),
          ),
          Expanded(
            child: Stack(children: [
              Positioned.fill(child: backdrop()),
              Positioned.fill(child: Container(color: Colors.black.withAlpha(110))),
              Positioned.fill(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: SizedBox(
                                width: 150,
                                height: 225,
                                child: poster.isEmpty
                                    ? const NoPoster()
                                    : Image.network(poster,
                                        fit: BoxFit.cover,
                                        cacheWidth: 340,
                                        errorBuilder: (_, __, ___) => const NoPoster()),
                              ),
                            ),
                            const SizedBox(width: 26),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(it.name,
                                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                                if (meta.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Text(meta, style: const TextStyle(fontSize: 17)),
                                ],
                                if (plot.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Text(plot,
                                      maxLines: 5,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 16, height: 1.35)),
                                ],
                                if (error != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 10),
                                    child: Text(error!, style: const TextStyle(color: Colors.redAccent)),
                                  ),
                                const SizedBox(height: 16),
                                Wrap(spacing: 12, runSpacing: 10, children: [
                                  SizedBox(
                                      width: 200,
                                      child: GradBtn(playLabel, watchNow, icon: Icons.play_arrow)),
                                  SizedBox(
                                    width: 250,
                                    child: GradBtn(fav ? 'Remove Favourite' : 'Add to Favourite', toggleFav,
                                        outline: true, icon: Icons.favorite),
                                  ),
                                ]),
                              ]),
                            ),
                          ]),
                          if (isSeries && seasons.isNotEmpty) ...[
                            const SizedBox(height: 26),
                            seasonTabs(),
                            const Divider(color: Colors.white24, height: 1),
                            const Padding(
                              padding: EdgeInsets.fromLTRB(4, 22, 0, 8),
                              child: Text('EPISODES',
                                  style: TextStyle(fontSize: 18, letterSpacing: 0.5)),
                            ),
                            for (var i = 0; i < el.length; i++) epRow(el, i),
                          ],
                          castSection(castNames),
                        ]),
                      ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
