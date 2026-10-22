import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'core.dart';
import 'fx.dart';
import 'main.dart' show doLogout;
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
  final List<It> siblings; // the list the movie was opened from (for the previous / next buttons)
  const DetailPage(this.s, this.it, this.type, {this.siblings = const [], super.key});
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

  static final Map<String, Map> _cache = {};
  String get _ck => '${widget.type}_${it.id}';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    uiBusy++; // background indexing waits while this page is open
    _busy = true;
    init();
  }

  @override
  void dispose() {
    if (_busy) uiBusy--;
    super.dispose();
  }

  void reload() {
    _cache.remove(_ck);
    setState(() {
      loading = true;
      error = null;
      tmdb = [];
      art = {};
    });
    init();
  }

  Future<Map> _fetchInfo() async {
    for (var a = 0; a < 2; a++) {
      try {
        return await s.infoOf(isSeries ? 'get_series_info' : 'get_vod_info',
            isSeries ? '&series_id=${it.id}' : '&vod_id=${it.id}');
      } catch (_) {
        if (a == 1) rethrow;
      }
    }
    return {};
  }

  Future<void> init() async {
    try {
      var m = _cache[_ck];
      if (m == null) {
        m = await _fetchInfo();
        if (m.isNotEmpty) _cache[_ck] = m;
      }
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
      error = null;
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

  String _p2(String x) => x.padLeft(2, '0');

  // Full release date as dd-mm-yyyy (falls back to the year only when that is all there is)
  String get relDate {
    final d = pick(['releasedate', 'releaseDate', 'release_date']);
    final a = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(d);
    if (a != null) return '${_p2(a.group(3)!)}-${_p2(a.group(2)!)}-${a.group(1)}';
    final b = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})').firstMatch(d);
    if (b != null) return '${_p2(b.group(1)!)}-${_p2(b.group(2)!)}-${b.group(3)}';
    return year;
  }

  List<String> get genres {
    final g = pick(['genre']);
    return [
      for (final x in g.split(RegExp(r'[,/|]')))
        if (x.trim().isNotEmpty) x.trim()
    ].take(4).toList();
  }

  String get catLabel => (isSeries ? s.series : s.movie).catName(it.cat).trim();

  String get duration {
    final d = pick(['duration']);
    if (d.isNotEmpty) return d;
    final r = pick(['episode_run_time']);
    return r.isEmpty ? '' : '$r min';
  }

  String get tmdbId => clean(info['tmdb_id'] ?? info['tmdb']);

  // every episode of every season, in order (the player's previous / next buttons walk through it)
  List<_Ep> allEps() => [for (final k in seasons.keys) ...eps(k)];

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
              s.seriesUrl('${e['id']}', xe == 'mp4' ? 'mkv' : 'mp4'), '${e['id']}', {
            'series': it.name,
            'tmdb': tmdbId,
            'season': k,
            'episode': n,
          })));
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
      final l = allEps();
      if (l.isNotEmpty) watch([for (final e in l) e.pi], 0);
    } else {
      Pi mk(It x, String ext, Map<String, String> m) {
        final ex = ext.isEmpty ? 'mp4' : ext;
        return Pi(x.name, s.movieUrl(x.id, ex), s.movieUrl(x.id, ex == 'mp4' ? 'mkv' : 'mp4'), x.id, m);
      }

      // the movie list it was opened from: back / forward in the player go to the previous / next movie
      final sib = widget.siblings;
      final at = sib.indexWhere((x) => x.id == it.id);
      final list = <Pi>[];
      var idx = 0;
      if (at >= 0) {
        for (var i = 0; i < sib.length; i++) {
          final x = sib[i];
          if (x.id == it.id) {
            idx = list.length;
            list.add(mk(x, movieExt.isEmpty ? it.ext : movieExt, {'tmdb': tmdbId, 'year': year, 'name': it.name}));
          } else {
            list.add(mk(x, x.ext, {'name': x.name}));
          }
        }
      } else {
        list.add(mk(it, movieExt.isEmpty ? it.ext : movieExt, {'tmdb': tmdbId, 'year': year, 'name': it.name}));
      }
      watch(list, idx);
    }
  }

  Future<void> toggleFav() async {
    final now = await toggleFavOf(widget.type, it);
    if (mounted) setState(() => fav = now);
  }

  String get playLabel {
    if (isSeries && seasons.isNotEmpty) {
      final k = seasons.keys.first;
      final l = eps(k);
      if (l.isNotEmpty) return 'Play S$k E${l.first.no}';
    }
    return 'Watch Now';
  }

  // 0..5 stars from the provider's rating (5-based when given, else the 10-based one halved)
  double get stars {
    final r5 = double.tryParse(pick(['rating_5based']));
    if (r5 != null && r5 > 0) return r5.clamp(0, 5).toDouble();
    final r10 = double.tryParse(pick(['rating']));
    if (r10 != null && r10 > 0) return (r10 / 2).clamp(0, 5).toDouble();
    return it.rating > 0 ? (it.rating / 2).clamp(0, 5).toDouble() : 0;
  }

  Widget starRow(double v, {double size = 22}) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var k = 0; k < 5; k++)
          Icon(v >= k + 0.75 ? Icons.star : (v >= k + 0.25 ? Icons.star_half : Icons.star_border),
              size: size,
              color: v >= k + 0.25 ? Colors.amber : Colors.white38),
      ]);

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
      onTap: () {
        final all = allEps();
        final at = all.indexWhere((x) => x.pi.id == e.pi.id);
        if (at >= 0) {
          watch([for (final x in all) x.pi], at);
        } else {
          watch([for (final x in l) x.pi], i);
        }
      },
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

  Widget chip(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
            border: Border.all(color: Colors.white38), borderRadius: BorderRadius.circular(24)),
        child: Text(t, style: const TextStyle(fontSize: 15)),
      );

  Widget storySection(String plot) {
    if (plot.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 22),
      const Text('Story', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      Text(plot, style: const TextStyle(fontSize: 16, height: 1.4, color: Colors.white70)),
    ]);
  }

  @override
  Widget build(BuildContext c) {
    final poster = posterUrl;
    final castNames = pick(['cast', 'actors']);
    final plot = pick(['plot', 'description']);
    final date = relDate;
    final meta = isSeries
        ? [seasons.isEmpty ? '' : '${seasons.length} Seasons', date]
            .where((e) => e.isNotEmpty)
            .join('  ·  ')
        : [duration, date].where((e) => e.isNotEmpty).join('  ·  ');
    final el = isSeries && season.isNotEmpty ? eps(season) : <_Ep>[];
    final cat = catLabel;
    final gl = genres;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          // top bar: only the back button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: Row(children: [
              rb(Icons.arrow_back, () => Navigator.pop(c)),
              if (isSeries) ...[
                const SizedBox(width: 14),
                Expanded(
                  child: Text(it.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 20)),
                ),
                rb(Icons.home, () => Navigator.of(c).popUntil((r) => r.isFirst)),
                rb(Icons.sync, reload),
                rb(Icons.settings, () => Navigator.push(
                    c, MaterialPageRoute(builder: (_) => const SettingsPage()))),
                rb(Icons.logout, () => doLogout(c)),
              ],
            ]),
          ),
          Expanded(
            child: Stack(children: [
              Positioned.fill(child: backdrop()),
              Positioned.fill(child: Container(color: Colors.black.withAlpha(110))),
              Positioned.fill(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 18, 28, 28),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: SizedBox(
                          width: 170,
                          height: 255,
                          child: PosterImg(poster, cacheW: 400),
                        ),
                      ),
                      const SizedBox(width: 26),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (!isSeries && cat.isNotEmpty)
                            Text(cat.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2,
                                    color: Colors.white70)),
                          if (!isSeries) const SizedBox(height: 6),
                          Text(it.name,
                              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                          if (isSeries) ...[
                            // like the reference: year · genres · seasons, then the stars
                            const SizedBox(height: 10),
                            Text(
                                [
                                  year,
                                  gl.join(', '),
                                  seasons.isEmpty ? '' : '${seasons.length} Seasons'
                                ].where((e) => e.isNotEmpty).join('·'),
                                style: const TextStyle(fontSize: 18, color: Colors.white70)),
                            if (stars > 0) ...[
                              const SizedBox(height: 6),
                              starRow(stars),
                            ],
                            if (plot.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Text(plot,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 17, height: 1.35)),
                            ],
                            if (pick(['director']).isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text.rich(
                                TextSpan(children: [
                                  const TextSpan(
                                      text: 'Director: ',
                                      style: TextStyle(fontWeight: FontWeight.bold)),
                                  TextSpan(text: pick(['director'])),
                                ]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 16),
                              ),
                            ],
                            if (castNames.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text.rich(
                                TextSpan(children: [
                                  const TextSpan(
                                      text: 'Cast: ',
                                      style: TextStyle(fontWeight: FontWeight.bold)),
                                  TextSpan(text: castNames),
                                ]),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 16),
                              ),
                            ],
                          ],
                          if (!isSeries) ...[
                            if (meta.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(meta, style: const TextStyle(fontSize: 18, color: Colors.white70)),
                            ],
                            if (gl.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Wrap(spacing: 10, runSpacing: 8, children: [for (final g in gl) chip(g)]),
                            ],
                            if (castNames.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Text.rich(
                                TextSpan(children: [
                                  const TextSpan(
                                      text: 'Cast:  ',
                                      style: TextStyle(fontWeight: FontWeight.bold)),
                                  TextSpan(text: castNames),
                                ]),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 15),
                              ),
                            ],
                          ],
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text(error!, style: const TextStyle(color: Colors.redAccent)),
                                TextButton(onPressed: reload, child: const Text('RETRY')),
                              ]),
                            ),
                          const SizedBox(height: 18),
                          Wrap(spacing: 12, runSpacing: 10, children: [
                            SizedBox(
                                width: 230,
                                child: GradBtn(playLabel, watchNow,
                                    icon: Icons.play_arrow, busy: isSeries && loading)),
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
                        child: Text('EPISODES', style: TextStyle(fontSize: 18, letterSpacing: 0.5)),
                      ),
                      for (var i = 0; i < el.length; i++) epRow(el, i),
                    ],
                    castSection(castNames),
                    if (!isSeries) storySection(plot),
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
