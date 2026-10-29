public enum AuthSource: String, Codable, Sendable {
    case ghCli
    case personalToken
}

public struct AppSettings: Codable, Equatable, Sendable {
    public static let defaultIgnoredBots = ["coderabbitai", "sonarqubecloud"]
    public static let refreshOptions = [1, 2, 5, 10, 15, 30]

    public var org: String
    public var authSource: AuthSource
    public var refreshMinutes: Int
    public var ignoredRepos: [String]
    public var ignoredBots: [String]
    public var notificationsEnabled: Bool
    public var launchAtLogin: Bool
    public var hasCompletedSetup: Bool
    public var popoverLayout: PopoverLayout

    public static let defaults = AppSettings(
        org: "",
        authSource: .ghCli,
        refreshMinutes: 5,
        ignoredRepos: [],
        ignoredBots: defaultIgnoredBots,
        notificationsEnabled: true,
        launchAtLogin: false,
        hasCompletedSetup: false,
        popoverLayout: .single
    )

    public init(
        org: String,
        authSource: AuthSource,
        refreshMinutes: Int,
        ignoredRepos: [String],
        ignoredBots: [String],
        notificationsEnabled: Bool,
        launchAtLogin: Bool,
        hasCompletedSetup: Bool,
        popoverLayout: PopoverLayout = .single
    ) {
        self.org = org
        self.authSource = authSource
        self.refreshMinutes = refreshMinutes
        self.ignoredRepos = ignoredRepos
        self.ignoredBots = ignoredBots
        self.notificationsEnabled = notificationsEnabled
        self.launchAtLogin = launchAtLogin
        self.hasCompletedSetup = hasCompletedSetup
        self.popoverLayout = popoverLayout
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let base = Self.defaults
        org = try values.decodeIfPresent(String.self, forKey: .org) ?? base.org
        authSource = try values.decodeIfPresent(AuthSource.self, forKey: .authSource) ?? base.authSource
        refreshMinutes = try values.decodeIfPresent(Int.self, forKey: .refreshMinutes) ?? base.refreshMinutes
        ignoredRepos = try values.decodeIfPresent([String].self, forKey: .ignoredRepos) ?? base.ignoredRepos
        ignoredBots = try values.decodeIfPresent([String].self, forKey: .ignoredBots) ?? base.ignoredBots
        notificationsEnabled = try values.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? base.notificationsEnabled
        launchAtLogin = try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? base.launchAtLogin
        hasCompletedSetup = try values.decodeIfPresent(Bool.self, forKey: .hasCompletedSetup) ?? base.hasCompletedSetup
        popoverLayout = try values.decodeIfPresent(PopoverLayout.self, forKey: .popoverLayout) ?? base.popoverLayout
    }
}
