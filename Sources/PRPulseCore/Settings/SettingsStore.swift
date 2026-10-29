import Foundation

public final class SettingsStore: @unchecked Sendable {
    public static let key = "settings"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var settings: AppSettings {
        get {
            guard let data = defaults.data(forKey: Self.key),
                  let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
            else { return .defaults }
            return decoded
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Self.key)
        }
    }
}
