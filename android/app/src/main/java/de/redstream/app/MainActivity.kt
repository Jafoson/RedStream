package de.redstream.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.remember
import de.redstream.app.ui.MainScreen
import de.redstream.app.ui.ProfileScreen
import de.redstream.app.ui.RedStreamTheme
import de.redstream.app.ui.SetupScreen

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            val app = remember { AppState(applicationContext) }
            RedStreamTheme {
                when (app.stage) {
                    Stage.SETUP -> SetupScreen(app)
                    Stage.PROFILE -> ProfileScreen(app)
                    Stage.READY -> MainScreen(app)
                }
            }
        }
    }
}
