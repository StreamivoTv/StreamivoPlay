import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'core.dart';
import 'player.dart';

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
  Lib get lib => isSeries ? s.series : s.movie;

  Map info = {};
  Map<String, List> seasons = {};
  String season = '';
  String movieExt = '';
  bool loading = true, fav = false;
  String? error;
  List<Map> tmdb = [];

  @override
  void initState() {
    super.initState();
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
    final c = await tmdbCast(isSeries ? 'tv' : 'movie', clean(info['tmdb_id'] ?? info['tmdb']));
    if (mounted && c.isNotEmpty) setState(() => tmdb = c);
  }

  String pick(List<String> keys) {
    for (final k in keys) {
      final v = clean(info[k]);
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  String get back {
    final b = info['backdrop_path'];
    if (b is List) return b.isEmpty ? '' : clean(b.first);
    return clean(b);
  }

  String get date {
    final d = pick(['releasedate', 'releaseDate', 'release_date']);
    final p = d.split('-');
    return p.length == 3 && p[0].length == 4 ? '${p[2]}-${p[1]}-${p[0]}' : d;
  }

  String get duration {
    final d = pick(['duration']);
    if (d.isNotEmpty) return d;
    final r = pick(['episode_run_time']);
    return r.isEmpty ? '' : '$r min';
  }

  List<Pi> eps(String k) {
    final out = <Pi>[];
    for (final e in (seasons[k] ?? <dynamic>[])) {
      if (e is! Map) continue;
      final t = clean(e['title']);
      final x = clean(e['container_extension']);
      out.add(Pi(t.isEmpty ? it.name : t, s.seriesUrl('${e['id']}', x.isEmpty ? 'mp4' : x)));
    }
    return out;
  }

  Future<void> watch(List<Pi> list, int idx) async {
    await addRecentTo(widget.type, it);
    if (!mounted) return;
    await playItems(context, s, list, idx, false);
  }

  void watchNow() {
    if (isSeries) {
      final l = eps(season);
      if (l.isNotEmpty) watch(l, 0);
    } else {
      final ext = movieExt.isEmpty ? it.ext : movieExt;
      watch([Pi(it.name, s.movieUrl(it.id, ext))], 0);
    }
  }

  Future<void> toggleFav() async {
    final now = await toggleFavOf(widget.type, it);
    if (mounted) setState(() => fav = now);
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

  @override
  Widget build(BuildContext c) {
    final pos = pick(isSeries ? ['cover', 'movie_image'] : ['movie_image', 'cover']);
    final poster = pos.isEmpty ? it.icon : pos;
    final bk = back;
    final genres = pick(['genre'])
        .split(RegExp(r'[,/|]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final castNames = pick(['cast', 'actors']);
    final plot = pick(['plot', 'description']);
    final meta = [duration, date].where((e) => e.isNotEmpty).join('   ·   ');
    final el = isSeries ? eps(season) : <Pi>[];
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(
          child: bk.isEmpty
              ? Container(color: bg)
              : ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Image.network(bk,
                      fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: bg)),
                ),
        ),
        Positioned.fill(child: Container(color: Colors.black.withAlpha(185))),
        SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(children: [rb(Icons.arrow_back, () => Navigator.pop(context))]),
            ),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 130,
                              height: 195,
                              child: poster.isEmpty
                                  ? Container(color: card, child: const Icon(Icons.movie, size: 40))
                                  : Image.network(poster,
                                      fit: BoxFit.cover,
                                      cacheWidth: 300,
                                      errorBuilder: (_, __, ___) =>
                                          Container(color: card, child: const Icon(Icons.movie))),
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(lib.catName(it.cat).toUpperCase(),
                                  style: const TextStyle(
                                      fontSize: 13, letterSpacing: 2, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              Text(it.name,
                                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                              if (meta.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(meta, style: const TextStyle(fontSize: 15, color: Colors.white70)),
                              ],
                              if (genres.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Wrap(spacing: 8, runSpacing: 8, children: [
                                  for (final g in genres)
                                    Container(
                                      padding:
                                          const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                      decoration: BoxDecoration(
                                          border: Border.all(color: Colors.white38),
                                          borderRadius: BorderRadius.circular(20)),
                                      child: Text(g, style: const TextStyle(fontSize: 13)),
                                    ),
                                ]),
                              ],
                              if (castNames.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Text.rich(
                                  TextSpan(children: [
                                    const TextSpan(
                                        text: 'Cast:  ',
                                        style: TextStyle(fontWeight: FontWeight.bold)),
                                    TextSpan(text: castNames),
                                  ]),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ],
                              const SizedBox(height: 16),
                              Wrap(spacing: 12, runSpacing: 10, children: [
                                SizedBox(
                                    width: 170,
                                    child: GradBtn('Watch Now', watchNow, icon: Icons.play_arrow)),
                                SizedBox(
                                  width: 230,
                                  child: GradBtn(
                                      fav ? 'Remove from Favourite' : 'Add to Favourite', toggleFav,
                                      outline: true, icon: Icons.favorite),
                                ),
                              ]),
                            ]),
                          ),
                        ]),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(error!, style: const TextStyle(color: Colors.redAccent)),
                          ),
                        if (isSeries && seasons.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Wrap(spacing: 8, children: [
                            for (final k in seasons.keys)
                              ChoiceChip(
                                label: Text('Season $k'),
                                selected: season == k,
                                onSelected: (_) => setState(() => season = k),
                              ),
                          ]),
                          const SizedBox(height: 8),
                          for (var i = 0; i < el.length; i++)
                            ListTile(
                              leading: Text('${i + 1}', style: const TextStyle(fontSize: 16)),
                              title: Text(el[i].title),
                              trailing: const Icon(Icons.play_arrow),
                              onTap: () => watch(el, i),
                            ),
                        ],
                        castSection(castNames),
                        if (plot.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          Text(plot, style: const TextStyle(fontSize: 15, height: 1.35)),
                        ],
                      ]),
                    ),
            ),
          ]),
        ),
      ]),
    );
  }
}
