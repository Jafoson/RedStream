package de.redstream.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Forward10
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay10
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.redstream.app.AppState
import de.redstream.app.data.Screen
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private fun formatTime(seconds: Double?): String {
    val s = (seconds ?: 0.0).toInt().coerceAtLeast(0)
    return if (s >= 3600) "%d:%02d:%02d".format(s / 3600, s / 60 % 60, s % 60) else "%d:%02d".format(s / 60, s % 60)
}

private fun describe(screen: Screen): String {
    val st = screen.state
    val what = st.series_title?.takeIf { it.isNotBlank() }?.let { t ->
        if (st.season != null && st.episode_number != null) "$t · ${epCode(st.season, st.episode_number)}" else t
    }
    return when (st.status) {
        "playing" -> "Spielt: ${what ?: "…"}"
        "paused" -> "Pausiert: ${what ?: "…"}"
        "buffering" -> "Lädt: ${what ?: "…"}"
        "loading" -> "Wird gestartet: ${what ?: "…"}"
        else -> "Bereit"
    }
}

/** Choose where playback happens: this phone or one of the online TVs. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CastSheet(app: AppState, onDismiss: () -> Unit) {
    var screens by remember { mutableStateOf<List<Screen>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) {
        while (true) {
            try {
                screens = app.cast.screens(); error = null
            } catch (e: Exception) {
                error = e.message
            }
            delay(3000)
        }
    }
    val myProfile = app.prefs.profileId
    val current = app.cast.target?.id
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = RS.panel) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 24.dp).navigationBarsPadding()) {
            Text("Abspielen auf", fontSize = 20.sp, fontWeight = FontWeight.ExtraBold, modifier = Modifier.padding(bottom = 12.dp))
            TargetRow(Icons.Filled.PhoneAndroid, "Dieses Handy", "Direkt hier abspielen", selected = current == null) {
                app.cast.select(null); onDismiss()
            }
            val list = screens
            when {
                list == null && error == null -> Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(Modifier.size(24.dp))
                }
                error != null -> Text("Fernseher konnten nicht geladen werden: $error", color = RS.error, modifier = Modifier.padding(8.dp))
                list.isNullOrEmpty() -> Muted(
                    "Kein Fernseher online. Öffne RedStream im Browser des Fernsehers – unter Einstellungen → Bildschirm muss „Als Bildschirm verfügbar“ an sein.",
                    Modifier.padding(8.dp),
                )
                else -> list.sortedByDescending { it.profile_id == myProfile }.forEach { s ->
                    val sameProfile = s.profile_id != null && s.profile_id == myProfile
                    TargetRow(
                        Icons.Filled.Tv,
                        s.name + if (sameProfile) "  · dein Profil" else "",
                        (s.profile_name?.let { "Profil $it · " } ?: "") + describe(s),
                        selected = current == s.id,
                    ) { app.cast.select(s); onDismiss() }
                }
            }
        }
    }
}

@Composable
private fun TargetRow(icon: ImageVector, title: String, subtitle: String, selected: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp))
            .background(if (selected) RS.panel3 else RS.panel)
            .clickable(onClick = onClick).padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = if (selected) RS.accent else RS.text)
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(title, fontWeight = FontWeight.Bold)
            Text(subtitle, color = RS.muted, fontSize = 13.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
        if (selected) Icon(Icons.Filled.CheckCircle, null, tint = RS.accent)
    }
    Spacer(Modifier.height(8.dp))
}

/** Remote control for the selected TV, shown above the bottom navigation. */
@Composable
fun RemoteBar(app: AppState, onOpenSheet: () -> Unit) {
    val target = app.cast.target ?: return
    val scope = rememberCoroutineScope()
    LaunchedEffect(target.id) {
        while (true) {
            app.cast.refreshTarget()
            delay(2000)
        }
    }
    val screen = app.cast.targetScreen
    val st = screen?.state
    val playing = st?.status == "playing" || st?.status == "buffering"
    val active = st != null && st.status != "idle"
    Surface(color = RS.panel2) {
        Column(Modifier.fillMaxWidth()) {
            if (active && (st?.duration ?: 0.0) > 0) {
                LinearProgressIndicator(
                    progress = { ((st?.position ?: 0.0) / (st?.duration ?: 1.0)).toFloat().coerceIn(0f, 1f) },
                    modifier = Modifier.fillMaxWidth().height(3.dp),
                    color = RS.accent,
                    trackColor = RS.panel3,
                )
            }
            Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Tv, null, tint = RS.accent, modifier = Modifier.padding(horizontal = 6.dp))
                Column(Modifier.weight(1f).clickable(onClick = onOpenSheet)) {
                    Text(target.name, fontWeight = FontWeight.Bold, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    val line = when {
                        app.cast.targetOffline -> "Offline – Browser am TV geöffnet?"
                        screen == null -> "Verbinde…"
                        active -> describe(screen) + "  " + formatTime(st?.position) + " / " + formatTime(st?.duration)
                        else -> "Bereit – wähle eine Folge"
                    }
                    Text(line, color = RS.muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                if (active) {
                    IconButton(onClick = { scope.launch { runCatching { app.cast.seekBy(-10) } } }) { Icon(Icons.Filled.Replay10, "10 Sek. zurück") }
                    IconButton(onClick = { scope.launch { runCatching { app.cast.toggle() } } }) {
                        Icon(if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow, if (playing) "Pause" else "Abspielen")
                    }
                    IconButton(onClick = { scope.launch { runCatching { app.cast.seekBy(10) } } }) { Icon(Icons.Filled.Forward10, "10 Sek. vor") }
                    IconButton(onClick = { scope.launch { runCatching { app.cast.stop() } } }) { Icon(Icons.Filled.Stop, "Stopp") }
                }
            }
        }
    }
}
