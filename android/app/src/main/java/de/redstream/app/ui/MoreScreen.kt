package de.redstream.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.redstream.app.AppState
import de.redstream.app.BuildConfig

@Composable
fun MoreScreen(app: AppState, onChooseTarget: () -> Unit) {
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Card("Profil") {
            Text(app.prefs.profileName ?: "—", fontSize = 18.sp, fontWeight = FontWeight.Bold)
            OutlinedButton(onClick = { app.switchProfile() }) { Text("Profil wechseln") }
        }
        Card("Abspielen auf") {
            Text(app.cast.target?.name ?: "Dieses Handy", fontSize = 18.sp, fontWeight = FontWeight.Bold)
            Muted("Wähle einen Fernseher, auf dem RedStream im Browser offen ist – dann starten Folgen dort statt auf dem Handy.")
            Button(onClick = onChooseTarget) { Text("Gerät wählen") }
        }
        Card("Server") {
            Text(app.prefs.baseUrl ?: "—", fontWeight = FontWeight.SemiBold)
            OutlinedButton(onClick = { app.disconnect() }) { Text("Verbindung trennen") }
        }
        Muted("RedStream für Android ${BuildConfig.VERSION_NAME}")
    }
}

@Composable
private fun Card(title: String, content: @Composable () -> Unit) {
    Surface(color = RS.panel, shape = RoundedCornerShape(16.dp), modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(title.uppercase(), color = RS.accent, fontSize = 12.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = 1.5.sp)
            content()
        }
    }
}
