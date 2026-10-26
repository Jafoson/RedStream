package de.redstream.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import de.redstream.app.AppState

private val SITES = listOf("aniworld" to "Anime", "sto" to "Serien", "megakino" to "Filme")

@Composable
fun SearchScreen(app: AppState, nav: NavHostController) {
    var text by rememberSaveable { mutableStateOf("") }
    var query by rememberSaveable { mutableStateOf("") }
    var site by rememberSaveable { mutableStateOf("aniworld") }
    val focus = LocalFocusManager.current
    val results = rememberLoad(query, site) { if (query.isBlank()) emptyList() else app.api.search(query, site) }

    Column(Modifier.fillMaxSize()) {
        OutlinedTextField(
            value = text,
            onValueChange = { text = it },
            placeholder = { Text("Titel suchen…") },
            leadingIcon = { Icon(Icons.Filled.Search, null) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            keyboardActions = KeyboardActions(onSearch = { query = text.trim(); focus.clearFocus() }),
            modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
        )
        Row(Modifier.padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            SITES.forEach { (key, label) ->
                FilterChip(selected = site == key, onClick = { site = key; query = text.trim() }, label = { Text(label) })
            }
        }
        LoadBox(results) { list ->
            if (query.isNotBlank() && list.isEmpty()) {
                Muted("Keine Treffer für „$query“.", Modifier.padding(16.dp))
            }
            LazyVerticalGrid(
                columns = GridCells.Adaptive(112.dp),
                contentPadding = PaddingValues(12.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
                modifier = Modifier.fillMaxSize(),
            ) {
                items(list, key = { it.url }) { item ->
                    PosterCard(item.title, app.api.absolute(item.poster_url)) { nav.openDetail(item.url, item.title) }
                }
            }
        }
    }
}
