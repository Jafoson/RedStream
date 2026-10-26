import AVFoundation
import SwiftUI
import UIKit

/// Lets the player switch the app to landscape (SwiftUI has no API for it).
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Portrait on iPhone outside the player; iPads rotate freely.
    static var defaultOrientations: UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait
    }

    static var orientationLock: UIInterfaceOrientationMask = defaultOrientations

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Sound even with the ring/silent switch on, like any video app.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        Theme.apply()
        return true
    }

    /// Locks the interface to `mask` and rotates there now.
    static func lock(_ mask: UIInterfaceOrientationMask) {
        orientationLock = mask
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            if #available(iOS 16.0, *) {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
            }
            scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}

@main
struct RedStreamApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(app.cast)
                .preferredColorScheme(.dark)
                .tint(RS.accent)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            RS.bg.ignoresSafeArea()
            switch app.stage {
            case .setup: SetupView()
            case .profile: ProfileView()
            case .ready: MainView()
            }
        }
    }
}
