package de.redstream.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.redstream.app.AppState

fun parseColor(hex: String?, fallback: Color = RS.accent): Color = try {
    Color(android.graphics.Color.parseColor(hex))
} catch (_: Exception) {
    fallback
}

@Composable
fun ProfileScreen(app: AppState) {
    val profiles = rememberLoad { app.api.profiles() }
    Surface(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().systemBarsPadding().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text("Wer schaut?", fontSize = 26.sp, fontWeight = FontWeight.ExtraBold, modifier = Modifier.padding(vertical = 24.dp))
            LoadBox(profiles, Modifier.weight(1f)) { list ->
                LazyVerticalGrid(
                    columns = GridCells.Adaptive(110.dp),
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                    verticalArrangement = Arrangement.spacedBy(20.dp),
                    modifier = Modifier.weight(1f),
                ) {
                    items(list, key = { it.id }) { p ->
                        Column(
                            Modifier.clickable { app.selectProfile(p.id, p.name) }.padding(8.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            Box(Modifier.size(84.dp).clip(CircleShape).background(parseColor(p.avatar_color)), contentAlignment = Alignment.Center) {
                                Text(p.name.take(1).uppercase(), fontSize = 34.sp, fontWeight = FontWeight.Black, color = Color.White)
                            }
                            Text(p.name, Modifier.padding(top = 8.dp), fontWeight = FontWeight.SemiBold)
                        }
                    }
                }
            }
            TextButton(onClick = { app.disconnect() }) { Text("Verbindung trennen") }
        }
    }
}
