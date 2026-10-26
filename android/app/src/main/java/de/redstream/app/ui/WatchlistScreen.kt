package de.redstream.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import de.redstream.app.AppState

@Composable
fun WatchlistScreen(app: AppState, nav: NavHostController) {
    val list = rememberLoad(app.profileVersion) { app.api.watchlist() }
    LoadBox(list) { items ->
        if (items.isEmpty()) {
            Muted("Noch nichts auf deiner Liste. Auf der Seite einer Serie kannst du sie hinzufügen.", Modifier.padding(16.dp))
        } else {
            LazyVerticalGrid(
                columns = GridCells.Adaptive(112.dp),
                contentPadding = PaddingValues(12.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
                modifier = Modifier.fillMaxSize(),
            ) {
                items(items, key = { it.url }) { item ->
                    PosterCard(item.title, app.api.absolute(item.poster_url)) { nav.openDetail(item.url, item.title) }
                }
            }
        }
    }
}
