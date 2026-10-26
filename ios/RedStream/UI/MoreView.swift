import SwiftUI

struct MoreView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var cast: CastController

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Card(title: "Profil") {
                    Text(app.prefs.profileName ?? "—").font(.title3.bold()).foregroundColor(RS.text)
                    Button("Profil wechseln") { app.switchProfile() }.buttonStyle(OutlineButtonStyle())
                }
                Card(title: "Abspielen auf") {
                    Text(cast.target?.name ?? "Dieses iPhone").font(.title3.bold()).foregroundColor(RS.text)
                    Muted("Wähle einen Fernseher, auf dem RedStream im Browser offen ist – dann starten Folgen dort statt auf dem iPhone.")
                    Button("Gerät wählen") { app.castSheetOpen = true }.buttonStyle(PrimaryButtonStyle())
                }
                Card(title: "Server") {
                    Text(app.prefs.baseUrl ?? "—").font(.body.weight(.semibold)).foregroundColor(RS.text)
                    Button("Verbindung trennen") { app.disconnect() }.buttonStyle(OutlineButtonStyle())
                }
                Muted("RedStream für iOS \(version)").frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
    }
}

private struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.heavy))
                .kerning(1.5)
                .foregroundColor(RS.accent)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(RS.panel))
    }
}
