import 'package:dio/dio.dart';

import '../models/models.dart';
import 'api_client.dart';

class ApiService {
  final Dio _dio;
  final String serverUrl;

  ApiService(this.serverUrl) : _dio = buildDio(serverUrl);

  // ── Proxy helper ────────────────────────────────────────────────────────
  /// Routes external poster URLs through the backend proxy so they load on TV.
  String proxyImage(String url) {
    if (url.isEmpty) return '';
    final base = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
    if (url.startsWith(serverUrl)) return url;
    // Relative backend URL (e.g. /api/proxy-image?url=...) — just prepend server base
    if (url.startsWith('/')) return '$base$url';
    return '$base/api/proxy-image?url=${Uri.encodeComponent(url)}';
  }

  // ── Search ───────────────────────────────────────────────────────────────
  Future<List<SeriesResult>> search(String keyword, {String site = 'aniworld'}) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '/api/search',
      data: {'keyword': keyword, 'site': site},
    );
    final list = resp.data?['results'] as List? ?? [];
    return list
        .map((e) => SeriesResult.fromJson(e as Map<String, dynamic>))
        .map((r) => SeriesResult(title: r.title, url: r.url, posterUrl: proxyImage(r.posterUrl)))
        .toList();
  }

  // ── Browse ───────────────────────────────────────────────────────────────
  Future<List<SeriesResult>> _fetchBrowse(String path) async {
    final resp = await _dio.get<Map<String, dynamic>>(path);
    final list = resp.data?['results'] as List? ?? [];
    return list
        .map((e) => SeriesResult.fromJson(e as Map<String, dynamic>))
        .map((r) => SeriesResult(title: r.title, url: r.url, posterUrl: proxyImage(r.posterUrl)))
        .toList();
  }

  Future<List<SeriesResult>> getNewAnimes() => _fetchBrowse('/api/new-animes');
  Future<List<SeriesResult>> getPopularAnimes() => _fetchBrowse('/api/popular-animes');
  Future<List<SeriesResult>> getNewSeries() => _fetchBrowse('/api/new-series');
  Future<List<SeriesResult>> getPopularSeries() => _fetchBrowse('/api/popular-series');

  Future<String> getTmdbPoster(String title) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/api/tmdb-poster',
      queryParameters: {'title': title},
    );
    final url = resp.data?['poster_url'] as String? ?? '';
    return proxyImage(url); // relative /api/proxy-image?url=… → full http://host/…
  }

  Future<({List<SeriesResult> items, bool hasMore, int total, List<String> allGenres})> getAllAnimes(
          int page, {int perPage = 50, String? genre}) =>
      _fetchPaged('/api/all-animes', page, perPage, genre: genre);

  Future<({List<SeriesResult> items, bool hasMore, int total, List<String> allGenres})> getAllSeries(
          int page, {int perPage = 50, String? genre}) =>
      _fetchPaged('/api/all-series', page, perPage, genre: genre);

  Future<({List<SeriesResult> items, bool hasMore, int total, List<String> allGenres})> _fetchPaged(
      String path, int page, int perPage, {String? genre}) async {
    final params = <String, dynamic>{'page': page, 'per_page': perPage};
    if (genre != null && genre.isNotEmpty) params['genre'] = genre;
    final resp = await _dio.get<Map<String, dynamic>>(path, queryParameters: params);
    final data = resp.data!;
    final list = (data['results'] as List)
        .map((e) => SeriesResult.fromJson(e as Map<String, dynamic>))
        .toList();
    final allGenres = (data['all_genres'] as List?)?.cast<String>() ?? [];
    return (
      items: list,
      hasMore: data['has_more'] as bool,
      total: data['total'] as int,
      allGenres: allGenres,
    );
  }

  // ── Series metadata ──────────────────────────────────────────────────────
  Future<SeriesDetail> getSeriesDetail(String url) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/api/series',
      queryParameters: {'url': url},
    );
    final d = SeriesDetail.fromJson(resp.data!);
    return SeriesDetail(
      title: d.title,
      posterUrl: proxyImage(d.posterUrl),
      backdropUrl: proxyImage(d.backdropUrl),
      description: d.description,
      genres: d.genres,
      releaseYear: d.releaseYear,
    );
  }

  Future<List<Season>> getSeasons(String seriesUrl) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/api/seasons',
      queryParameters: {'url': seriesUrl},
    );
    final list = resp.data?['seasons'] as List? ?? [];
    return list.map((e) => Season.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Episode>> getEpisodes(String seasonUrl) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/api/episodes',
      queryParameters: {'url': seasonUrl},
    );
    final list = resp.data?['episodes'] as List? ?? [];
    final base = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
    return list.map((e) {
      final ep = e as Map<String, dynamic>;
      final raw = ep['preview_url'] as String?;
      if (raw != null && raw.isNotEmpty) {
        ep['preview_url'] = '$base$raw';
      }
      return Episode.fromJson(ep);
    }).toList();
  }

  Future<Map<String, List<String>>> getProviders(String episodeUrl) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/api/providers',
      queryParameters: {'url': episodeUrl},
    );
    final raw = resp.data?['providers'] as Map<String, dynamic>? ?? {};
    return raw.map((k, v) => MapEntry(k, List<String>.from(v as List)));
  }

  // ── Download queue ───────────────────────────────────────────────────────
  Future<int> enqueueDownload({
    required String title,
    required String seriesUrl,
    required List<String> episodeUrls,
    required String language,
    required String provider,
    int? customPathId,
  }) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '/api/download',
      data: {
        'title': title,
        'series_url': seriesUrl,
        'episodes': episodeUrls,
        'language': language,
        'provider': provider,
        if (customPathId case final id?) 'custom_path_id': id,
      },
    );
    return resp.data?['queue_id'] as int? ?? 0;
  }

  Future<({List<QueueItem> items, FfmpegProgress ffmpeg})> getQueue() async {
    final resp = await _dio.get<Map<String, dynamic>>('/api/queue');
    final rawItems = resp.data?['items'] as List? ?? [];
    final items = rawItems.map((e) => QueueItem.fromJson(e as Map<String, dynamic>)).toList();
    final progress = FfmpegProgress.fromJson(
      resp.data?['ffmpeg_progress'] as Map<String, dynamic>? ?? {},
    );
    return (items: items, ffmpeg: progress);
  }

  Future<void> cancelQueueItem(int id) =>
      _dio.post<void>('/api/queue/$id/cancel');

  Future<void> removeQueueItem(int id) =>
      _dio.delete<void>('/api/queue/$id');

  Future<void> clearCompleted() =>
      _dio.delete<void>('/api/queue/completed');

  Future<void> moveQueueItem(int id, String direction) =>
      _dio.post<void>('/api/queue/$id/move', data: {'direction': direction});

  // ── Streaming ────────────────────────────────────────────────────────────
  Future<String> getStreamUrl({
    required String folder,
    required int season,
    required int episode,
    int? customPathId,
  }) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/api/stream',
      queryParameters: {
        'folder': folder,
        'season': season,
        'episode': episode,
        if (customPathId case final id?) 'custom_path_id': id,
      },
    );
    return resp.data?['url'] as String? ?? '';
  }

  // ── Library ──────────────────────────────────────────────────────────────
  Future<List<LibraryTitle>> getLibrary() async {
    final resp = await _dio.get<Map<String, dynamic>>('/api/library');
    final locations = resp.data?['locations'] as List? ?? [];
    final titles = <LibraryTitle>[];
    for (final loc in locations) {
      final rawTitles = (loc as Map<String, dynamic>)['titles'] as List? ?? [];
      titles.addAll(rawTitles.map((e) => LibraryTitle.fromJson(e as Map<String, dynamic>)));
    }
    return titles;
  }

  Future<void> deleteFromLibrary({
    required String folder,
    int? season,
    int? episode,
    int? customPathId,
  }) async {
    await _dio.post<void>(
      '/api/library/delete',
      data: {
        'folder': folder,
        if (season case final s?) 'season': s,
        if (episode case final e?) 'episode': e,
        if (customPathId case final id?) 'custom_path_id': id,
      },
    );
  }

  // ── Watch Progress ───────────────────────────────────────────────────────
  Future<void> saveProgress({
    required String episodeUrl,
    String? seriesTitle,
    String? seriesUrl,
    int season = 0,
    int episodeNumber = 0,
    String? episodeTitle,
    required double positionSeconds,
    required double durationSeconds,
    bool completed = false,
    String? streamFile,
  }) async {
    await _dio.post<void>('/api/progress', data: {
      'episode_url': episodeUrl,
      'series_title': seriesTitle,
      'series_url': seriesUrl,
      'season': season,
      'episode_number': episodeNumber,
      'episode_title': episodeTitle,
      'position_seconds': positionSeconds,
      'duration_seconds': durationSeconds,
      'completed': completed,
      'stream_file': streamFile,
    });
  }

  Future<List<WatchProgress>> getAllProgress({bool continueOnly = false, int limit = 50}) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/api/progress',
      queryParameters: {
        if (continueOnly) 'continue': '1',
        'limit': limit,
      },
    );
    final list = resp.data?['progress'] as List? ?? [];
    final base = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
    return list.map((e) {
      final row = e as Map<String, dynamic>;
      final rawPreview = row['preview_url'] as String?;
      if (rawPreview != null && rawPreview.isNotEmpty) {
        row['preview_url'] = '$base$rawPreview';
      }
      final rawPoster = row['poster_url'] as String?;
      if (rawPoster != null && rawPoster.isNotEmpty && rawPoster.startsWith('/')) {
        row['poster_url'] = '$base$rawPoster';
      }
      return WatchProgress.fromJson(row);
    }).toList();
  }

  /// Fetches thumbnail sprite metadata, polling until ready (max ~90 s).
  Future<ThumbnailMeta?> getThumbnails({required String streamUrl}) async {
    const marker = '/api/stream/files/';
    final idx = streamUrl.indexOf(marker);
    if (idx < 0) return null;
    final filepath = Uri.decodeFull(streamUrl.substring(idx + marker.length));
    final base = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
    final spriteFilepath = filepath.replaceAll('.m3u8', '.thumbs.jpg');
    final spriteUrl = '$base/api/thumbnails/sprite/${Uri.encodeFull(spriteFilepath)}';

    for (int i = 0; i < 30; i++) {
      try {
        final resp = await _dio.get<Map<String, dynamic>>(
          '/api/thumbnails',
          queryParameters: {'filepath': filepath},
        );
        final data = resp.data ?? {};
        final status = data['status'] as String? ?? '';
        if (status == 'ready') return ThumbnailMeta.fromJson(data, spriteUrl: spriteUrl);
        if (status == 'generating') {
          await Future.delayed(const Duration(seconds: 3));
          continue;
        }
      } catch (_) {
        await Future.delayed(const Duration(seconds: 3));
      }
      break;
    }
    return null;
  }

  Future<SkipTimes> getSkipTimes({required String seriesTitle, required int episode}) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/api/skip-times',
      queryParameters: {'series_title': seriesTitle, 'episode': episode},
    );
    return SkipTimes.fromJson(resp.data ?? {});
  }

  // ── Autosync ──────────────────────────────────────────────────────────────
  /// Returns the job id if this series already has an autosync job, else null.
  Future<int?> checkAutosync(String seriesUrl) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/api/autosync/check',
      queryParameters: {'url': seriesUrl},
    );
    final exists = resp.data?['exists'] as bool? ?? false;
    if (!exists) return null;
    final job = resp.data?['job'] as Map<String, dynamic>?;
    return job?['id'] as int?;
  }

  Future<int> addAutosync(String seriesUrl, {required String title}) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '/api/autosync',
      data: {'title': title, 'series_url': seriesUrl},
    );
    return resp.data?['id'] as int? ?? 0;
  }

  Future<void> removeAutosync(int jobId) async {
    await _dio.delete<void>('/api/autosync/$jobId');
  }

  // ── Watchlist ─────────────────────────────────────────────────────────────
  Future<List<SeriesResult>> getWatchlist() async {
    final resp = await _dio.get<Map<String, dynamic>>('/api/watchlist');
    final list = resp.data?['items'] as List? ?? [];
    return list
        .map((e) => SeriesResult.fromJson(e as Map<String, dynamic>))
        .map((r) => SeriesResult(title: r.title, url: r.url, posterUrl: proxyImage(r.posterUrl)))
        .toList();
  }

  Future<void> addToWatchlist(String seriesUrl, {required String title, String posterUrl = ''}) async {
    await _dio.post<void>('/api/watchlist', data: {
      'series_url': seriesUrl,
      'series_title': title,
      'poster_url': posterUrl,
    });
  }

  Future<void> removeFromWatchlist(String seriesUrl) async {
    await _dio.delete<void>('/api/watchlist', data: {'series_url': seriesUrl});
  }

  Future<bool> isInWatchlist(String seriesUrl) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/api/watchlist/check',
      queryParameters: {'url': seriesUrl},
    );
    return resp.data?['in_list'] as bool? ?? false;
  }

  // ── Settings ─────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getSettings() async {
    final resp = await _dio.get<Map<String, dynamic>>('/api/settings');
    return resp.data ?? {};
  }
}
