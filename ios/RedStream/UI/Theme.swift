import SwiftUI

// Same palette as the TV web app (webapp/src/styles/theme.css) and Android.
enum RS {
    static let bg = Color(hex: 0x17120E)
    static let panel = Color(hex: 0x1F1813)
    static let panel2 = Color(hex: 0x261D17)
    static let panel3 = Color(hex: 0x31251D)
    static let text = Color(hex: 0xF6EDE0)
    static let muted = Color(hex: 0xB7A892)
    static let muted2 = Color(hex: 0x7D6F5E)
    static let accent = Color(hex: 0xD9824B)
    static let gold = Color(hex: 0xE7B34A)
    static let error = Color(hex: 0xFF6B6B)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// "#RRGGBB" (profile avatar colours); falls back to the accent colour.
    init(hexString: String?) {
        let s = (hexString ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        if s.count == 6, let v = UInt32(s, radix: 16) {
            self.init(hex: v)
        } else {
            self = RS.accent
        }
    }
}

enum Theme {
    /// UIKit-side appearance (tab bar, navigation bar) to match the palette.
    static func apply() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(RS.bg)
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.foregroundColor: UIColor(RS.text)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(RS.text)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(RS.panel)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        UITabBar.appearance().unselectedItemTintColor = UIColor(RS.muted)
    }
}
