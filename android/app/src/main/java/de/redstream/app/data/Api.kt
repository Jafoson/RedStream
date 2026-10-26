package de.redstream.app.data

import android.os.Build
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

class ApiException(val status: Int, message: String) : Exception(message)

val json = Json {
    ignoreUnknownKeys = true
    coerceInputValues = true
    explicitNulls = false
    isLenient = true
}

/**
 * Thin client for the RedStream backend's JSON API (the same endpoints the
 * TV web app uses). Auth is the bearer token from device approval; the
 * active profile travels as X-Profile-ID.
 */
class Api(private val prefs: Prefs) {

    val userAgent = "RedStream-Android/1 (Android ${Build.VERSION.RELEASE}; ${Build.MANUFACTURER} ${Build.MODEL})"

    val http: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        // /api/live/resolve can take a while (provider extraction, captcha).
        .readTimeout(120, TimeUnit.SECONDS)
        .build()

    private val jsonType = "application/json".toMediaType()

    val baseUrl: String get() = prefs.baseUrl.orEmpty().trimEnd('/')

    /** Normalizes what the user typed into the setup screen. */
    fun normalizeBaseUrl(input: String): String? {
        var s = input.trim().trimEnd('/')
        if (s.isEmpty()) return null
        if (!s.startsWith("http://") && !s.startsWith("https://")) s = "http://$s"
        return s.toHttpUrlOrNull()?.toString()?.trimEnd('/')
    }

    /** Absolute URL for a backend path (or an already absolute URL). */
    fun absolute(pathOrUrl: String?): String? {
        if (pathOrUrl.isNullOrBlank()) return null
        if (pathOrUrl.startsWith("http://") || pathOrUrl.startsWith("https://")) return pathOrUrl
        return baseUrl + (if (pathOrUrl.startsWith("/")) pathOrUrl else "/$pathOrUrl")
    }

    fun authHeaders(withProfile: Boolean = true): Map<String, String> = buildMap {
        prefs.token?.let { put("Authorization", "Bearer $it") }
        if (withProfile) prefs.profileId?.let { put("X-Profile-ID", it.toString()) }
        put("User-Agent", userAgent)
    }

    private fun url(path: String, params: Map<String, Any?> = emptyMap(), base: String = baseUrl): HttpUrl {
        val b = (base + path).toHttpUrlOrNull()?.newBuilder()
            ?: throw ApiException(0, "Ungültige Server-Adresse")
        for ((k, v) in params) if (v != null && v.toString().isNotEmpty()) b.addQueryParameter(k, v.toString())
        return b.build()
    }

    private suspend fun call(
        method: String,
        path: String,
        params: Map<String, Any?> = emptyMap(),
        body: JsonObject? = null,
        withProfile: Boolean = true,
        base: String = baseUrl,
    ): String = withContext(Dispatchers.IO) {
        val reqBody = body?.toString()?.toRequestBody(jsonType)
            ?: if (method == "POST" || method == "PUT") "".toRequestBody(jsonType) else null
        val builder = Request.Builder().url(url(path, params, base)).method(method, reqBody)
        authHeaders(withProfile).forEach { (k, v) -> builder.header(k, v) }
        http.newCall(builder.build()).execute().use { resp ->
            val text = resp.body?.string().orEmpty()
            if (!resp.isSuccessful) {
                val msg = runCatching {
                    (json.parseToJsonElement(text) as? JsonObject)?.get("error")?.let { (it as? JsonPrimitive)?.content }
                }.getOrNull() ?: "Fehler ${resp.code}"
                throw ApiException(resp.code, msg)
            }
            text
        }
    }

    private suspend inline fun <reified T> get(path: String, params: Map<String, Any?> = emptyMap(), withProfile: Boolean = true): T =
        json.decodeFromString(call("GET", path, params, withProfile = withProfile))

    private suspend inline fun <reified T> post(path: String, body: JsonObject, withProfile: Boolean = true): T =
        json.decodeFromString(call("POST", path, body = body, withProfile = withProfile))

    // ── Setup / auth ────────────────────────────────────────────────────────

    /** Checks that [base] is a RedStream server. */
    suspend fun probe(base: String) {
        call("GET", "/api/auth/check", base = base, withProfile = false)
    }

    suspend fun requestAccess(): AccessRequest = post("/api/webapp/request-access", buildJsonObject { }, withProfile = false)

    suspend fun pollAccess(deviceId: String): AccessPoll =
        get("/api/webapp/request-access/" + URLEncoder.encode(deviceId, "UTF-8"), withProfile = false)

    suspend fun me(): AuthUser = get("/api/auth/me", withProfile = false)

    suspend fun profiles(): List<Profile> = get<ProfilesResponse>("/api/profiles", withProfile = false).profiles

    // ── Browse ──────────────────────────────────────────────────────────────

    suspend fun rail(path: String): List<BrowseItem> = get<ResultsResponse>(path).results

