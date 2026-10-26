import SwiftUI

/// First start: enter the server address, then the same device approval as
/// the web app — the app shows a code, the owner approves it in the server
/// terminal (`aniworld --web-requests` / `aniworld --web-approve <id>`).
struct SetupView: View {
    @EnvironmentObject var app: AppState
    @State private var address = ""
    @State private var busy = false
    @State private var error: String?
    @State private var deviceId: String?
    @State private var code: String?
    @State private var denied = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Logo()
            if deviceId == nil {
                Text("Mit deinem RedStream-Server verbinden")
                    .font(.headline)
                    .foregroundColor(RS.text)
                    .multilineTextAlignment(.center)
                TextField("", text: $address, prompt: Text("Server-Adresse").foregroundColor(RS.muted2))
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.go)
                    .onSubmit(connect)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 10).stroke(RS.muted2))
                    .foregroundColor(RS.text)
                    .accessibilityIdentifier("serverAddress")
                if denied { Text("Die Anfrage wurde abgelehnt.").foregroundColor(RS.error) }
                if let error = error {
                    Text(error).foregroundColor(RS.error).multilineTextAlignment(.center)
                }
                Button(action: connect) {
                    Group {
                        if busy { ProgressView().tint(.white) } else { Text("Verbinden") }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy)
            } else {
                ProgressView().tint(RS.accent)
                Text("Zugriff angefragt").font(.title3.bold()).foregroundColor(RS.text)
                Muted("Gib diese App im Server-Terminal frei. Bestätigungscode:")
                    .multilineTextAlignment(.center)
                Text(code ?? "······")
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .kerning(6)
                    .foregroundColor(RS.gold)
                Text("aniworld --web-requests\naniworld --web-approve <ID>")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(RS.text)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 10).fill(RS.panel2))
                Button("Andere Server-Adresse") {
                    deviceId = nil
                    code = nil
                    app.prefs.pendingDeviceId = nil
                    app.prefs.pendingCode = nil
                }
                .foregroundColor(RS.accent)
            }
            Spacer()
            Spacer()
        }
        .padding(24)
        .onAppear {
            address = app.prefs.baseUrl ?? ""
            deviceId = app.prefs.pendingDeviceId
            code = app.prefs.pendingCode
        }
        .task(id: deviceId) { await poll() }
    }

    private func connect() {
        guard let base = app.api.normalizeBaseUrl(address) else {
            error = "Bitte eine Server-Adresse eingeben, z. B. https://serien.example.de"
            return
        }
        busy = true
        error = nil
        denied = false
        Task {
            defer { busy = false }
            do {
                try await app.api.probe(base)
                app.prefs.baseUrl = base
                let req = try await app.api.requestAccess()
                app.prefs.pendingDeviceId = req.deviceId
                app.prefs.pendingCode = req.code
                code = req.code
                deviceId = req.deviceId
            } catch {
                self.error = "Server nicht erreichbar: \(error.localizedDescription)"
            }
        }
    }

    /// Polls the pending request until the terminal approves or denies it.
    private func poll() async {
        guard let id = deviceId else { return }
        while !Task.isCancelled {
            if let r = try? await app.api.pollAccess(id) {
                if let c = r.code { code = c }
                switch r.status {
                case "approved":
                    if let token = r.token {
                        app.onApproved(token: token)
                        return
                    }
                case "denied", "revoked":
                    denied = true
                    deviceId = nil
                    app.prefs.pendingDeviceId = nil
                    app.prefs.pendingCode = nil
                    return
                default:
                    break
                }
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }
}

struct Logo: View {
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10)
                .fill(RS.accent)
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: "play.fill").foregroundColor(RS.text))
            Text("RedStream").font(.system(size: 28, weight: .heavy)).foregroundColor(RS.text)
        }
    }
}
