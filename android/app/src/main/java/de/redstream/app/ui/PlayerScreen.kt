package de.redstream.app.ui

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.ActivityInfo
import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Translate
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView
import de.redstream.app.AppState
import de.redstream.app.data.Episode
import de.redstream.app.data.PlayItem
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private const val RESUME_MIN_SECONDS = 30.0
private const val COMPLETED_RATIO = 0.9

private data class Resolved(val url: String, val hls: Boolean, val next: PlayItem?)

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

/** Finds the episode on the server's disk and the episode after it. */
private suspend fun lookupSeason(app: AppState, item: PlayItem): Pair<Episode?, PlayItem?> {
    val season = app.api.seasons(item.seriesUrl).firstOrNull { it.season_number == item.season } ?: return null to null
    val eps = app.api.episodes(season.url)
    val idx = eps.indexOfFirst { it.url == item.episodeUrl || it.episode_number == item.episodeNumber }
    val next = eps.getOrNull(idx + 1)?.takeIf { idx >= 0 }?.let { n ->
        item.copy(
            episodeUrl = n.url,
            episodeNumber = n.episode_number,
            episodeTitle = n.title.takeIf { it.isNotBlank() },
            absoluteEpisodeNumber = n.absolute_episode_number,
            folder = if (n.downloaded) n.folder else null,
        )
    }
    return eps.getOrNull(idx) to next
}

private suspend fun resolve(app: AppState, item: PlayItem, allowDownloaded: Boolean): Resolved {
    val (ep, next) = runCatching { lookupSeason(app, item) }.getOrDefault(null to null)
    val folder = if (allowDownloaded) item.folder ?: ep?.takeIf { it.downloaded }?.folder else null
    if (folder != null) {
        runCatching { app.api.downloadedStream(folder, item.season, item.episodeNumber) }.getOrNull()?.let { path ->
            return Resolved(app.api.absolute(path)!!, hls = true, next = next)
        }
    }
    val live = app.api.liveStream(item.episodeUrl, item.language, item.provider)
    return Resolved(app.api.absolute(live.url)!!, hls = live.kind == "hls", next = next)
}

