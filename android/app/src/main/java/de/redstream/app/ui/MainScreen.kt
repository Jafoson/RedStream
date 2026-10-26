package de.redstream.app.ui

import android.net.Uri
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.Cast
import androidx.compose.material.icons.filled.CastConnected
import androidx.compose.material.icons.filled.Explore
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import de.redstream.app.AppState
import de.redstream.app.data.PlayItem
import kotlinx.coroutines.launch

private data class Tab(val route: String, val label: String, val icon: ImageVector)

private val TABS = listOf(
    Tab("home", "Start", Icons.Filled.Home),
    Tab("browse", "Entdecken", Icons.Filled.Explore),
    Tab("search", "Suche", Icons.Filled.Search),
    Tab("watchlist", "Meine Liste", Icons.Filled.Bookmark),
    Tab("more", "Mehr", Icons.Filled.Person),
)

/** Episode handed to the player route (navigation args would be clumsy). */
object PlayerHolder {
    var item: PlayItem? = null
}

fun NavHostController.openDetail(url: String, title: String) {
    navigate("detail?url=${Uri.encode(url)}&title=${Uri.encode(title)}")
}

/** Plays [item] on the selected TV, or opens the phone player. */
class Playback(
    private val app: AppState,
    private val nav: NavHostController,
    private val snackbar: SnackbarHostState,
    private val scope: kotlinx.coroutines.CoroutineScope,
) {
    fun play(item: PlayItem, forcePhone: Boolean = false) {
        val target = app.cast.target
        if (target != null && !forcePhone) {
            scope.launch {
                try {
                    app.cast.play(item)
                    snackbar.showSnackbar("Läuft auf ${target.name}: ${item.seriesTitle} ${epCode(item.season, item.episodeNumber)}")
                } catch (e: Exception) {
                    snackbar.showSnackbar("${target.name} nicht erreichbar: ${e.message}")
                }
            }
        } else {
            PlayerHolder.item = item
            nav.navigate("player")
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(app: AppState) {
    val nav = rememberNavController()
    val snackbar = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    val playback = remember(nav) { Playback(app, nav, snackbar, scope) }
    var castSheet by remember { mutableStateOf(false) }
    val backStack by nav.currentBackStackEntryAsState()
    val route = backStack?.destination?.route
    val inPlayer = route == "player"
    val tabRoute = TABS.firstOrNull { it.route == route }

    Scaffold(
        topBar = {
            if (!inPlayer) {
                TopAppBar(
                    title = { Text(tabRoute?.label ?: "RedStream", fontWeight = FontWeight.ExtraBold) },
                    navigationIcon = {
                        if (tabRoute == null) {
                            IconButton(onClick = { nav.popBackStack() }) {
                                Icon(Icons.AutoMirrored.Filled.ArrowBack, "Zurück")
                            }
                        }
                    },
                    actions = {
                        IconButton(onClick = { castSheet = true }) {
                            Icon(
                                if (app.cast.target != null) Icons.Filled.CastConnected else Icons.Filled.Cast,
                                "Auf TV abspielen",
                                tint = if (app.cast.target != null) RS.accent else RS.text,
                            )
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = RS.bg),
                )
            }
        },
        bottomBar = {
            if (!inPlayer) {
                Column {
                    RemoteBar(app) { castSheet = true }
                    NavigationBar(containerColor = RS.panel) {
                        TABS.forEach { tab ->
                            NavigationBarItem(
                                selected = route == tab.route,
                                onClick = {
                                    nav.navigate(tab.route) {
                                        popUpTo("home") { saveState = true }
                                        launchSingleTop = true
                                        restoreState = true
                                    }
                                },
                                icon = { Icon(tab.icon, tab.label) },
                                label = { Text(tab.label) },
                                colors = NavigationBarItemDefaults.colors(indicatorColor = RS.panel3, selectedIconColor = RS.accent),
                            )
                        }
                    }
                }
            }
        },
        snackbarHost = { SnackbarHost(snackbar) },
        containerColor = RS.bg,
    ) { padding ->
        NavHost(nav, startDestination = "home", modifier = if (inPlayer) Modifier else Modifier.padding(padding)) {
            composable("home") { HomeScreen(app, nav, playback) }
            composable("browse") { BrowseScreen(app, nav) }
            composable("search") { SearchScreen(app, nav) }
            composable("watchlist") { WatchlistScreen(app, nav) }
            composable("more") { MoreScreen(app) { castSheet = true } }
            composable(
                "detail?url={url}&title={title}",
                arguments = listOf(
                    navArgument("url") { type = NavType.StringType; defaultValue = "" },
                    navArgument("title") { type = NavType.StringType; defaultValue = "" },
                ),
            ) { entry ->
                DetailScreen(
                    app,
                    playback,
                    seriesUrl = entry.arguments?.getString("url").orEmpty(),
                    initialTitle = entry.arguments?.getString("title").orEmpty(),
                )
            }
            composable("player") {
                PlayerScreen(app, PlayerHolder.item, onClose = { nav.popBackStack() }, onCast = { castSheet = true })
            }
        }
    }

    if (castSheet) CastSheet(app) { castSheet = false }
}
