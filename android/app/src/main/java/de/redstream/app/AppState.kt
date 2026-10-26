package de.redstream.app

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.redstream.app.data.Api
import de.redstream.app.data.Prefs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

enum class Stage { SETUP, PROFILE, READY }

/** App-wide state: where we are in setup, plus the shared API client. */
class AppState(context: Context) {
    val prefs = Prefs(context.applicationContext)
    val api = Api(prefs)
    val cast = CastController(api, prefs)

    /** Outlives single screens — e.g. the player's last progress save. */
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    var stage by mutableStateOf(computeStage())
        private set

    /** Bumped after a profile switch so screens reload their data. */
    var profileVersion by mutableStateOf(0)
        private set

    private fun computeStage(): Stage = when {
        prefs.baseUrl.isNullOrBlank() || prefs.token.isNullOrBlank() -> Stage.SETUP
        prefs.profileId == null -> Stage.PROFILE
        else -> Stage.READY
    }

    fun onApproved(token: String) {
        prefs.token = token
        prefs.pendingDeviceId = null
        prefs.pendingCode = null
        stage = computeStage()
    }

    fun selectProfile(id: Int, name: String) {
        prefs.profileId = id
        prefs.profileName = name
        profileVersion++
        stage = computeStage()
    }

    fun switchProfile() {
        prefs.profileId = null
        stage = computeStage()
    }

    /** Forget this server entirely (token, profile, TV). */
    fun disconnect() {
        cast.select(null)
        prefs.clearSession()
        prefs.baseUrl = null
        stage = computeStage()
    }
}
