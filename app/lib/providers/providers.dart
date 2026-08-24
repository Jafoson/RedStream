import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_service.dart';
import '../models/models.dart';
import '../navigation/app_nav.dart';
import '../services/update_service.dart';

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
// Auth token
// ---------------------------------------------------------------------------

final authTokenProvider = StateNotifierProvider<AuthTokenNotifier, String?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return AuthTokenNotifier(prefs);
});

class AuthTokenNotifier extends StateNotifier<String?> {
  final SharedPreferences _prefs;

  AuthTokenNotifier(this._prefs) : super(_prefs.getString('auth_token'));

  Future<void> setToken(String token) async {
    await _prefs.setString('auth_token', token);
    state = token;
  }

  Future<void> clearToken() async {
    await _prefs.remove('auth_token');
    state = null;
  }
}

// ---------------------------------------------------------------------------
// Active Profile
// ---------------------------------------------------------------------------

final activeProfileIdProvider =
    StateNotifierProvider<ActiveProfileIdNotifier, int?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ActiveProfileIdNotifier(prefs);
});

class ActiveProfileIdNotifier extends StateNotifier<int?> {
  final SharedPreferences _prefs;

  ActiveProfileIdNotifier(this._prefs)
      : super(_prefs.getInt('active_profile_id'));

  Future<void> setProfile(int id) async {
    await _prefs.setInt('active_profile_id', id);
    state = id;
  }

  Future<void> clearProfile() async {
    await _prefs.remove('active_profile_id');
    state = null;
  }
}

/// Resolves to the display name of the currently active profile.
final activeProfileNameProvider = FutureProvider<String?>((ref) async {
  final id = ref.watch(activeProfileIdProvider);
  if (id == null) return null;
  final api = ref.watch(apiServiceProvider);
  final profiles = await api.getProfiles();
  try {
    return profiles.firstWhere((p) => p.id == id).name;
  } catch (_) {
    return null;
  }
});

// ---------------------------------------------------------------------------
// API service — rebuilt whenever server URL or active profile changes
// ---------------------------------------------------------------------------

final apiServiceProvider = Provider<ApiService>((ref) {
  final url = ref.watch(serverUrlProvider);
  final profileId = ref.watch(activeProfileIdProvider);
  final authToken = ref.watch(authTokenProvider);
  return ApiService(url, profileId: profileId, authToken: authToken);
});

// ---------------------------------------------------------------------------
// Browse — home screen content rows
// ---------------------------------------------------------------------------

class BrowseState {
  final List<SeriesResult> newAnimes;
  final List<SeriesResult> popularAnimes;
  final List<SeriesResult> newSeries;
  final List<SeriesResult> popularSeries;
  final List<SeriesResult> popularMovies;
  final bool loading;
  final String? error;

  const BrowseState({
    this.newAnimes = const [],
    this.popularAnimes = const [],
    this.newSeries = const [],
    this.popularSeries = const [],
    this.popularMovies = const [],
    this.loading = false,
    this.error,
  });

