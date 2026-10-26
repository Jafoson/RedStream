package de.redstream.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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
import androidx.navigation.NavHostController
import coil.compose.AsyncImage
import de.redstream.app.AppState
import de.redstream.app.data.PlayItem
import de.redstream.app.data.ProgressEntry

private val RAILS = listOf(
    "Neue Anime" to "/api/new-animes",
    "Beliebte Anime" to "/api/popular-animes",
    "Neue Serien" to "/api/new-series",
    "Beliebte Serien" to "/api/popular-series",
    "Beliebte Filme" to "/api/popular-movies",
)

@Composable
fun HomeScreen(app: AppState, nav: NavHostController, playback: Playback) {
    val cont = rememberLoad(app.profileVersion) { app.api.continueWatching() }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(vertical = 8.dp)) {
        item {
            val list = (cont.state as? Load.Ok)?.value.orEmpty()
            if (list.isNotEmpty()) {
                SectionTitle("Weiterschauen")
                LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(list, key = { it.episode_url }) { p ->
                        ContinueCard(app, p) {
                            playback.play(
                                PlayItem(
                                    episodeUrl = p.episode_url,
                                    seriesTitle = p.series_title.orEmpty(),
                                    seriesUrl = p.series_url.orEmpty(),
                                    season = p.season,
                                    episodeNumber = p.episode_number,
                                    episodeTitle = p.episode_title,
                                ),
                            )
                        }
                    }
                }
                Spacer(Modifier.height(12.dp))
            }
        }
        items(RAILS, key = { it.second }) { (title, path) ->
            val rail = rememberLoad(path) { app.api.rail(path) }
            when (val s = rail.state) {
                is Load.Ok -> Rail(title, s.value, app.api::absolute) { nav.openDetail(it.url, it.title) }
                is Load.Failed -> {}
                Load.Loading -> {}
            }
        }
    }
}

@Composable
private fun ContinueCard(app: AppState, p: ProgressEntry, onClick: () -> Unit) {
    val image = app.api.absolute(p.preview_url?.takeIf { it.isNotBlank() } ?: p.backdrop_url?.takeIf { it.isNotBlank() } ?: p.poster_url)
    Column(Modifier.width(230.dp).clickable(onClick = onClick)) {
        Box(
            Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(RoundedCornerShape(12.dp))
                .background(Brush.linearGradient(listOf(RS.panel3, RS.panel))),
        ) {
            if (image != null) AsyncImage(image, p.series_title, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
            val frac = if (p.completed) 1f else if (p.duration_seconds > 0) (p.position_seconds / p.duration_seconds).toFloat() else 0f
            LinearProgressIndicator(
                progress = { frac.coerceIn(0f, 1f) },
                modifier = Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(4.dp),
                color = RS.accent,
                trackColor = Color.Black.copy(alpha = 0.5f),
            )
        }
        Text(p.series_title.orEmpty(), Modifier.padding(top = 6.dp), fontWeight = FontWeight.SemiBold, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(
            epCode(p.season, p.episode_number) + (p.episode_title?.let { " · $it" } ?: ""),
            color = RS.muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
        )
    }
}
