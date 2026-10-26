package de.redstream.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import de.redstream.app.AppState
import de.redstream.app.data.BrowseItem
import de.redstream.app.data.BrowseKind

@Composable
fun BrowseScreen(app: AppState, nav: NavHostController) {
    var kindIndex by rememberSaveable { mutableIntStateOf(0) }
    var genre by rememberSaveable { mutableStateOf<String?>(null) }
    val kind = BrowseKind.entries[kindIndex]
    Column(Modifier.fillMaxSize()) {
        TabRow(selectedTabIndex = kindIndex, containerColor = RS.bg, contentColor = RS.accent) {
            BrowseKind.entries.forEachIndexed { i, k ->
                Tab(selected = i == kindIndex, onClick = { kindIndex = i; genre = null }, text = { Text(k.label) })
            }
        }
        PagedGrid(app, nav, kind, genre) { genre = it }
    }
}

@Composable
private fun PagedGrid(app: AppState, nav: NavHostController, kind: BrowseKind, genre: String?, onGenre: (String?) -> Unit) {
    val items = remember(kind, genre) { mutableStateListOf<BrowseItem>() }
    var genres by remember(kind) { mutableStateOf<List<String>>(emptyList()) }
    var page by remember(kind, genre) { mutableIntStateOf(1) }
    var hasMore by remember(kind, genre) { mutableStateOf(true) }
    var loading by remember(kind, genre) { mutableStateOf(false) }
    var error by remember(kind, genre) { mutableStateOf<String?>(null) }
    var retry by remember(kind, genre) { mutableIntStateOf(0) }
    val grid = rememberLazyGridState()

    LaunchedEffect(kind, genre, page, retry) {
        if (!hasMore) return@LaunchedEffect
        loading = true
        try {
            val r = app.api.allByKind(kind, page, genre)
            items.addAll(r.results.filter { n -> items.none { it.url == n.url } })
            hasMore = r.has_more
            if (r.all_genres.isNotEmpty()) genres = r.all_genres
            error = null
        } catch (e: Exception) {
            error = e.message
        } finally {
            loading = false
        }
    }

    val nearEnd by remember {
        derivedStateOf {
            val last = grid.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
            last >= grid.layoutInfo.totalItemsCount - 6
        }
    }
    LaunchedEffect(nearEnd, loading) {
        if (nearEnd && !loading && hasMore && error == null && items.isNotEmpty()) page++
    }

    if (genres.isNotEmpty()) {
        LazyRow(contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            item { FilterChip(selected = genre == null, onClick = { onGenre(null) }, label = { Text("Alle") }) }
            items(genres) { g -> FilterChip(selected = genre == g, onClick = { onGenre(g) }, label = { Text(g) }) }
        }
    }
    LazyVerticalGrid(
        columns = GridCells.Adaptive(112.dp),
        state = grid,
        contentPadding = PaddingValues(12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        modifier = Modifier.fillMaxSize(),
    ) {
        items(items, key = { it.url }) { item ->
            PosterCard(item.title, app.api.absolute(item.poster_url)) { nav.openDetail(item.url, item.title) }
        }
        item(span = { GridItemSpan(maxLineSpan) }) {
            Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) {
                when {
                    error != null -> ErrorBox(error!!, onRetry = { error = null; retry++ })
                    loading -> CircularProgressIndicator()
                    items.isEmpty() -> Muted("Nichts gefunden.")
                }
            }
        }
    }
}
