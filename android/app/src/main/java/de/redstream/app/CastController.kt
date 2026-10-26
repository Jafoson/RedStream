package de.redstream.app

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.redstream.app.data.Api
import de.redstream.app.data.PlayItem
import de.redstream.app.data.Prefs
import de.redstream.app.data.Screen
import de.redstream.app.data.ScreenState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * "Auf TV abspielen": which TV is the playback target, and remote control
 * for it. Two kinds of TV:
 * - a RedStream screen: a browser running the web app (see web/cast.py),
 *   controlled through the server; remembered across launches;
 * - a Google Cast device (Chromecast, Android TV), see [GoogleCast].
 * No target = play on this phone.
 */
// Like the TV/desktop player: jump to the next episode 30 s before the end
// (its 40 s "Nächste Folge" window minus the 10 s countdown).
private const val CAST_ADVANCE_REMAINING_S = 30.0

class CastController(context: Context, private val api: Api, private val prefs: Prefs, scope: CoroutineScope) {

    enum class Kind { SCREEN, GCAST }

    data class Target(val id: String, val name: String, val kind: Kind = Kind.SCREEN)

    val gcast = GoogleCast(context)

    private var screenTarget by mutableStateOf(
        prefs.castScreenId?.let { Target(it, prefs.castScreenName ?: "Fernseher") }
    )

    /** A connected Cast device wins over the remembered screen. */
    val target: Target?
        get() = gcast.connected?.let { Target("gcast", it, Kind.GCAST) } ?: screenTarget

    private var screenState by mutableStateOf<Screen?>(null)
    private var screenOffline by mutableStateOf(false)

    /** What the Cast device plays (it only knows a URL and a title). */
    private var gcastItem by mutableStateOf<PlayItem?>(null)

    // The device's queue by URL — the next episode is appended right away so
    // the TV moves on by itself; while the app runs it's topped up one at a time.
    private val gcastQueue = mutableMapOf<String, PlayItem>()
    private val nextQueuedFor = mutableSetOf<String>()
    private val queuedNext = mutableMapOf<String, PlayItem>()
    private val advancedFrom = mutableSetOf<String>()

    /** Latest state of [target] for the remote bar (null while unknown). */
    val targetScreen: Screen?
        get() = gcast.connected?.let { name ->
            val item = gcastItem
            Screen(
                id = "gcast",
                name = name,
                state = ScreenState(
                    status = if (item == null) "idle" else gcast.playerState,
                    series_title = item?.seriesTitle,
                    season = item?.season,
                    episode_number = item?.episodeNumber,
                    position = gcast.position,
                    duration = gcast.duration,
                ),
            )
        } ?: screenState

    val targetOffline: Boolean get() = gcast.connected == null && screenOffline

    init {
        // Follow the device through its queue: a new item playing → that's the
        // current episode (the previous one counts as watched), top the queue
        // up, and skip ahead 30 s before the end like the desktop player.
        scope.launch {
            while (true) {
                delay(1000)
                if (gcast.connected == null) continue
                val playing = gcast.contentId?.let { gcastQueue[it] }
                val cur = gcastItem
                if (playing != null && cur != null && playing.episodeUrl != cur.episodeUrl) {
                    if (gcast.duration > 0) runCatching { api.saveProgress(cur, gcast.duration, gcast.duration, true) }
                    gcastItem = playing
                }
                val now = gcastItem ?: continue
                if (gcast.playerState == "idle") continue
                if (now.episodeUrl !in nextQueuedFor) launch { queueNextAfter(now) }
                val remaining = gcast.duration - gcast.position
                if (gcast.playerState == "playing" && gcast.duration > 60 && remaining <= CAST_ADVANCE_REMAINING_S &&
                    queuedNext.containsKey(now.episodeUrl) && advancedFrom.add(now.episodeUrl)
                ) {
                    gcast.next()
                }
            }
        }
        // A Cast device doesn't report to the server — save its progress from here.
        scope.launch {
            while (true) {
                delay(10_000)
                val item = gcastItem ?: continue
                if (gcast.connected == null || gcast.playerState != "playing" || gcast.duration <= 0) continue
                runCatching {
                    api.saveProgress(item, gcast.position, gcast.duration, gcast.position / gcast.duration >= 0.9)
                }
            }
        }
    }

    fun select(screen: Screen?) {
        if (gcast.connected != null) gcast.disconnect()
        screenTarget = screen?.let { Target(it.id, it.name) }
        screenState = screen
        screenOffline = false
        prefs.castScreenId = screen?.id
        prefs.castScreenName = screen?.name
    }

    fun connectGcast(device: GoogleCast.Device) {
        screenTarget = null
        prefs.castScreenId = null
        prefs.castScreenName = null
        gcast.connect(device)
    }