    suspend fun allByKind(kind: BrowseKind, page: Int, genre: String?): PagedResponse =
        get(kind.endpoint, mapOf("page" to page, "per_page" to 30, "genre" to genre))

    suspend fun search(keyword: String, site: String): List<BrowseItem> =
        post<ResultsResponse>("/api/search", buildJsonObject { put("keyword", keyword); put("site", site) }, withProfile = false).results

    // ── Series ──────────────────────────────────────────────────────────────

    suspend fun series(url: String): SeriesDetail = get("/api/series", mapOf("url" to url))
    suspend fun seasons(url: String): List<Season> = get<SeasonsResponse>("/api/seasons", mapOf("url" to url)).seasons
    suspend fun episodes(seasonUrl: String): List<Episode> = get<EpisodesResponse>("/api/episodes", mapOf("url" to seasonUrl)).episodes
    suspend fun providers(episodeUrl: String): Map<String, List<String>> =
        get<ProvidersResponse>("/api/providers", mapOf("url" to episodeUrl)).providers

    suspend fun preferredLanguage(seriesUrl: String): String =
        get<LanguageResponse>("/api/preferred-language", mapOf("series_url" to seriesUrl)).language ?: "German Dub"

    suspend fun setSeriesLanguage(seriesUrl: String, language: String) {
        call("PUT", "/api/series-language", body = buildJsonObject { put("url", seriesUrl); put("language", language) })
    }

    // ── Progress / watchlist ────────────────────────────────────────────────

    suspend fun continueWatching(): List<ProgressEntry> =
        get<ProgressListResponse>("/api/progress", mapOf("continue" to 1, "limit" to 20)).progress

    suspend fun allProgress(): List<ProgressEntry> = get<ProgressListResponse>("/api/progress", mapOf("limit" to 500)).progress

    suspend fun episodeProgress(episodeUrl: String): ProgressEntry? =
        get<ProgressOneResponse>("/api/progress/" + URLEncoder.encode(episodeUrl, "UTF-8")).progress

    suspend fun saveProgress(p: PlayItem, position: Double, duration: Double, completed: Boolean) {
        call("POST", "/api/progress", body = buildJsonObject {
            put("episode_url", p.episodeUrl)
            put("series_title", p.seriesTitle)
            put("series_url", p.seriesUrl)
            put("season", p.season)
            put("episode_number", p.episodeNumber)
            p.episodeTitle?.let { put("episode_title", it) }
            put("position_seconds", position)
            put("duration_seconds", duration)
            put("completed", completed)
        })
    }

    suspend fun watchlist(): List<WatchlistItem> = get<WatchlistResponse>("/api/watchlist").items
    suspend fun inWatchlist(url: String): Boolean = get<InListResponse>("/api/watchlist/check", mapOf("url" to url)).in_list

    suspend fun addToWatchlist(url: String, title: String, poster: String?) {
        call("POST", "/api/watchlist", body = buildJsonObject {
            put("series_url", url); put("series_title", title); poster?.let { put("poster_url", it) }
        })
    }

    suspend fun removeFromWatchlist(url: String) {
        call("DELETE", "/api/watchlist", body = buildJsonObject { put("series_url", url) })
    }

    // ── Playback ────────────────────────────────────────────────────────────

    /** Path of a downloaded episode's playlist (host dropped, like the web app does). */
    suspend fun downloadedStream(folder: String, season: Int, episode: Int): String {
        val url = get<StreamResponse>("/api/stream", mapOf("folder" to folder, "season" to season, "episode" to episode)).url
        val parsed = url.toHttpUrlOrNull() ?: return url
        return parsed.encodedPath + (parsed.encodedQuery?.let { "?$it" } ?: "")
    }

    suspend fun liveStream(episodeUrl: String, language: String?, provider: String?): LiveStream =
        post("/api/live/resolve", buildJsonObject {
            put("episode_url", episodeUrl); language?.let { put("language", it) }; provider?.let { put("provider", it) }
        })

    // ── Cast ────────────────────────────────────────────────────────────────

    suspend fun screens(): List<Screen> = get<ScreensResponse>("/api/cast/screens").screens

    suspend fun castCommand(screenId: String, body: JsonObject) {
        call("POST", "/api/cast/screens/" + URLEncoder.encode(screenId, "UTF-8") + "/command", body = body)
    }
}

enum class BrowseKind(val label: String, val endpoint: String) {
    SERIES("Serien", "/api/all-series"),
    ANIME("Anime", "/api/all-animes"),
    MOVIES("Filme", "/api/all-movies"),
}

/** One episode to play — on the phone or on a TV. */
data class PlayItem(
    val episodeUrl: String,
    val seriesTitle: String,
    val seriesUrl: String,
    val season: Int,
    val episodeNumber: Int,
    val episodeTitle: String? = null,
    val absoluteEpisodeNumber: Int? = null,
    val language: String? = null,
    val provider: String? = null,
    /** Set when the episode is on the server's disk (plays from there). */
    val folder: String? = null,
)
