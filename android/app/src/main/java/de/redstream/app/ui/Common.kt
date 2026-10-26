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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import de.redstream.app.data.BrowseItem

/** Result of an async load, see [rememberLoad]. */
sealed interface Load<out T> {
    data object Loading : Load<Nothing>
    data class Ok<T>(val value: T) : Load<T>
    data class Failed(val message: String) : Load<Nothing>
}

/** Loads [block] whenever [keys] change; `retry()` reloads. */
class LoadHandle<T>(val state: Load<T>, val retry: () -> Unit)

@Composable
fun <T> rememberLoad(vararg keys: Any?, block: suspend () -> T): LoadHandle<T> {
    var state by remember(*keys) { mutableStateOf<Load<T>>(Load.Loading) }
    var attempt by remember(*keys) { mutableIntStateOf(0) }
    LaunchedEffect(*keys, attempt) {
        state = Load.Loading
        state = try {
            Load.Ok(block())
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            Load.Failed(e.message ?: "Unbekannter Fehler")
        }
    }
    return LoadHandle(state) { attempt++ }
}

@Composable
fun <T> LoadBox(handle: LoadHandle<T>, modifier: Modifier = Modifier, content: @Composable (T) -> Unit) {
    when (val s = handle.state) {
        is Load.Loading -> Box(modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
            CircularProgressIndicator()
        }
        is Load.Failed -> ErrorBox(s.message, modifier, onRetry = handle.retry)
        is Load.Ok -> content(s.value)
    }
}

@Composable
fun ErrorBox(message: String, modifier: Modifier = Modifier, onRetry: (() -> Unit)? = null) {
    Column(
        modifier.fillMaxWidth().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(message, color = RS.error, textAlign = TextAlign.Center)
        if (onRetry != null) Button(onClick = onRetry) { Text("Erneut versuchen") }
    }
}

@Composable
fun SectionTitle(text: String, modifier: Modifier = Modifier) {
    Row(modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.width(4.dp).height(20.dp).clip(RoundedCornerShape(2.dp)).background(RS.accent))
        Spacer(Modifier.width(10.dp))
        Text(text, fontSize = 20.sp, fontWeight = FontWeight.ExtraBold)
    }
}

/** Poster with a gradient placeholder if there is no (loadable) image. */
@Composable
fun PosterCard(
    title: String,
    imageUrl: String?,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    progress: Float? = null,
    onClick: () -> Unit,
) {
    Column(modifier.clickable(onClick = onClick)) {
        Box(
            Modifier.fillMaxWidth().aspectRatio(206f / 300f).clip(RoundedCornerShape(12.dp))
                .background(Brush.verticalGradient(listOf(RS.panel3, RS.panel))),
        ) {
            Text(
                title.take(1).uppercase(),
                Modifier.align(Alignment.Center),
                fontSize = 34.sp,
                fontWeight = FontWeight.Black,
                color = RS.muted2,
            )
            if (imageUrl != null) {
                AsyncImage(model = imageUrl, contentDescription = title, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
            }
            if (progress != null) {
                LinearProgressIndicator(
                    progress = { progress.coerceIn(0f, 1f) },
                    modifier = Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(4.dp),
                    color = RS.accent,
                    trackColor = Color.Black.copy(alpha = 0.5f),
                )
            }
        }
        Text(title, Modifier.padding(top = 6.dp), maxLines = 2, overflow = TextOverflow.Ellipsis, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        if (subtitle != null) Text(subtitle, maxLines = 1, overflow = TextOverflow.Ellipsis, fontSize = 12.sp, color = RS.muted)
    }
}

@Composable
fun Rail(title: String, items: List<BrowseItem>, image: (String?) -> String?, onClick: (BrowseItem) -> Unit) {
    if (items.isEmpty()) return
    SectionTitle(title)
    LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        items(items, key = { it.url }) { item ->
            PosterCard(item.title, image(item.poster_url), Modifier.width(118.dp)) { onClick(item) }
        }
    }
    Spacer(Modifier.height(12.dp))
}

/** Site language keys -> what you hear/read (same wording as the web player). */
fun languageLabel(lang: String): String = when (lang) {
    "German Dub" -> "Deutsch"
    "English Dub" -> "Englisch"
    "German Sub" -> "Japanisch · deutsche Untertitel"
    "English Sub" -> "Japanisch · englische Untertitel"
    else -> lang
}

private val LANGUAGE_ORDER = listOf("German Dub", "German Sub", "English Sub", "English Dub")

fun sortLanguages(langs: Collection<String>): List<String> =
    langs.distinct().sortedWith(compareBy({ LANGUAGE_ORDER.indexOf(it).let { i -> if (i < 0) 99 else i } }, { it }))

fun epCode(season: Int, episode: Int): String = "S%02dE%02d".format(season, episode)

@Composable
fun Muted(text: String, modifier: Modifier = Modifier) {
    Text(text, modifier, color = RS.muted, style = MaterialTheme.typography.bodyMedium)
}
