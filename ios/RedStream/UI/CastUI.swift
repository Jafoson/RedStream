import SwiftUI

private func describe(_ screen: Screen) -> String {
    let st = screen.state
    var what = "…"
    if let t = nonEmpty(st?.seriesTitle) {
        if let s = st?.season, let e = st?.episodeNumber { what = "\(t) · \(epCode(s, e))" } else { what = t }
    }
    switch st?.status {
    case "playing": return "Spielt: \(what)"
    case "paused": return "Pausiert: \(what)"
    case "buffering": return "Lädt: \(what)"
    case "loading": return "Wird gestartet: \(what)"
    default: return "Bereit"
    }
}

/// Choose where playback happens: this phone or one of the online TVs.
struct CastSheet: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var cast: CastController
    @Environment(\.dismiss) private var dismiss
    @State private var screens: [Screen]?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Abspielen auf")
                    .font(.title3.weight(.heavy))
                    .foregroundColor(RS.text)
                    .padding(.bottom, 4)
                TargetRow(icon: "iphone", title: "Dieses iPhone", subtitle: "Direkt hier abspielen", selected: cast.target == nil) {
                    cast.select(nil)
                    dismiss()
                }
                if let error = error {
                    Text("Fernseher konnten nicht geladen werden: \(error)").foregroundColor(RS.error).padding(8)
                } else if let list = screens {
                    if list.isEmpty {
                        Muted("Kein Fernseher online. Öffne RedStream im Browser des Fernsehers – unter Einstellungen → Bildschirm muss „Als Bildschirm verfügbar“ an sein.")
                            .padding(8)
                    }
                    let mine = app.prefs.profileId
                    ForEach(list.sorted { ($0.profileId == mine ? 0 : 1) < ($1.profileId == mine ? 0 : 1) }) { s in
                        let sameProfile = s.profileId != nil && s.profileId == mine
                        TargetRow(
                            icon: "tv",
                            title: s.name + (sameProfile ? "  · dein Profil" : ""),
                            subtitle: (s.profileName.map { "Profil \($0) · " } ?? "") + describe(s),
                            selected: cast.target?.id == s.id
                        ) {
                            cast.select(s)
                            dismiss()
                        }
                    }
                } else {
                    ProgressView().tint(RS.accent).frame(maxWidth: .infinity).padding(16)
                }
            }
            .padding(16)
        }
        .background(RS.panel.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            while !Task.isCancelled {
                do {
                    screens = try await cast.screens()
                    error = nil
                } catch {
                    if !(error is CancellationError) { self.error = error.localizedDescription }
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }
}

private struct TargetRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(selected ? RS.accent : RS.text)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.bold()).foregroundColor(RS.text)
                    Text(subtitle).font(.footnote).foregroundColor(RS.muted).lineLimit(2)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(RS.accent)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(selected ? RS.panel3 : RS.panel2))
        }
        .buttonStyle(.plain)
    }
}

/// Remote control for the selected TV, shown above the tab bar.
struct RemoteBar: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var cast: CastController

    var body: some View {
        if let target = cast.target {
            let screen = cast.targetScreen
            let st = screen?.state
            let active = st != nil && st?.status != "idle" && st?.status != nil
            let playing = st?.status == "playing" || st?.status == "buffering"
            VStack(spacing: 0) {
                if active, let d = st?.duration, d > 0 {
                    ProgressLine(fraction: (st?.position ?? 0) / d, height: 3)
                }
                HStack(spacing: 4) {
                    Image(systemName: "tv").foregroundColor(RS.accent).padding(.horizontal, 6)
                    Button { app.castSheetOpen = true } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(target.name).font(.subheadline.bold()).foregroundColor(RS.text).lineLimit(1)
                            Text(line(screen: screen, active: active))
                                .font(.caption)
                                .foregroundColor(RS.muted)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    if active {
                        RemoteButton(icon: "gobackward.10", label: "10 Sek. zurück") { await cast.seek(by: -10) }
                        RemoteButton(icon: playing ? "pause.fill" : "play.fill", label: playing ? "Pause" : "Abspielen") { await cast.toggle() }
                        RemoteButton(icon: "goforward.10", label: "10 Sek. vor") { await cast.seek(by: 10) }
                        RemoteButton(icon: "stop.fill", label: "Stopp") { await cast.stop() }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .background(RS.panel2)
            .task(id: target.id) {
                while !Task.isCancelled {
                    await cast.refreshTarget()
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }
    }

    private func line(screen: Screen?, active: Bool) -> String {
        if cast.targetOffline { return "Offline – Browser am TV geöffnet?" }
        guard let screen = screen else { return "Verbinde…" }
        if active {
            return describe(screen) + "  " + formatTime(screen.state?.position) + " / " + formatTime(screen.state?.duration)
        }
        return "Bereit – wähle eine Folge"
    }
}

private struct RemoteButton: View {
    let icon: String
    let label: String
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(RS.text)
                .frame(width: 40, height: 40)
        }
        .accessibilityLabel(label)
    }
}
