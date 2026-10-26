package de.redstream.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.BookmarkBorder
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.DownloadDone
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Translate
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.ScrollableTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import de.redstream.app.AppState
import de.redstream.app.data.Episode
import de.redstream.app.data.PlayItem
import de.redstream.app.data.ProgressEntry
import de.redstream.app.data.Season
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Composable
fun DetailScreen(app: AppState, playback: Playback, seriesUrl: String, initialTitle: String) {
    val scope = rememberCoroutineScope()
    val detail = rememberLoad(seriesUrl) { app.api.series(seriesUrl) }
    val seasons = rememberLoad(seriesUrl) { app.api.seasons(seriesUrl) }
    var progress by remember(seriesUrl) { mutableStateOf<Map<String, ProgressEntry>>(emptyMap()) }
    var inList by remember(seriesUrl) { mutableStateOf<Boolean?>(null) }
    var language by remember(seriesUrl) { mutableStateOf<String?>(null) }
    var seasonIndex by rememberSaveable(seriesUrl) { mutableIntStateOf(-1) }

    LaunchedEffect(seriesUrl, app.profileVersion) {
        runCatching { inList = app.api.inWatchlist(seriesUrl) }
        runCatching { language = app.api.preferredLanguage(seriesUrl) }
        // Polled like the web app's detail page, so progress stays current
        // after coming back from the player or while a TV plays this series.
        while (true) {
            runCatching {
                progress = app.api.allProgress().filter { it.series_url == seriesUrl }.associateBy { it.episode_url }
            }
            delay(8000)
        }
    }

    val seasonList = (seasons.state as? Load.Ok)?.value.orEmpty()
    // Start on the season of the furthest-watched episode.
    LaunchedEffect(seasonList, progress.isNotEmpty()) {
        if (seasonIndex >= 0 || seasonList.isEmpty()) return@LaunchedEffect
        val frontier = progress.values.maxByOrNull { it.season * 10000 + it.episode_number }
        seasonIndex = seasonList.indexOfFirst { it.season_number == frontier?.season }.takeIf { it >= 0 } ?: 0
    }
    val season: Season? = seasonList.getOrNull(seasonIndex.coerceAtLeast(0))
    val episodes = rememberLoad(season?.url) { season?.let { app.api.episodes(it.url) } ?: emptyList() }
    val epList = (episodes.state as? Load.Ok)?.value.orEmpty()

    val title = (detail.state as? Load.Ok)?.value?.title?.takeIf { it.isNotBlank() } ?: initialTitle

    fun item(ep: Episode) = PlayItem(
        episodeUrl = ep.url,
        seriesTitle = title,
        seriesUrl = seriesUrl,
        season = season?.season_number ?: 1,
        episodeNumber = ep.episode_number,
        episodeTitle = ep.title.takeIf { it.isNotBlank() },
        absoluteEpisodeNumber = ep.absolute_episode_number,
        language = language,
        folder = if (ep.downloaded) ep.folder else null,
    )

    // "Weiterschauen": the furthest episode of this season that was started
    // and not finished, else the one after the furthest finished one.
    val nextUp: Episode? = run {
        if (epList.isEmpty()) return@run null
        val watched = epList.filter { progress[it.url] != null }
        val furthest = watched.maxByOrNull { it.episode_number } ?: return@run epList.first()
        if (progress[furthest.url]?.completed != true) furthest
        else epList.firstOrNull { it.episode_number > furthest.episode_number } ?: furthest
    }

    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
        item {
            val d = (detail.state as? Load.Ok)?.value
            Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f)) {
                val backdrop = app.api.absolute(d?.backdrop_url?.takeIf { it.isNotBlank() } ?: d?.poster_url)
                if (backdrop != null) AsyncImage(backdrop, title, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Transparent, RS.bg))))
                Column(Modifier.align(Alignment.BottomStart).padding(16.dp)) {
                    Text(title, fontSize = 26.sp, fontWeight = FontWeight.ExtraBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    val meta = listOfNotNull(d?.release_year?.takeIf { it.isNotBlank() }, d?.genres?.take(3)?.joinToString(" · ")?.takeIf { it.isNotBlank() })
                    if (meta.isNotEmpty()) Muted(meta.joinToString("  ·  "))
                }
            }
        }
        item {
            Row(Modifier.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { nextUp?.let { playback.play(item(it)) } }, enabled = nextUp != null, modifier = Modifier.weight(1f).height(48.dp)) {
                    Icon(if (app.cast.target != null) Icons.Filled.Tv else Icons.Filled.PlayArrow, null)
                    Spacer(Modifier.width(8.dp))
                    val started = nextUp != null && progress[nextUp.url] != null
                    Text(
                        (if (started) "Weiterschauen " else "Abspielen ") + (nextUp?.let { epCode(season?.season_number ?: 1, it.episode_number) } ?: ""),
                        maxLines = 1,
                    )
                }
                IconButton(onClick = {
                    val now = inList ?: return@IconButton
                    scope.launch {
                        runCatching {
                            if (now) app.api.removeFromWatchlist(seriesUrl)
                            else app.api.addToWatchlist(seriesUrl, title, (detail.state as? Load.Ok)?.value?.poster_url)
                            inList = !now
                        }
                    }
                }) {
                    Icon(if (inList == true) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder, "Meine Liste", tint = if (inList == true) RS.accent else RS.text)
                }
            }
            LanguagePicker(
                current = language,
                available = sortLanguages(epList.flatMap { it.available_languages }),
            ) { lang ->
                language = lang
                scope.launch { runCatching { app.api.setSeriesLanguage(seriesUrl, lang) } }
            }
            (detail.state as? Load.Ok)?.value?.description?.takeIf { it.isNotBlank() }?.let { desc ->
                var expanded by remember { mutableStateOf(false) }
                Text(
                    desc,
                    Modifier.padding(horizontal = 16.dp, vertical = 8.dp).clickable { expanded = !expanded },
                    color = RS.muted,
                    fontSize = 14.sp,
                    maxLines = if (expanded) Int.MAX_VALUE else 3,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        item {
            when (val s = seasons.state) {
                is Load.Failed -> ErrorBox(s.message, onRetry = seasons.retry)
                Load.Loading -> Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                is Load.Ok -> if (s.value.size > 1) {
                    ScrollableTabRow(selectedTabIndex = seasonIndex.coerceAtLeast(0), containerColor = RS.bg, contentColor = RS.accent, edgePadding = 12.dp) {
                        s.value.forEachIndexed { i, se ->
                            Tab(
                                selected = i == seasonIndex,
                                onClick = { seasonIndex = i },
                                text = { Text(if (se.are_movies) "Filme" else "Staffel ${se.season_number}") },
                            )
                        }
                    }
                }
            }
        }
        when (val e = episodes.state) {
            is Load.Failed -> item { ErrorBox(e.message, onRetry = episodes.retry) }
            Load.Loading -> if (season != null) item {
                Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            }
            is Load.Ok -> items(e.value, key = { it.url }) { ep ->
                EpisodeRow(
                    ep,
                    progress[ep.url],
                    tvName = app.cast.target?.name,
                    onPlay = { playback.play(item(ep)) },
                    onPlayPhone = { playback.play(item(ep), forcePhone = true) },
                )
            }
        }
    }
}

