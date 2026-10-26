package de.redstream.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.redstream.app.AppState
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * First start: enter the server address, then the same device approval as
 * the web app — the app shows a code, the owner approves it in the server
 * terminal (`aniworld --web-requests` / `aniworld --web-approve <id>`).
 */
@Composable
fun SetupScreen(app: AppState) {
    val scope = rememberCoroutineScope()
    var address by remember { mutableStateOf(app.prefs.baseUrl ?: "") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var deviceId by remember { mutableStateOf(app.prefs.pendingDeviceId) }
    var code by remember { mutableStateOf(app.prefs.pendingCode) }
    var denied by remember { mutableStateOf(false) }

    fun connect() {
        val base = app.api.normalizeBaseUrl(address)
        if (base == null) {
            error = "Bitte eine Server-Adresse eingeben, z. B. https://serien.example.de"
            return
        }
        busy = true; error = null; denied = false
        scope.launch {
            try {
                app.api.probe(base)
                app.prefs.baseUrl = base
                val req = app.api.requestAccess()
                app.prefs.pendingDeviceId = req.device_id
                app.prefs.pendingCode = req.code
                deviceId = req.device_id
                code = req.code
            } catch (e: Exception) {
                error = "Server nicht erreichbar: ${e.message}"
            } finally {
                busy = false
            }
        }
    }

    // Poll the pending request until the terminal approves or denies it.
    LaunchedEffect(deviceId) {
        val id = deviceId ?: return@LaunchedEffect
        while (true) {
            try {
                val r = app.api.pollAccess(id)
                if (r.code != null) code = r.code
                when (r.status) {
                    "approved" -> if (r.token != null) {
                        app.onApproved(r.token); return@LaunchedEffect
                    }
                    "denied", "revoked" -> {
                        denied = true; deviceId = null
                        app.prefs.pendingDeviceId = null; app.prefs.pendingCode = null
                        return@LaunchedEffect
                    }
                }
            } catch (_: Exception) {
                // server briefly unreachable — keep polling
            }
            delay(3000)
        }
    }

    Surface(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize().systemBarsPadding().imePadding().padding(24.dp), contentAlignment = Alignment.Center) {
            Column(
                Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(40.dp).clip(RoundedCornerShape(10.dp)).background(RS.accent), contentAlignment = Alignment.Center) {
                        Icon(Icons.Filled.PlayArrow, null, tint = RS.text)
                    }
                    Spacer(Modifier.size(10.dp))
                    Text("RedStream", fontSize = 26.sp, fontWeight = FontWeight.ExtraBold)
                }
                if (deviceId == null) {
                    Text("Mit deinem RedStream-Server verbinden", fontSize = 18.sp, fontWeight = FontWeight.Bold)
                    OutlinedTextField(
                        value = address,
                        onValueChange = { address = it },
                        label = { Text("Server-Adresse") },
                        placeholder = { Text("https://serien.example.de") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Go),
                        keyboardActions = KeyboardActions(onGo = { connect() }),
                        modifier = Modifier.fillMaxWidth(),
                    )
                    if (denied) Text("Die Anfrage wurde abgelehnt.", color = RS.error)
                    error?.let { Text(it, color = RS.error, textAlign = TextAlign.Center) }
                    Button(onClick = { connect() }, enabled = !busy, modifier = Modifier.fillMaxWidth().height(50.dp)) {
                        if (busy) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) else Text("Verbinden")
                    }
                } else {
                    CircularProgressIndicator()
                    Text("Zugriff angefragt", fontSize = 20.sp, fontWeight = FontWeight.Bold)
                    Muted("Gib diese App im Server-Terminal frei. Bestätigungscode:")
                    Text(code ?: "······", fontSize = 34.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace, color = RS.gold, letterSpacing = 6.sp)
                    Surface(color = RS.panel2, shape = RoundedCornerShape(10.dp)) {
                        Text(
                            "aniworld --web-requests\naniworld --web-approve <ID>",
                            Modifier.padding(14.dp),
                            fontFamily = FontFamily.Monospace,
                            fontSize = 13.sp,
                        )
                    }
                    TextButton(onClick = {
                        deviceId = null; code = null
                        app.prefs.pendingDeviceId = null; app.prefs.pendingCode = null
                    }) { Text("Andere Server-Adresse") }
                }
            }
        }
    }
}