@OptIn(UnstableApi::class)
@Composable
fun PlayerScreen(app: AppState, initial: PlayItem?, onClose: () -> Unit, onCast: () -> Unit) {
    if (initial == null) {
        LaunchedEffect(Unit) { onClose() }
        return
    }
    val context = LocalContext.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    var item by remember { mutableStateOf(initial) }
    // Bumped to (re)load: next episode, language switch, retry.
    var loadKey by remember { mutableIntStateOf(0) }
    var startAt by remember { mutableStateOf<Double?>(null) }
    var allowDownloaded by remember { mutableStateOf(true) }
    var resolved by remember { mutableStateOf<Resolved?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var controlsVisible by remember { mutableStateOf(true) }
    var languages by remember { mutableStateOf<List<String>>(emptyList()) }
    var langMenu by remember { mutableStateOf(false) }

    val player = remember {
        val http = DefaultHttpDataSource.Factory()
            .setUserAgent(app.api.userAgent)
            .setAllowCrossProtocolRedirects(true)
            .setDefaultRequestProperties(app.api.authHeaders().filterKeys { it != "User-Agent" })
        ExoPlayer.Builder(context).setMediaSourceFactory(DefaultMediaSourceFactory(http)).build()
    }

    fun save(completedOverride: Boolean = false) {
        val dur = player.duration.takeIf { it > 0 }?.div(1000.0) ?: return
        val pos = player.currentPosition / 1000.0
        val done = completedOverride || pos / dur >= COMPLETED_RATIO
        val snapshot = item
        app.scope.launch { runCatching { app.api.saveProgress(snapshot, pos, dur, done) } }
    }

    // Landscape, full screen, screen stays on; restored when leaving.
    DisposableEffect(Unit) {
        val activity = context.findActivity()
        val previous = activity?.requestedOrientation
        activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        val window = activity?.window
        val insets = window?.let { WindowCompat.getInsetsController(it, view) }
        insets?.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        insets?.hide(WindowInsetsCompat.Type.systemBars())
        onDispose {
            save()
            player.release()
            insets?.show(WindowInsetsCompat.Type.systemBars())
            activity?.requestedOrientation = previous ?: ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }
    }

    // Resolve + start the current item.
    LaunchedEffect(loadKey) {
        error = null
        resolved = null
        player.stop()
        try {
            val r = resolve(app, item, allowDownloaded)
            resolved = r
            val resume = startAt ?: runCatching { app.api.episodeProgress(item.episodeUrl) }.getOrNull()?.let { p ->
                p.position_seconds.takeIf { !p.completed && it > RESUME_MIN_SECONDS && it < p.duration_seconds - 10 }
            }
            startAt = null
            val media = MediaItem.Builder().setUri(r.url).apply { if (r.hls) setMimeType(MimeTypes.APPLICATION_M3U8) }.build()
            player.setMediaItem(media, ((resume ?: 0.0) * 1000).toLong())
            player.prepare()
            player.playWhenReady = true
        } catch (e: Exception) {
            error = e.message ?: "Folge konnte nicht geladen werden"
        }
        languages = runCatching { sortLanguages(app.api.providers(item.episodeUrl).keys) }.getOrDefault(emptyList())
    }

    // Progress every 10 s while playing.
    LaunchedEffect(Unit) {
        while (true) {
            delay(10_000)
            if (player.isPlaying) save()
        }
    }

    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_ENDED) {
                    save(completedOverride = true)
                    resolved?.next?.let { next ->
                        item = next; allowDownloaded = true; loadKey++
                    }
                }
            }

            override fun onPlayerError(e: PlaybackException) {
                error = "Wiedergabe fehlgeschlagen: ${e.errorCodeName}"
            }
        }
        player.addListener(listener)
        onDispose { player.removeListener(listener) }
    }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        AndroidView(
            factory = { ctx ->
                PlayerView(ctx).apply {
                    this.player = player
                    keepScreenOn = true
                    setShowNextButton(false)
                    setShowPreviousButton(false)
                    setControllerVisibilityListener(PlayerView.ControllerVisibilityListener { v -> controlsVisible = v == android.view.View.VISIBLE })
                }
            },
            modifier = Modifier.fillMaxSize(),
        )

        if (resolved == null && error == null) {
            Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
                CircularProgressIndicator()
                Text("Stream wird vorbereitet…", Modifier.padding(top = 12.dp), color = Color.White)
            }
        }

        error?.let { msg ->
            Column(
                Modifier.align(Alignment.Center).padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(msg, color = RS.error)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { loadKey++ }) { Text("Erneut versuchen") }
                    OutlinedButton(onClick = onClose) { Text("Schließen") }
                }
            }
        }

        if (controlsVisible || resolved == null) {
            Row(
                Modifier.fillMaxWidth().background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.7f), Color.Transparent)))
                    .padding(horizontal = 8.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = onClose) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Zurück", tint = Color.White) }
                Column(Modifier.weight(1f)) {
                    Text(item.seriesTitle, color = Color.White, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(
                        epCode(item.season, item.episodeNumber) + (item.episodeTitle?.let { " · $it" } ?: ""),
                        color = Color.White.copy(alpha = 0.75f), fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    )
                }
                if (languages.isNotEmpty()) {
                    Box {
                        IconButton(onClick = { langMenu = true }) { Icon(Icons.Filled.Translate, "Sprache", tint = Color.White) }
                        DropdownMenu(expanded = langMenu, onDismissRequest = { langMenu = false }) {
                            languages.forEach { lang ->
                                DropdownMenuItem(
                                    text = { Text(languageLabel(lang)) },
                                    leadingIcon = { if (lang == item.language) Icon(Icons.Filled.CheckCircle, null, tint = RS.accent) },
                                    onClick = {
                                        langMenu = false
                                        if (lang != item.language) {
                                            save()
                                            startAt = player.currentPosition / 1000.0
                                            // A file on disk might be in the old language.
                                            allowDownloaded = false
                                            item = item.copy(language = lang, provider = null, folder = null)
                                            scope.launch { runCatching { app.api.setSeriesLanguage(item.seriesUrl, lang) } }
                                            loadKey++
                                        }
                                    },
                                )
                            }
                        }
                    }
                }
                Spacer(Modifier.width(4.dp))
                OutlinedButton(onClick = {
                    if (app.cast.target == null) {
                        onCast()
                    } else {
                        // Hand over: save the position, the TV resumes from it.
                        save()
                        player.pause()
                        val handoff = item
                        app.scope.launch {
                            delay(600) // let the progress save land first
                            runCatching { app.cast.play(handoff) }
                        }
                        onClose()
                    }
                }) {
                    Icon(Icons.Filled.Tv, null, tint = Color.White)
                    Spacer(Modifier.width(6.dp))
                    Text(app.cast.target?.let { "Auf ${it.name}" } ?: "Auf TV", color = Color.White, maxLines = 1)
                }
            }
        }
    }
}
