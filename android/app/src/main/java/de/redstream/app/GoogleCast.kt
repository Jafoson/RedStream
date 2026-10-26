package de.redstream.app

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.mediarouter.media.MediaRouter
import com.google.android.gms.cast.HlsSegmentFormat
import com.google.android.gms.cast.HlsVideoSegmentFormat
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaLoadRequestData
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.cast.MediaQueueItem
import com.google.android.gms.cast.MediaStatus
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastOptions
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.OptionsProvider
import com.google.android.gms.cast.framework.SessionManagerListener
import com.google.android.gms.cast.framework.SessionProvider
import com.google.android.gms.cast.framework.media.RemoteMediaClient
import com.google.android.gms.cast.CastMediaControlIntent

/** Registered in the manifest; Google's Default Media Receiver plays our HLS. */
class CastOptionsProvider : OptionsProvider {
    override fun getCastOptions(context: Context): CastOptions =
        CastOptions.Builder()
            .setReceiverApplicationId(CastMediaControlIntent.DEFAULT_MEDIA_RECEIVER_APPLICATION_ID)
            .build()

    override fun getAdditionalSessionProviders(context: Context): List<SessionProvider>? = null
}

/**
 * Google Cast (Chromecast, Android TV / Google TV): discovery of devices on
 * the network, connecting, loading an episode and remote control. The TV
 * fetches the stream itself, so URLs must be login-free (relay or
 * /api/share) and reachable from it. Null-safe when Play Services are
 * missing — then simply no devices show up.
 */
class GoogleCast(context: Context) {
    data class Device(val id: String, val name: String, val description: String?)

    private val castContext: CastContext? = runCatching { CastContext.getSharedInstance(context) }.getOrNull()
    private val router: MediaRouter? = castContext?.let { MediaRouter.getInstance(context) }

    var devices by mutableStateOf<List<Device>>(emptyList())
        private set

    /** Name of the connected device, or null. */
    var connected by mutableStateOf<String?>(null)
        private set

    var playerState by mutableStateOf("idle")
        private set
    var position by mutableStateOf(0.0)
        private set
    var duration by mutableStateOf(0.0)
        private set
    /** URL of what the device plays (identifies the queue item). */
    var contentId by mutableStateOf<String?>(null)
        private set

    private val session: CastSession? get() = castContext?.sessionManager?.currentCastSession
    private val client: RemoteMediaClient? get() = session?.remoteMediaClient

    private val mediaCallback = object : RemoteMediaClient.Callback() {
        override fun onStatusUpdated() = refresh()
    }
    private val progressListener = RemoteMediaClient.ProgressListener { progressMs, durationMs ->
        position = progressMs / 1000.0
        if (durationMs > 0) duration = durationMs / 1000.0
    }

    private val sessionListener = object : SessionManagerListener<CastSession> {
        override fun onSessionStarted(s: CastSession, id: String) = attach(s)
        override fun onSessionResumed(s: CastSession, wasSuspended: Boolean) = attach(s)
        override fun onSessionEnded(s: CastSession, error: Int) = detach()
        override fun onSessionStartFailed(s: CastSession, error: Int) = detach()
        override fun onSessionStarting(s: CastSession) {}
        override fun onSessionEnding(s: CastSession) {}
        override fun onSessionResuming(s: CastSession, id: String) {}
        override fun onSessionResumeFailed(s: CastSession, error: Int) = detach()
        override fun onSessionSuspended(s: CastSession, reason: Int) {}
    }

    private val routerCallback = object : MediaRouter.Callback() {
        override fun onRouteAdded(router: MediaRouter, route: MediaRouter.RouteInfo) = updateDevices()
        override fun onRouteRemoved(router: MediaRouter, route: MediaRouter.RouteInfo) = updateDevices()
        override fun onRouteChanged(router: MediaRouter, route: MediaRouter.RouteInfo) = updateDevices()
    }

    init {
        castContext?.sessionManager?.addSessionManagerListener(sessionListener, CastSession::class.java)
        session?.let { attach(it) }
    }