@Composable
private fun LanguagePicker(current: String?, available: List<String>, onPick: (String) -> Unit) {
    if (available.isEmpty() && current == null) return
    var open by remember { mutableStateOf(false) }
    Box(Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) {
        OutlinedButton(onClick = { open = true }) {
            Icon(Icons.Filled.Translate, null, Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text(current?.let { languageLabel(it) } ?: "Sprache")
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            (if (current != null && current !in available) available + current else available).forEach { lang ->
                DropdownMenuItem(
                    text = { Text(languageLabel(lang)) },
                    leadingIcon = { if (lang == current) Icon(Icons.Filled.CheckCircle, null, tint = RS.accent) },
                    onClick = { open = false; onPick(lang) },
                )
            }
        }
    }
}

@Composable
private fun EpisodeRow(ep: Episode, progress: ProgressEntry?, tvName: String?, onPlay: () -> Unit, onPlayPhone: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onPlay).padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier.size(44.dp).clip(RoundedCornerShape(10.dp)).background(RS.panel2),
            contentAlignment = Alignment.Center,
        ) { Text(ep.episode_number.toString(), fontWeight = FontWeight.ExtraBold) }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(ep.title.ifBlank { "Folge ${ep.episode_number}" }, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (ep.downloaded) {
                    Icon(Icons.Filled.DownloadDone, "Heruntergeladen", Modifier.size(14.dp), tint = RS.muted)
                    Spacer(Modifier.width(4.dp))
                }
                when {
                    progress?.completed == true -> Text("Gesehen", color = RS.accent, fontSize = 12.sp)
                    progress != null && progress.duration_seconds > 0 ->
                        Text("${(progress.position_seconds / progress.duration_seconds * 100).toInt()} % gesehen", color = RS.muted, fontSize = 12.sp)
                    else -> Text(sortLanguages(ep.available_languages).joinToString(" · ") { shortLanguageLabel(it) }, color = RS.muted2, fontSize = 12.sp, maxLines = 1)
                }
            }
            if (progress != null && !progress.completed && progress.duration_seconds > 0) {
                LinearProgressIndicator(
                    progress = { (progress.position_seconds / progress.duration_seconds).toFloat().coerceIn(0f, 1f) },
                    modifier = Modifier.padding(top = 4.dp).fillMaxWidth(0.6f).height(3.dp),
                    color = RS.accent,
                    trackColor = RS.panel3,
                )
            }
        }
        if (tvName != null) {
            Box {
                IconButton(onClick = { menu = true }) { Icon(Icons.Filled.MoreVert, "Optionen") }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    DropdownMenuItem(text = { Text("Auf $tvName abspielen") }, leadingIcon = { Icon(Icons.Filled.Tv, null) }, onClick = { menu = false; onPlay() })
                    DropdownMenuItem(text = { Text("Auf diesem Handy abspielen") }, leadingIcon = { Icon(Icons.Filled.PhoneAndroid, null) }, onClick = { menu = false; onPlayPhone() })
                }
            }
        } else {
            Icon(Icons.Filled.PlayArrow, "Abspielen", tint = RS.accent)
        }
    }
}