    suspend fun screens(): List<Screen> = api.screens()

    /** Refreshes a RedStream screen's state; called periodically while the remote bar shows. */
    suspend fun refreshTarget() {
        val t = screenTarget ?: return
        if (gcast.connected != null) return
        val match = runCatching { api.screens() }.getOrNull()?.firstOrNull { it.id == t.id }
        screenState = match
        screenOffline = match == null
    }

    suspend fun play(item: PlayItem) {
        if (gcast.connected != null) {
            val url = loginFreeUrl(item)
            val resume = runCatching { api.episodeProgress(item.episodeUrl) }.getOrNull()?.let { p ->
                p.position_seconds.takeIf { !p.completed && it > 30 && it < p.duration_seconds - 10 }
            } ?: 0.0
            gcastQueue.clear(); gcastQueue[url] = item
            nextQueuedFor.clear(); queuedNext.clear(); advancedFrom.clear()
            gcastItem = item
            gcast.load(url, item.seriesTitle, subtitle(item), resume)
            return
        }
        val t = screenTarget ?: error("Kein Fernseher ausgewählt")
        api.castCommand(t.id, buildJsonObject {
            put("type", "play")
            put("episode_url", item.episodeUrl)
            put("series_title", item.seriesTitle)
            put("series_url", item.seriesUrl)
            put("season", item.season)
            put("episode_number", item.episodeNumber)
            item.episodeTitle?.let { put("episode_title", it) }
            item.absoluteEpisodeNumber?.let { put("absolute_episode_number", it) }
            item.language?.let { put("language", it) }
            item.provider?.let { put("provider", it) }
        })
    }

    private fun subtitle(item: PlayItem) =
        "S%02dE%02d".format(item.season, item.episodeNumber) + (item.episodeTitle?.let { " · $it" } ?: "")

    /** Puts the episode after [item] into the device's queue (once). */
    private suspend fun queueNextAfter(item: PlayItem) {
        if (!nextQueuedFor.add(item.episodeUrl)) return
        try {
            val next = nextEpisode(item) ?: return
            val url = loginFreeUrl(next)
            gcast.append(url, next.seriesTitle, subtitle(next))
            gcastQueue[url] = next
            queuedNext[item.episodeUrl] = next
        } catch (e: Exception) {
            nextQueuedFor.remove(item.episodeUrl) // try again next tick
        }
    }

    private suspend fun nextEpisode(item: PlayItem): PlayItem? {
        val season = api.seasons(item.seriesUrl).firstOrNull { it.season_number == item.season } ?: return null
        val eps = api.episodes(season.url)
        val idx = eps.indexOfFirst { it.url == item.episodeUrl || it.episode_number == item.episodeNumber }
        val n = eps.getOrNull(idx + 1)?.takeIf { idx >= 0 } ?: return null
        return item.copy(
            episodeUrl = n.url,
            episodeNumber = n.episode_number,
            episodeTitle = n.title.takeIf { it.isNotBlank() },
            absoluteEpisodeNumber = n.absolute_episode_number,
            folder = if (n.downloaded) n.folder else null,
        )
    }

    /**
     * A URL the TV can fetch without logging in: a /api/share URL for a
     * downloaded episode, else the direct-stream relay.
     */
    private suspend fun loginFreeUrl(item: PlayItem): String {
        var folder = item.folder
        if (folder == null) {
            runCatching {
                val season = api.seasons(item.seriesUrl).firstOrNull { it.season_number == item.season }
                val ep = season?.let { s -> api.episodes(s.url).firstOrNull { it.url == item.episodeUrl || it.episode_number == item.episodeNumber } }
                if (ep?.downloaded == true) folder = ep.folder
            }
        }
        folder?.let { f ->
            runCatching { api.share(api.downloadedStream(f, item.season, item.episodeNumber)) }.getOrNull()?.let { path ->
                return api.absolute(path)!!
            }
        }
        val live = api.liveStream(item.episodeUrl, item.language, item.provider)
        return api.absolute(live.url)!!
    }

    suspend fun toggle() = if (gcast.connected != null) gcast.toggle() else simple("toggle")
    suspend fun stop() = if (gcast.connected != null) gcast.stop() else simple("stop")

    suspend fun seekBy(seconds: Int) {
        if (gcast.connected != null) {
            gcast.seekBy(seconds)
            return
        }
        val t = screenTarget ?: return
        api.castCommand(t.id, buildJsonObject { put("type", "seek"); put("delta", seconds) })
    }

    private suspend fun simple(type: String) {
        val t = screenTarget ?: return
        api.castCommand(t.id, buildJsonObject { put("type", type) })
    }
}
