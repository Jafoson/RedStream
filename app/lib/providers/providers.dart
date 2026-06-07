import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_service.dart';
import '../models/models.dart';
import '../navigation/app_nav.dart';

// ---------------------------------------------------------------------------
// App navigation controller (D-Pad focus engine)
// ---------------------------------------------------------------------------

final appNavProvider = ChangeNotifierProvider<AppNavController>((_) => AppNavController());

// ---------------------------------------------------------------------------
// SharedPreferences — injected at startup via ProviderScope.overrides
// ---------------------------------------------------------------------------

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (_) => throw UnimplementedError('inject via ProviderScope.overrides'),
);

// ---------------------------------------------------------------------------
// Server URL
// ---------------------------------------------------------------------------

final serverUrlProvider = StateNotifierProvider<ServerUrlNotifier, String>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ServerUrlNotifier(prefs);
});

class ServerUrlNotifier extends StateNotifier<String> {
  final SharedPreferences _prefs;

  ServerUrlNotifier(this._prefs) : super(_prefs.getString('server_url') ?? '');

  Future<void> setUrl(String url) async {
    final trimmed = url.trim().replaceAll(RegExp(r'/$'), '');
    await _prefs.setString('server_url', trimmed);
    state = trimmed;
  }
}

// ---------------------------------------------------------------------------
// API service — rebuilt whenever server URL changes
// ---------------------------------------------------------------------------

final apiServiceProvider = Provider<ApiService>((ref) {
  final url = ref.watch(serverUrlProvider);
  return ApiService(url);
});

// ---------------------------------------------------------------------------
// Browse — home screen content rows
// ---------------------------------------------------------------------------

class BrowseState {
  final List<SeriesResult> newAnimes;
  final List<SeriesResult> popularAnimes;
  final List<SeriesResult> newSeries;
  final List<SeriesResult> popularSeries;
  final bool loading;
  final String? error;

  const BrowseState({
    this.newAnimes = const [],
    this.popularAnimes = const [],
    this.newSeries = const [],
    this.popularSeries = const [],
    this.loading = false,
    this.error,
  });

  BrowseState copyWith({
    List<SeriesResult>? newAnimes,
    List<SeriesResult>? popularAnimes,
    List<SeriesResult>? newSeries,
    List<SeriesResult>? popularSeries,
    bool? loading,
    String? error,
  }) =>
      BrowseState(
        newAnimes: newAnimes ?? this.newAnimes,
        popularAnimes: popularAnimes ?? this.popularAnimes,
        newSeries: newSeries ?? this.newSeries,
        popularSeries: popularSeries ?? this.popularSeries,
        loading: loading ?? this.loading,
        error: error,
      );
}

final browseProvider = StateNotifierProvider<BrowseNotifier, BrowseState>((ref) {
  return BrowseNotifier(ref.watch(apiServiceProvider));
});

class BrowseNotifier extends StateNotifier<BrowseState> {
  final ApiService _api;

  BrowseNotifier(this._api) : super(const BrowseState()) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(loading: true);
    try {
      final results = await Future.wait([
        _api.getNewAnimes(),
        _api.getPopularAnimes(),
        _api.getNewSeries(),
        _api.getPopularSeries(),
      ]);
      state = BrowseState(
        newAnimes: results[0],
        popularAnimes: results[1],
        newSeries: results[2],
        popularSeries: results[3],
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }
}

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

class SearchState {
  final String query;
  final String site;
  final List<SeriesResult> results;
  final bool loading;
  final String? error;

  const SearchState({
    this.query = '',
    this.site = 'aniworld',
    this.results = const [],
    this.loading = false,
    this.error,
  });

  SearchState copyWith({
    String? query,
    String? site,
    List<SeriesResult>? results,
    bool? loading,
    String? error,
  }) =>
      SearchState(
        query: query ?? this.query,
        site: site ?? this.site,
        results: results ?? this.results,
        loading: loading ?? this.loading,
        error: error,
      );
}

final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  return SearchNotifier(ref.watch(apiServiceProvider));
});

class SearchNotifier extends StateNotifier<SearchState> {
  final ApiService _api;
  Timer? _debounce;

  SearchNotifier(this._api) : super(const SearchState());

  void setSite(String site) {
    state = state.copyWith(site: site, results: [], error: null);
    if (state.query.isNotEmpty) search(state.query);
  }