  BrowseState copyWith({
    List<SeriesResult>? newAnimes,
    List<SeriesResult>? popularAnimes,
    List<SeriesResult>? newSeries,
    List<SeriesResult>? popularSeries,
    List<SeriesResult>? popularMovies,
    bool? loading,
    String? error,
  }) =>
      BrowseState(
        newAnimes: newAnimes ?? this.newAnimes,
        popularAnimes: popularAnimes ?? this.popularAnimes,
        newSeries: newSeries ?? this.newSeries,
        popularSeries: popularSeries ?? this.popularSeries,
        popularMovies: popularMovies ?? this.popularMovies,
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
        _api.getPopularMovies(),
      ]);
      state = BrowseState(
        newAnimes: results[0],
        popularAnimes: results[1],
        newSeries: results[2],
        popularSeries: results[3],
        popularMovies: results[4],
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
    this.site = 'both',
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
        final List<SeriesResult> results;
        if (state.site == 'both') {
          // Search aniworld + sto + megakino in parallel; aniworld takes
          // priority on duplicates, then sto, then megakino.
          final trio = await Future.wait([
            _api.search(query.trim(), site: 'aniworld'),
            _api.search(query.trim(), site: 'sto'),
            _api.search(query.trim(), site: 'megakino'),
          ]);
          final seen = <String>{};
          final merged = <SeriesResult>[];
          for (final r in [...trio[0], ...trio[1], ...trio[2]]) {
            final key = r.title.trim().toLowerCase();
            if (seen.add(key)) merged.add(r);
          }
          results = merged;
        } else {
          results = await _api.search(query.trim(), site: state.site);
        }
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
// Watchlist
// ---------------------------------------------------------------------------

final watchlistProvider =
    StateNotifierProvider<WatchlistNotifier, AsyncValue<List<SeriesResult>>>(
        (ref) => WatchlistNotifier(ref.watch(apiServiceProvider)));

class WatchlistNotifier extends StateNotifier<AsyncValue<List<SeriesResult>>> {
  final ApiService _api;

  WatchlistNotifier(this._api) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final items = await _api.getWatchlist();
      state = AsyncValue.data(items);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() => load();
}

final watchlistEnrichedProvider =
    StateNotifierProvider<WatchlistEnrichedNotifier, AsyncValue<List<WatchlistEntry>>>(
        (ref) => WatchlistEnrichedNotifier(ref.watch(apiServiceProvider)));

class WatchlistEnrichedNotifier
    extends StateNotifier<AsyncValue<List<WatchlistEntry>>> {
  final ApiService _api;

  WatchlistEnrichedNotifier(this._api) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final items = await _api.getWatchlistEnriched();
      state = AsyncValue.data(items);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() => load();
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

// ---------------------------------------------------------------------------
// Auto-update
// ---------------------------------------------------------------------------

sealed class UpdateState {
  const UpdateState();
}

class UpdateIdle extends UpdateState {
  const UpdateIdle();
}

class UpdateChecking extends UpdateState {
  const UpdateChecking();
}

class UpdateUpToDate extends UpdateState {
  final String version;
  const UpdateUpToDate(this.version);
}

class UpdateAvailable extends UpdateState {
  final ReleaseInfo release;
  final String currentVersion;
  const UpdateAvailable({required this.release, required this.currentVersion});
}

class UpdateDownloading extends UpdateState {
  final ReleaseInfo release;
  final double progress;
  const UpdateDownloading({required this.release, required this.progress});
}

class UpdateError extends UpdateState {
  final String message;
  const UpdateError(this.message);
}

final updateProvider =
    StateNotifierProvider<UpdateNotifier, UpdateState>((_) => UpdateNotifier());

class UpdateNotifier extends StateNotifier<UpdateState> {
  UpdateNotifier() : super(const UpdateIdle());

  final _svc = UpdateService();

  Future<void> check() async {
    state = const UpdateChecking();
    try {
      final current = await _svc.currentVersion();
      final release = await _svc.fetchLatestRelease();
      if (release == null || release.version.isEmpty) {
        state = UpdateUpToDate(current);
        return;
      }
      if (UpdateService.isNewer(current, release.version)) {
        state = UpdateAvailable(release: release, currentVersion: current);
      } else {
        state = UpdateUpToDate(current);
      }
    } catch (e) {
      state = UpdateError(e.toString());
    }
  }

  Future<void> install(ReleaseInfo release) async {
    state = UpdateDownloading(release: release, progress: 0);
    try {
      await _svc.downloadAndInstall(
        release,
        onProgress: (p) =>
            state = UpdateDownloading(release: release, progress: p),
      );
    } catch (e) {
      state = UpdateError(e.toString());
    }
  }

  void reset() => state = const UpdateIdle();
}
