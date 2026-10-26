package de.redstream.app.data

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull

/** Accepts true/false as well as SQLite's 0/1 (progress rows are raw DB rows). */
object FlexBoolSerializer : KSerializer<Boolean> {
    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor("FlexBool", PrimitiveKind.BOOLEAN)
    override fun serialize(encoder: Encoder, value: Boolean) = encoder.encodeBoolean(value)
    override fun deserialize(decoder: Decoder): Boolean {
        val element = (decoder as? JsonDecoder)?.decodeJsonElement() ?: return decoder.decodeBoolean()
        val p = element as? JsonPrimitive ?: return false
        return p.booleanOrNull ?: ((p.doubleOrNull ?: 0.0) != 0.0)
    }
}

// ── Device approval ─────────────────────────────────────────────────────────

@Serializable
data class AccessRequest(val device_id: String, val status: String = "pending", val code: String? = null)

@Serializable
data class AccessPoll(val status: String, val code: String? = null, val token: String? = null)

@Serializable
data class AuthUser(val id: Int, val username: String, val role: String)

@Serializable
data class Profile(
    val id: Int,
    val name: String,
    val avatar_color: String = "#E50914",
    val default_language: String? = null,
)

@Serializable
data class ProfilesResponse(val profiles: List<Profile> = emptyList())

// ── Browse / search ─────────────────────────────────────────────────────────

@Serializable
data class BrowseItem(
    val title: String = "",
    val url: String = "",
    val poster_url: String? = null,
    val genres: List<String> = emptyList(),
)

@Serializable
data class ResultsResponse(val results: List<BrowseItem> = emptyList())

@Serializable
data class PagedResponse(
    val results: List<BrowseItem> = emptyList(),
    val total: Int = 0,
    val page: Int = 1,
    val per_page: Int = 25,
    val has_more: Boolean = false,
    val all_genres: List<String> = emptyList(),
)

// ── Series detail ───────────────────────────────────────────────────────────

@Serializable
data class SeriesDetail(
    val title: String = "",
    val poster_url: String? = null,
    val backdrop_url: String? = null,
    val description: String? = null,
    val genres: List<String> = emptyList(),
    val release_year: String? = null,
)

@Serializable
data class Season(
    val url: String,
    val season_number: Int,
    val episode_count: Int = 0,
    val are_movies: Boolean = false,
)

@Serializable
data class SeasonsResponse(val seasons: List<Season> = emptyList())

@Serializable
data class Episode(
    val url: String,
    val episode_number: Int,
    val title_de: String? = null,
    val title_en: String? = null,
    @Serializable(with = FlexBoolSerializer::class) val downloaded: Boolean = false,
    val available_languages: List<String> = emptyList(),
    val folder: String? = null,
    val absolute_episode_number: Int? = null,
    val preview_url: String? = null,
) {
    val title: String get() = title_de?.takeIf { it.isNotBlank() } ?: title_en.orEmpty()
}

@Serializable
data class EpisodesResponse(val episodes: List<Episode> = emptyList())

@Serializable
data class LanguageResponse(val language: String? = null)

@Serializable
data class ProvidersResponse(val providers: Map<String, List<String>> = emptyMap())

// ── Progress / watchlist ────────────────────────────────────────────────────

@Serializable
data class ProgressEntry(
    val episode_url: String,
    val series_title: String? = null,
    val series_url: String? = null,
    val season: Int = 0,
    val episode_number: Int = 0,
    val episode_title: String? = null,
    val position_seconds: Double = 0.0,
    val duration_seconds: Double = 0.0,
    @Serializable(with = FlexBoolSerializer::class) val completed: Boolean = false,
    val poster_url: String? = null,
    val backdrop_url: String? = null,
    val preview_url: String? = null,
)

@Serializable
data class ProgressListResponse(val progress: List<ProgressEntry> = emptyList())

@Serializable
data class ProgressOneResponse(val progress: ProgressEntry? = null)

@Serializable
data class WatchlistItem(val title: String = "", val url: String = "", val poster_url: String? = null)

@Serializable
data class WatchlistResponse(val items: List<WatchlistItem> = emptyList())

@Serializable
data class InListResponse(val in_list: Boolean = false)

// ── Playback ────────────────────────────────────────────────────────────────

@Serializable
data class StreamResponse(val url: String)

@Serializable
data class LiveStream(val url: String, val kind: String = "hls", val provider: String? = null)

// ── Cast ────────────────────────────────────────────────────────────────────

@Serializable
data class ScreenState(
    val status: String = "idle",
    val episode_url: String? = null,
    val series_title: String? = null,
    val series_url: String? = null,
    val season: Int? = null,
    val episode_number: Int? = null,
    val episode_title: String? = null,
    val language: String? = null,
    val position: Double? = null,
    val duration: Double? = null,
)

@Serializable
data class Screen(
    val id: String,
    val name: String,
    val profile_id: Int? = null,
    val profile_name: String? = null,
    val online: Boolean = true,
    val state: ScreenState = ScreenState(),
)

@Serializable
data class ScreensResponse(val screens: List<Screen> = emptyList())
