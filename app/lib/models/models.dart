// ---------------------------------------------------------------------------
// Profile
// ---------------------------------------------------------------------------

class Profile {
  final int id;
  final String name;
  final String avatarColor;
  final String createdAt;
  final String? defaultLanguage;

  const Profile({
    required this.id,
    required this.name,
    required this.avatarColor,
    this.createdAt = '',
    this.defaultLanguage,
  });

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as int? ?? 1,
        name: j['name'] as String? ?? 'Profile',
        avatarColor: j['avatar_color'] as String? ?? '#E50914',
        createdAt: j['created_at'] as String? ?? '',
        defaultLanguage: j['default_language'] as String?,
      );
}

/// Canonical set of selectable audio/subtitle language options, mirroring
/// the backend's LANG_LABELS (src/aniworld/config.py). Used for profile- and
/// series-level default pickers, which offer the full set regardless of what
/// a specific episode actually has available (the episode/download pickers
/// already restrict to `availableLanguages`).
const kAllLanguages = ['German Dub', 'German Sub', 'English Dub', 'English Sub'];

// ---------------------------------------------------------------------------
// Search / Browse
// ---------------------------------------------------------------------------

class SeriesResult {
  final String title;
  final String url;
  final String posterUrl;
  final List<String> genres;

  const SeriesResult({
    required this.title,
    required this.url,
    required this.posterUrl,
    this.genres = const [],
  });

  factory SeriesResult.fromJson(Map<String, dynamic> j) => SeriesResult(
        title: j['title'] as String? ?? '',
        url: j['url'] as String? ?? '',
        posterUrl: j['poster_url'] as String? ?? '',
        genres: (j['genres'] as List?)?.cast<String>() ?? [],
      );
}

// ---------------------------------------------------------------------------
// Watchlist (enriched)
// ---------------------------------------------------------------------------

class WatchlistEntry {
  final String title;
  final String url;
  final String posterUrl;
  final String? lastWatchedAt;
  final String? newContent; // null | "episode" | "season"

  const WatchlistEntry({
    required this.title,
    required this.url,
    required this.posterUrl,
    this.lastWatchedAt,
    this.newContent,
  });

  SeriesResult get asSeriesResult =>
      SeriesResult(title: title, url: url, posterUrl: posterUrl);

  factory WatchlistEntry.fromJson(Map<String, dynamic> j) => WatchlistEntry(
        title: j['title'] as String? ?? '',
        url: j['url'] as String? ?? '',
        posterUrl: j['poster_url'] as String? ?? '',
        lastWatchedAt: j['last_watched_at'] as String?,
        newContent: j['new_content'] as String?,
      );
}

// ---------------------------------------------------------------------------
// Series detail
// ---------------------------------------------------------------------------

class SeriesDetail {
  final String title;
  final String posterUrl;
  final String backdropUrl;
  final String description;
  final List<String> genres;
  final String releaseYear;

  const SeriesDetail({
    required this.title,
    required this.posterUrl,
    this.backdropUrl = '',
    required this.description,
    required this.genres,
    required this.releaseYear,
  });

  factory SeriesDetail.fromJson(Map<String, dynamic> j) => SeriesDetail(
        title: j['title'] as String? ?? '',
        posterUrl: j['poster_url'] as String? ?? '',
        backdropUrl: j['backdrop_url'] as String? ?? '',
        description: j['description'] as String? ?? '',
        genres: List<String>.from(j['genres'] as List? ?? []),
        releaseYear: j['release_year'] as String? ?? '',
      );
}

// ---------------------------------------------------------------------------
// Season
// ---------------------------------------------------------------------------

class Season {
  final String url;
  final int seasonNumber;
  final int episodeCount;
  final bool areMovies;

  const Season({
    required this.url,
    required this.seasonNumber,
    required this.episodeCount,
    required this.areMovies,
  });

  factory Season.fromJson(Map<String, dynamic> j) => Season(
        url: j['url'] as String? ?? '',
        seasonNumber: j['season_number'] as int? ?? 0,
        episodeCount: j['episode_count'] as int? ?? 0,
        areMovies: j['are_movies'] as bool? ?? false,
      );

  String get label => areMovies ? 'Movies' : 'Season $seasonNumber';
}

// ---------------------------------------------------------------------------
// Episode
// ---------------------------------------------------------------------------

class Episode {
  final String url;
  final int episodeNumber;
  // Running episode count across all seasons (e.g. One Piece "Episode 745"),
  // null when the backend couldn't compute it (single-season shows, or the
  // per-season episode counts failed to resolve).
  final int? absoluteEpisodeNumber;
  final String titleDe;
  final String titleEn;
  final bool downloaded;
  final List<String> availableLanguages;
  final double watchPosition;
  final double watchDuration;
  final bool isWatched;
  final String? previewUrl;

  const Episode({
    required this.url,
    required this.episodeNumber,
    this.absoluteEpisodeNumber,
    required this.titleDe,
    required this.titleEn,
    required this.downloaded,
    required this.availableLanguages,
    this.watchPosition = 0,
    this.watchDuration = 0,
    this.isWatched = false,
    this.previewUrl,
  });