    private fun attach(s: CastSession) {
        connected = s.castDevice?.friendlyName ?: "Chromecast"
        s.remoteMediaClient?.let {
            it.registerCallback(mediaCallback)
            it.addProgressListener(progressListener, 1000)
        }
        refresh()
    }

    private fun detach() {
        connected = null
        playerState = "idle"
        position = 0.0
        duration = 0.0
        contentId = null
    }

    private fun refresh() {
        val c = client ?: return
        playerState = when (c.playerState) {
            MediaStatus.PLAYER_STATE_PLAYING -> "playing"
            MediaStatus.PLAYER_STATE_PAUSED -> "paused"
            MediaStatus.PLAYER_STATE_BUFFERING, MediaStatus.PLAYER_STATE_LOADING -> "buffering"
            else -> "idle"
        }
        position = c.approximateStreamPosition / 1000.0
        if (c.streamDuration > 0) duration = c.streamDuration / 1000.0
        contentId = c.mediaInfo?.contentId
    }

    private fun updateDevices() {
        val r = router ?: return
        val selector = castContext?.mergedSelector ?: return
        devices = r.routes
            .filter { !it.isDefault && it.isEnabled && it.matchesSelector(selector) }
            .map { Device(it.id, it.name, it.description) }
    }

    /** Device discovery runs while the target sheet is open. */
    fun startDiscovery() {
        val r = router ?: return
        val selector = castContext?.mergedSelector ?: return
        r.addCallback(selector, routerCallback, MediaRouter.CALLBACK_FLAG_REQUEST_DISCOVERY)
        updateDevices()
    }

    fun stopDiscovery() {
        router?.removeCallback(routerCallback)
    }

    /** Connects; the session listener reports when it's up. */
    fun connect(device: Device) {
        val r = router ?: return
        r.routes.firstOrNull { it.id == device.id }?.let { r.selectRoute(it) }
    }

    fun disconnect() {
        castContext?.sessionManager?.endCurrentSession(true)
    }

    private fun queueItem(url: String, title: String, subtitle: String, startSeconds: Double): MediaQueueItem {
        val meta = MediaMetadata(MediaMetadata.MEDIA_TYPE_TV_SHOW).apply {
            putString(MediaMetadata.KEY_SERIES_TITLE, title)
            putString(MediaMetadata.KEY_TITLE, subtitle)
        }
        val info = MediaInfo.Builder(url)
            .setStreamType(MediaInfo.STREAM_TYPE_BUFFERED)
            .setContentType("application/x-mpegurl")
            // Our HLS (downloads and most hosters) is MPEG-TS.
            .setHlsSegmentFormat(HlsSegmentFormat.TS)
            .setHlsVideoSegmentFormat(HlsVideoSegmentFormat.MPEG2_TS)
            .setMetadata(meta)
            .build()
        return MediaQueueItem.Builder(info)
            .setAutoplay(true)
            .setPreloadTime(20.0)
            .setStartTime(startSeconds)
            .build()
    }

    /** Plays an episode as a new queue; more are added with [append]. */
    fun load(url: String, title: String, subtitle: String, startSeconds: Double) {
        val c = client ?: error("Kein Chromecast verbunden")
        c.queueLoad(arrayOf(queueItem(url, title, subtitle, startSeconds)), 0, MediaStatus.REPEAT_MODE_REPEAT_OFF, (startSeconds * 1000).toLong(), null)
    }

    /** Adds an episode at the end of the device's queue — it plays there by itself. */
    fun append(url: String, title: String, subtitle: String) {
        client?.queueAppendItem(queueItem(url, title, subtitle, 0.0), null)
    }

    fun next() {
        client?.queueNext(null)
    }

    fun toggle() {
        client?.togglePlayback()
    }

    fun stop() {
        client?.stop()
    }

    fun seekBy(seconds: Int) {
        val c = client ?: return
        val target = (c.approximateStreamPosition + seconds * 1000L).coerceAtLeast(0)
        c.seek(com.google.android.gms.cast.MediaSeekOptions.Builder().setPosition(target).build())
    }
}
