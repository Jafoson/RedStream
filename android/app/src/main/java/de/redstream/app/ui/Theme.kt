package de.redstream.app.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// Same palette as the TV web app (webapp/src/styles/theme.css).
object RS {
    val bg = Color(0xFF17120E)
    val panel = Color(0xFF1F1813)
    val panel2 = Color(0xFF261D17)
    val panel3 = Color(0xFF31251D)
    val text = Color(0xFFF6EDE0)
    val muted = Color(0xFFB7A892)
    val muted2 = Color(0xFF7D6F5E)
    val accent = Color(0xFFD9824B)
    val gold = Color(0xFFE7B34A)
    val error = Color(0xFFFF6B6B)
}

private val scheme = darkColorScheme(
    primary = RS.accent,
    onPrimary = Color.White,
    secondary = RS.gold,
    background = RS.bg,
    onBackground = RS.text,
    surface = RS.panel,
    onSurface = RS.text,
    surfaceVariant = RS.panel2,
    onSurfaceVariant = RS.muted,
    surfaceContainer = RS.panel,
    surfaceContainerHigh = RS.panel2,
    surfaceContainerHighest = RS.panel3,
    outline = RS.muted2,
    error = RS.error,
)

@Composable
fun RedStreamTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = scheme, content = content)
}
