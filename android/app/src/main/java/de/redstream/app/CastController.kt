package de.redstream.app

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.redstream.app.data.Api
import de.redstream.app.data.PlayItem
import de.redstream.app.data.Prefs
import de.redstream.app.data.Screen
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * "Auf TV abspielen": which TV (a browser running the web app, see
 * web/cast.py) is the playback target, and remote control for it.
 * No target selected = play on this phone.
 */
class CastController(private val api: Api, private val prefs: Prefs) {

    data class Target(val id: String, val name: String)

    var target by mutableStateOf(
        prefs.castScreenId?.let { Target(it, prefs.castScreenName ?: "Fernseher") }
    )
        private set

    /** Latest heartbeat of [target] (null while unknown / offline). */
    var targetScreen by mutableStateOf<Screen?>(null)
        private set

    var targetOffline by mutableStateOf(false)
        private set

    fun select(screen: Screen?) {
        target = screen?.let { Target(it.id, it.name) }
        targetScreen = screen
        targetOffline = false
        prefs.castScreenId = screen?.id
        prefs.castScreenName = screen?.name
    }

    suspend fun screens(): List<Screen> = api.screens()

    /** Refreshes [targetScreen]; called periodically while the app is open. */
    suspend fun refreshTarget() {
        val t = target ?: return
        val match = runCatching { api.screens() }.getOrNull()?.firstOrNull { it.id == t.id }
        targetScreen = match
        targetOffline = match == null
    }

    suspend fun play(item: PlayItem) {
        val t = target ?: error("Kein Fernseher ausgewählt")
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

    suspend fun toggle() = simple("toggle")
    suspend fun stop() = simple("stop")

    suspend fun seekBy(seconds: Int) {
        val t = target ?: return
        api.castCommand(t.id, buildJsonObject { put("type", "seek"); put("delta", seconds) })
    }

    suspend fun seekTo(seconds: Double) {
        val t = target ?: return
        api.castCommand(t.id, buildJsonObject { put("type", "seek"); put("position", seconds) })
    }

    private suspend fun simple(type: String) {
        val t = target ?: return
        api.castCommand(t.id, buildJsonObject { put("type", type) })
    }
}
