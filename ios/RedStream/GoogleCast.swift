import Foundation
import GoogleCast

/// Google Cast (Chromecast, Android TV / Google TV): device discovery,
/// connecting, loading an episode and remote control. The TV fetches the
/// stream itself, so URLs must be login-free (relay or /api/share) and
/// reachable from it. Google's Default Media Receiver plays our HLS.
@MainActor
final class GoogleCastManager: NSObject, ObservableObject {
    struct Device: Identifiable, Hashable {
        let id: String
        let name: String
        let model: String?
    }

    @Published private(set) var devices: [Device] = []
    /// Name of the connected device, or nil.
    @Published private(set) var connected: String?
    @Published private(set) var playerState = "idle"
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0

    private var timer: Timer?

    /// Must run before any other Cast call (AppDelegate.didFinishLaunching).
    static func configure() {
        let criteria = GCKDiscoveryCriteria(applicationID: kGCKDefaultMediaReceiverApplicationID)
        let options = GCKCastOptions(discoveryCriteria: criteria)
        options.physicalVolumeButtonsWillControlDeviceVolume = true
        GCKCastContext.setSharedInstanceWith(options)
        GCKCastContext.sharedInstance().useDefaultExpandedMediaControls = false
    }

    private var context: GCKCastContext { GCKCastContext.sharedInstance() }
    private var client: GCKRemoteMediaClient? { context.sessionManager.currentCastSession?.remoteMediaClient }

    override init() {
        super.init()
        context.discoveryManager.add(self)
        context.sessionManager.add(self)
        if let session = context.sessionManager.currentCastSession { attach(session) }
    }

    /// Discovery runs while the target sheet is open.
    func startDiscovery() {
        context.discoveryManager.startDiscovery()
        updateDevices()
    }

    func stopDiscovery() {
        context.discoveryManager.stopDiscovery()
    }

    func connect(_ device: Device) {
        let dm = context.discoveryManager
        for i in 0..<dm.deviceCount where dm.device(at: i).deviceID == device.id {
            context.sessionManager.startSession(with: dm.device(at: i))
            return
        }
    }

    func disconnect() {
        context.sessionManager.endSessionAndStopCasting(true)
    }

    func load(url: URL, title: String, subtitle: String, start: Double) {
        guard let client = client else { return }
        let info = GCKMediaInformationBuilder(contentURL: url)
        info.streamType = .buffered
        info.contentType = "application/x-mpegurl"
        // Our HLS (downloads and most hosters) is MPEG-TS.
        info.hlsSegmentFormat = .TS
        info.hlsVideoSegmentFormat = .MPEG2_TS
        let meta = GCKMediaMetadata(metadataType: .tvShow)
        meta.setString(title, forKey: kGCKMetadataKeySeriesTitle)
        meta.setString(subtitle, forKey: kGCKMetadataKeyTitle)
        info.metadata = meta
        let request = GCKMediaLoadRequestDataBuilder()
        request.mediaInformation = info.build()
        request.autoplay = true
        request.startTime = start
        client.loadMedia(with: request.build())
    }

    func toggle() {
        guard let client = client else { return }
        if client.mediaStatus?.playerState == .playing { client.pause() } else { client.play() }
    }

    func stop() {
        client?.stop()
    }

    func seek(by seconds: Int) {
        let options = GCKMediaSeekOptions()
        options.interval = TimeInterval(seconds)
        options.relative = true
        client?.seek(with: options)
    }

    // MARK: State

    private func updateDevices() {
        let dm = context.discoveryManager
        devices = (0..<dm.deviceCount).map { i in
            let d = dm.device(at: i)
            return Device(id: d.deviceID, name: d.friendlyName ?? "Chromecast", model: d.modelName)
        }
    }

    private func attach(_ session: GCKCastSession) {
        connected = session.device.friendlyName ?? "Chromecast"
        session.remoteMediaClient?.add(self)
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func detach() {
        timer?.invalidate()
        timer = nil
        connected = nil
        playerState = "idle"
        position = 0
        duration = 0
    }

    private func refresh() {
        guard let client = client else { return }
        switch client.mediaStatus?.playerState {
        case .playing: playerState = "playing"
        case .paused: playerState = "paused"
        case .buffering, .loading: playerState = "buffering"
        default: playerState = "idle"
        }
        position = client.approximateStreamPosition()
        if let d = client.mediaStatus?.mediaInformation?.streamDuration, d.isFinite, d > 0 { duration = d }
    }
}

extension GoogleCastManager: GCKDiscoveryManagerListener {
    nonisolated func didUpdateDeviceList() {
        Task { @MainActor in self.updateDevices() }
    }
}

extension GoogleCastManager: GCKSessionManagerListener {
    nonisolated func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKCastSession) {
        Task { @MainActor in self.attach(session) }
    }

    nonisolated func sessionManager(_ sessionManager: GCKSessionManager, didResumeCastSession session: GCKCastSession) {
        Task { @MainActor in self.attach(session) }
    }

    nonisolated func sessionManager(_ sessionManager: GCKSessionManager, didEnd session: GCKCastSession, withError error: Error?) {
        Task { @MainActor in self.detach() }
    }

    nonisolated func sessionManager(_ sessionManager: GCKSessionManager, didFailToStart session: GCKCastSession, withError error: Error) {
        Task { @MainActor in self.detach() }
    }
}

extension GoogleCastManager: GCKRemoteMediaClientListener {
    nonisolated func remoteMediaClient(_ client: GCKRemoteMediaClient, didUpdate mediaStatus: GCKMediaStatus?) {
        Task { @MainActor in self.refresh() }
    }
}
