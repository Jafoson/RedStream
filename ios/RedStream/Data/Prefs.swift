import Foundation

/// Everything the app remembers between launches.
final class Prefs: @unchecked Sendable {
    private let d = UserDefaults.standard

    var baseUrl: String? {
        get { d.string(forKey: "base_url") }
        set { d.set(newValue, forKey: "base_url") }
    }

    var token: String? {
        get { d.string(forKey: "token") }
        set { d.set(newValue, forKey: "token") }
    }

    /// Device-approval request still waiting for the terminal.
    var pendingDeviceId: String? {
        get { d.string(forKey: "pending_device_id") }
        set { d.set(newValue, forKey: "pending_device_id") }
    }

    var pendingCode: String? {
        get { d.string(forKey: "pending_code") }
        set { d.set(newValue, forKey: "pending_code") }
    }

    var profileId: Int? {
        get { d.object(forKey: "profile_id") as? Int }
        set { d.set(newValue, forKey: "profile_id") }
    }

    var profileName: String? {
        get { d.string(forKey: "profile_name") }
        set { d.set(newValue, forKey: "profile_name") }
    }

    /// Screen (TV) chosen as playback target; nil = play on this phone.
    var castScreenId: String? {
        get { d.string(forKey: "cast_screen_id") }
        set { d.set(newValue, forKey: "cast_screen_id") }
    }

    var castScreenName: String? {
        get { d.string(forKey: "cast_screen_name") }
        set { d.set(newValue, forKey: "cast_screen_name") }
    }

    func clearSession() {
        for key in ["token", "profile_id", "profile_name", "pending_device_id", "pending_code", "cast_screen_id", "cast_screen_name"] {
            d.removeObject(forKey: key)
        }
    }
}