  factory Episode.fromJson(Map<String, dynamic> j) => Episode(
        url: j['url'] as String? ?? '',
        episodeNumber: j['episode_number'] as int? ?? 0,
        absoluteEpisodeNumber: j['absolute_episode_number'] as int?,
        titleDe: j['title_de'] as String? ?? '',
        titleEn: j['title_en'] as String? ?? '',
        downloaded: j['downloaded'] as bool? ?? false,
        availableLanguages: List<String>.from(j['available_languages'] as List? ?? []),
        watchPosition: (j['watch_position'] as num?)?.toDouble() ?? 0,
        watchDuration: (j['watch_duration'] as num?)?.toDouble() ?? 0,
        isWatched: j['is_watched'] as bool? ?? false,
        previewUrl: j['preview_url'] as String?,
      );

  String get displayTitle => titleDe.isNotEmpty ? titleDe : (titleEn.isNotEmpty ? titleEn : 'Episode $episodeNumber');

  /// e.g. "Folge 45 · #745" when the absolute number is known and differs
  /// from the season-relative one; otherwise just "Folge 45".
  String get episodeLabel => (absoluteEpisodeNumber != null && absoluteEpisodeNumber != episodeNumber)
      ? 'Folge $episodeNumber · #$absoluteEpisodeNumber'
      : 'Folge $episodeNumber';

  Episode copyWith({double? watchPosition, double? watchDuration, bool? isWatched}) => Episode(
        url: url,
        episodeNumber: episodeNumber,
        absoluteEpisodeNumber: absoluteEpisodeNumber,
        titleDe: titleDe,
        titleEn: titleEn,
        downloaded: downloaded,
        availableLanguages: availableLanguages,
        watchPosition: watchPosition ?? this.watchPosition,
        watchDuration: watchDuration ?? this.watchDuration,
        isWatched: isWatched ?? this.isWatched,
        previewUrl: previewUrl,
      );

  double get watchProgress =>
      watchDuration > 0 ? (watchPosition / watchDuration).clamp(0.0, 1.0) : 0.0;

  bool get isPartiallyWatched => !isWatched && watchProgress > 0.03;
}

// ---------------------------------------------------------------------------
// Watch Progress
// ---------------------------------------------------------------------------

class WatchProgress {
  final String episodeUrl;
  final String? seriesTitle;
  final String? seriesUrl;
  final int season;
  final int episodeNumber;
  final String? episodeTitle;
  final double positionSeconds;
  final double durationSeconds;
  final bool completed;
  final bool started;
  final String updatedAt;
  final String posterUrl;
  final String previewUrl;

  const WatchProgress({
    required this.episodeUrl,
    this.seriesTitle,
    this.seriesUrl,
    required this.season,
    required this.episodeNumber,
    this.episodeTitle,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.completed,
    required this.started,
    required this.updatedAt,
    this.posterUrl = '',
    this.previewUrl = '',
  });

  factory WatchProgress.fromJson(Map<String, dynamic> j) => WatchProgress(
        episodeUrl: j['episode_url'] as String? ?? '',
        seriesTitle: j['series_title'] as String?,
        seriesUrl: j['series_url'] as String?,
        season: j['season'] as int? ?? 0,
        episodeNumber: j['episode_number'] as int? ?? 0,
        episodeTitle: j['episode_title'] as String?,
        positionSeconds: (j['position_seconds'] as num?)?.toDouble() ?? 0,
        durationSeconds: (j['duration_seconds'] as num?)?.toDouble() ?? 0,
        completed: (j['completed'] as int? ?? 0) == 1,
        started: (j['started'] as int? ?? 0) == 1,
        updatedAt: j['updated_at'] as String? ?? '',
        posterUrl: j['poster_url'] as String? ?? '',
        previewUrl: j['preview_url'] as String? ?? '',
      );

  double get progress =>
      durationSeconds > 0 ? (positionSeconds / durationSeconds).clamp(0.0, 1.0) : 0.0;
}

// ---------------------------------------------------------------------------
// Skip Times
// ---------------------------------------------------------------------------

class SkipInterval {
  final double start;
  final double end;
  const SkipInterval({required this.start, required this.end});

  factory SkipInterval.fromJson(Map<String, dynamic> j) => SkipInterval(
        start: (j['start'] as num).toDouble(),
        end: (j['end'] as num).toDouble(),
      );
}

class SkipTimes {
  final SkipInterval? op;
  final SkipInterval? ed;
  const SkipTimes({this.op, this.ed});

  factory SkipTimes.fromJson(Map<String, dynamic> j) => SkipTimes(
        op: j['op'] != null ? SkipInterval.fromJson(j['op'] as Map<String, dynamic>) : null,
        ed: j['ed'] != null ? SkipInterval.fromJson(j['ed'] as Map<String, dynamic>) : null,
      );

