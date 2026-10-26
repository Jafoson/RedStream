import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var app: AppState
    @State private var profiles: Load<[Profile]> = .loading

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 16)]

    var body: some View {
        VStack {
            Text("Wer schaut?")
                .font(.system(size: 28, weight: .heavy))
                .foregroundColor(RS.text)
                .padding(.vertical, 24)
            ScrollView {
                LoadView(state: profiles, retry: { Task { await load() } }) { list in
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(list) { p in
                            Button { app.selectProfile(p) } label: {
                                VStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(hexString: p.avatarColor))
                                        .frame(width: 84, height: 84)
                                        .overlay(
                                            Text(p.name.prefix(1).uppercased())
                                                .font(.system(size: 34, weight: .black))
                                                .foregroundColor(.white)
                                        )
                                    Text(p.name).font(.body.weight(.semibold)).foregroundColor(RS.text)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
            Button("Verbindung trennen") { app.disconnect() }
                .foregroundColor(RS.accent)
                .padding(.bottom, 16)
        }
        .task { await load() }
    }

    private func load() async {
        profiles = .loading
        do {
            profiles = .ok(try await app.api.profiles())
        } catch {
            profiles = .failed(error.localizedDescription)
        }
    }
}