  void search(String query) {
    _debounce?.cancel();
    state = state.copyWith(query: query, error: null);
    if (query.trim().length < 2) {
      state = state.copyWith(results: [], loading: false);
      return;
    }
    state = state.copyWith(loading: true);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final results = await _api.search(query.trim(), site: state.site);
        state = state.copyWith(results: results, loading: false);
      } catch (e) {
        state = state.copyWith(loading: false, error: e.toString());
      }
    });
  }

  void clear() {
    _debounce?.cancel();
    state = const SearchState();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Queue — auto-polls every 2 s while active
// ---------------------------------------------------------------------------

class QueueState {
  final List<QueueItem> items;
  final FfmpegProgress ffmpeg;
  final bool loading;
  final String? error;

  const QueueState({
    this.items = const [],
    this.ffmpeg = FfmpegProgress.empty,
    this.loading = false,
    this.error,
  });

  QueueState copyWith({
    List<QueueItem>? items,
    FfmpegProgress? ffmpeg,
    bool? loading,
    String? error,
  }) =>
      QueueState(
        items: items ?? this.items,
        ffmpeg: ffmpeg ?? this.ffmpeg,
        loading: loading ?? this.loading,
        error: error,
      );
}

final queueProvider = StateNotifierProvider<QueueNotifier, QueueState>((ref) {
  return QueueNotifier(ref.watch(apiServiceProvider));
});

class QueueNotifier extends StateNotifier<QueueState> {
  final ApiService _api;
  Timer? _poll;

  QueueNotifier(this._api) : super(const QueueState()) {
    refresh();
    _startPolling();
  }

  void _startPolling() {
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => refresh());
  }

  Future<void> refresh() async {
    try {
      final data = await _api.getQueue();
      state = state.copyWith(items: data.items, ffmpeg: data.ffmpeg, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> cancel(int id) async {
    await _api.cancelQueueItem(id);
    await refresh();
  }

  Future<void> remove(int id) async {
    await _api.removeQueueItem(id);
    await refresh();
  }

  Future<void> clearCompleted() async {
    await _api.clearCompleted();
    await refresh();
  }

  Future<void> move(int id, String direction) async {
    await _api.moveQueueItem(id, direction);
    await refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Continue Watching
// ---------------------------------------------------------------------------

class ContinueWatchingState {
  final List<WatchProgress> items;
  final bool loading;
  const ContinueWatchingState({this.items = const [], this.loading = true});
}

final continueWatchingProvider =
    StateNotifierProvider<ContinueWatchingNotifier, ContinueWatchingState>(
        (ref) => ContinueWatchingNotifier(ref.watch(apiServiceProvider)));

class ContinueWatchingNotifier extends StateNotifier<ContinueWatchingState> {
  final ApiService _api;

  ContinueWatchingNotifier(this._api)
      : super(const ContinueWatchingState()) {
    _load();
  }

  Future<void> _load() async {
    state = const ContinueWatchingState(loading: true);
    try {
      final all = await _api.getAllProgress(continueOnly: true, limit: 50);
      final seen = <String>{};
      final grouped = <WatchProgress>[];
      for (final p in all) {
        final key = p.seriesUrl?.isNotEmpty == true
            ? p.seriesUrl!
            : (p.seriesTitle ?? p.episodeUrl);
        if (seen.add(key)) grouped.add(p);
      }
      state = ContinueWatchingState(items: grouped, loading: false);
    } catch (_) {
      state = const ContinueWatchingState(items: [], loading: false);
    }
  }

  Future<void> refresh() => _load();
}

// ---------------------------------------------------------------------------
// Library
// ---------------------------------------------------------------------------

final libraryProvider = StateNotifierProvider<LibraryNotifier, AsyncValue<List<LibraryTitle>>>((ref) {
  return LibraryNotifier(ref.watch(apiServiceProvider));
});

class LibraryNotifier extends StateNotifier<AsyncValue<List<LibraryTitle>>> {
  final ApiService _api;

  LibraryNotifier(this._api) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final titles = await _api.getLibrary();
      state = AsyncValue.data(titles);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> delete({required String folder, int? season, int? episode}) async {
    await _api.deleteFromLibrary(folder: folder, season: season, episode: episode);
    await load();
  }
}