  bool get hasAny => op != null || ed != null;
}

// ---------------------------------------------------------------------------
// Thumbnail preview
// ---------------------------------------------------------------------------

class ThumbnailMeta {
  final int interval;
  final int total;
  final int cols;
  final int rows;
  final int thumbW;
  final int thumbH;
  final String spriteUrl;

  const ThumbnailMeta({
    required this.interval,
    required this.total,
    required this.cols,
    required this.rows,
    required this.thumbW,
    required this.thumbH,
    required this.spriteUrl,
  });

  factory ThumbnailMeta.fromJson(Map<String, dynamic> j, {required String spriteUrl}) =>
      ThumbnailMeta(
        interval: (j['interval'] as num?)?.toInt() ?? 10,
        total: (j['total'] as num?)?.toInt() ?? 1,
        cols: (j['cols'] as num?)?.toInt() ?? 1,
        rows: (j['rows'] as num?)?.toInt() ?? 1,
        thumbW: (j['thumb_w'] as num?)?.toInt() ?? 160,
        thumbH: (j['thumb_h'] as num?)?.toInt() ?? 90,
        spriteUrl: spriteUrl,
      );

  // Returns the zero-based frame index for a given playback position.
  int frameAt(Duration position) {
    final idx = (position.inSeconds / interval).floor();
    return idx.clamp(0, total - 1);
  }
}

// ---------------------------------------------------------------------------
// Queue
// ---------------------------------------------------------------------------

class QueueItem {
  final int id;
  final String title;
  final String status;
  final double progress;
  final String? errorMessage;

  const QueueItem({
    required this.id,
    required this.title,
    required this.status,
    required this.progress,
    this.errorMessage,
  });

  factory QueueItem.fromJson(Map<String, dynamic> j) => QueueItem(
        id: j['id'] as int? ?? 0,
        title: j['title'] as String? ?? '',
        status: j['status'] as String? ?? 'pending',
        progress: (j['progress'] as num?)?.toDouble() ?? 0.0,
        errorMessage: j['error_message'] as String?,
      );

  bool get isActive => status == 'running';
  bool get isDone => status == 'completed';
  bool get isFailed => status == 'failed';
}

class FfmpegProgress {
  final double percent;
  final String time;
  final String speed;
  final String bandwidth;
  final bool active;

  const FfmpegProgress({
    required this.percent,
    required this.time,
    required this.speed,
    required this.bandwidth,
    required this.active,
  });

  factory FfmpegProgress.fromJson(Map<String, dynamic> j) => FfmpegProgress(
        percent: (j['percent'] as num?)?.toDouble() ?? 0.0,
        time: j['time'] as String? ?? '',
        speed: j['speed'] as String? ?? '',
        bandwidth: j['bandwidth'] as String? ?? '',
        active: j['active'] as bool? ?? false,
      );

  static const empty = FfmpegProgress(percent: 0, time: '', speed: '', bandwidth: '', active: false);
}

// ---------------------------------------------------------------------------
// Library
// ---------------------------------------------------------------------------

class LibraryEpisode {
  final int episode;
  final String file;
  final int size;
  final bool isVideo;

  const LibraryEpisode({
    required this.episode,
    required this.file,
    required this.size,
    required this.isVideo,
  });

  factory LibraryEpisode.fromJson(Map<String, dynamic> j) => LibraryEpisode(
        episode: j['episode'] as int? ?? 0,
        file: j['file'] as String? ?? '',
        size: j['size'] as int? ?? 0,
        isVideo: j['is_video'] as bool? ?? false,
      );
}

class LibraryTitle {
  final String folder;
  final Map<String, List<LibraryEpisode>> seasons;
  final int totalEpisodes;
  final int totalSize;

  const LibraryTitle({
    required this.folder,
    required this.seasons,
    required this.totalEpisodes,
    required this.totalSize,
  });

  factory LibraryTitle.fromJson(Map<String, dynamic> j) {
    final rawSeasons = j['seasons'] as Map<String, dynamic>? ?? {};
    final seasons = rawSeasons.map(
      (k, v) => MapEntry(
        k,
        (v as List).map((e) => LibraryEpisode.fromJson(e as Map<String, dynamic>)).toList(),
      ),
    );
    return LibraryTitle(
      folder: j['folder'] as String? ?? '',
      seasons: seasons,
      totalEpisodes: j['total_episodes'] as int? ?? 0,
      totalSize: j['total_size'] as int? ?? 0,
    );
  }

  String get displayName {
    // Strip IMDB suffix for display: "Title (2012) [imdbid-tt123]" → "Title (2012)"
    final match = RegExp(r'^(.*?)\s*\[imdbid').firstMatch(folder);
    return match?.group(1)?.trim() ?? folder;
  }

  String get sizeFormatted {
    if (totalSize < 1024 * 1024) return '${(totalSize / 1024).toStringAsFixed(1)} KB';
    if (totalSize < 1024 * 1024 * 1024) return '${(totalSize / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(totalSize / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}
