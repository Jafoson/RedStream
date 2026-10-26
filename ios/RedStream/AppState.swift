import Foundation
import SwiftUI

enum Stage { case setup, profile, ready }

/// App-wide state: where we are in setup, the shared API client, the
/// playback target and what the phone player is showing.
@MainActor
final class AppState: ObservableObject {
    let prefs = Prefs()
    let api: Api
    let cast: CastController

    @Published private(set) var stage: Stage = .setup
    /// Bumped after a profile switch so screens reload their data.
    @Published private(set) var profileVersion = 0
    /// Episode open in the phone player (full-screen cover).
    @Published var playing: PlayItem?
    @Published var castSheetOpen = false
    /// Short message at the bottom ("Läuft auf …").
    @Published private(set) var toast: String?
    private var toastTask: Task<Void, Never>?

    init() {
        api = Api(prefs: prefs)
        cast = CastController(api: api, prefs: prefs)
        stage = computeStage()
    }

    private func computeStage() -> Stage {
        if (prefs.baseUrl ?? "").isEmpty || (prefs.token ?? "").isEmpty { return .setup }
        if prefs.profileId == nil { return .profile }
        return .ready
    }

    func onApproved(token: String) {
        prefs.token = token
        prefs.pendingDeviceId = nil
        prefs.pendingCode = nil
        stage = computeStage()
    }

    func selectProfile(_ p: Profile) {
        prefs.profileId = p.id
        prefs.profileName = p.name
        profileVersion += 1
        stage = computeStage()
    }

    func switchProfile() {
        prefs.profileId = nil
        stage = computeStage()
    }

    /// Forget this server entirely (token, profile, TV).
    func disconnect() {
        cast.select(nil)
        prefs.clearSession()
        prefs.baseUrl = nil
        stage = computeStage()
    }

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    /// Plays `item` on the selected TV, or opens the phone player.
    func play(_ item: PlayItem, forcePhone: Bool = false) {
        if let target = cast.target, !forcePhone {
            Task {
                do {
                    try await cast.play(item)
                    showToast("Läuft auf \(target.name): \(item.seriesTitle) \(epCode(item.season, item.episodeNumber))")
                } catch {
                    showToast("\(target.name) nicht erreichbar: \(error.localizedDescription)")
                }
            }
        } else {
            playing = item
        }
    }
}
