public enum AuthSource: String, Codable, Sendable {
    case ghCli
    case personalToken
}

public struct AppSettings: Codable, Equatable, Sendable {
    public static let defaultIgnoredBots = ["coderabbitai", "sonarqubecloud"]
    public static let refreshOptions = [1, 2, 5, 10, 15, 30]

    /// The organizations to watch, in the order the user picked them.
    public var orgs: [String]
    public var authSource: AuthSource
    public var refreshMinutes: Int
    /// Repositories to leave out, as `owner/name`.
    public var ignoredRepos: [String]
    public var ignoredBots: [String]
    public var notificationsEnabled: Bool
    public var launchAtLogin: Bool
    public var automaticUpdates: Bool
    public var globalShortcut: Bool
    /// Days without a review before one of my PRs shows as waiting; 0 hides the list.
    public var waitingReviewDays: Int
    public var hasCompletedSetup: Bool
    public var popoverLayout: PopoverLayout

    public static let defaults = AppSettings(
        orgs: [],
        authSource: .ghCli,
        refreshMinutes: 5,
        ignoredRepos: [],
        ignoredBots: defaultIgnoredBots,
        notificationsEnabled: true,
        launchAtLogin: false,
        automaticUpdates: true,
        globalShortcut: true,
        waitingReviewDays: 2,
        hasCompletedSetup: false,
        popoverLayout: .single
    )

    public init(
        orgs: [String],
        authSource: AuthSource,
        refreshMinutes: Int,
        ignoredRepos: [String],
        ignoredBots: [String],
        notificationsEnabled: Bool,
        launchAtLogin: Bool,
        automaticUpdates: Bool = true,
        globalShortcut: Bool = true,
        waitingReviewDays: Int = 2,
        hasCompletedSetup: Bool,
        popoverLayout: PopoverLayout = .single
    ) {
        self.orgs = orgs
        self.authSource = authSource
        self.refreshMinutes = refreshMinutes
        self.ignoredRepos = ignoredRepos
        self.ignoredBots = ignoredBots
        self.notificationsEnabled = notificationsEnabled
        self.launchAtLogin = launchAtLogin
        self.automaticUpdates = automaticUpdates
        self.globalShortcut = globalShortcut
        self.waitingReviewDays = waitingReviewDays
        self.hasCompletedSetup = hasCompletedSetup
        self.popoverLayout = popoverLayout
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let base = Self.defaults
        orgs = try Self.decodeOrganizations(values)
        authSource = try values.decodeIfPresent(AuthSource.self, forKey: .authSource) ?? base.authSource
        refreshMinutes = try values.decodeIfPresent(Int.self, forKey: .refreshMinutes) ?? base.refreshMinutes
        let repos = try values.decodeIfPresent([String].self, forKey: .ignoredRepos) ?? base.ignoredRepos
        ignoredRepos = Self.qualified(repos, defaultOwner: orgs.first)
        ignoredBots = try values.decodeIfPresent([String].self, forKey: .ignoredBots) ?? base.ignoredBots
        notificationsEnabled = try values.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? base.notificationsEnabled
        launchAtLogin = try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? base.launchAtLogin
        automaticUpdates = try values.decodeIfPresent(Bool.self, forKey: .automaticUpdates) ?? base.automaticUpdates
        globalShortcut = try values.decodeIfPresent(Bool.self, forKey: .globalShortcut) ?? base.globalShortcut
        waitingReviewDays = try values.decodeIfPresent(Int.self, forKey: .waitingReviewDays) ?? base.waitingReviewDays
        hasCompletedSetup = try values.decodeIfPresent(Bool.self, forKey: .hasCompletedSetup) ?? base.hasCompletedSetup
        popoverLayout = try values.decodeIfPresent(PopoverLayout.self, forKey: .popoverLayout) ?? base.popoverLayout
    }

    private enum CodingKeys: String, CodingKey {
        case orgs, org, authSource, refreshMinutes, ignoredRepos, ignoredBots, notificationsEnabled
        case launchAtLogin, automaticUpdates, globalShortcut, waitingReviewDays, hasCompletedSetup, popoverLayout
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(orgs, forKey: .orgs)
        try values.encode(authSource, forKey: .authSource)
        try values.encode(refreshMinutes, forKey: .refreshMinutes)
        try values.encode(ignoredRepos, forKey: .ignoredRepos)
        try values.encode(ignoredBots, forKey: .ignoredBots)
        try values.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try values.encode(launchAtLogin, forKey: .launchAtLogin)
        try values.encode(automaticUpdates, forKey: .automaticUpdates)
        try values.encode(globalShortcut, forKey: .globalShortcut)
        try values.encode(waitingReviewDays, forKey: .waitingReviewDays)
        try values.encode(hasCompletedSetup, forKey: .hasCompletedSetup)
        try values.encode(popoverLayout, forKey: .popoverLayout)
    }

    /// Settings saved before 0.4 hold a single `org`.
    private static func decodeOrganizations(_ values: KeyedDecodingContainer<CodingKeys>) throws -> [String] {
        if let orgs = try values.decodeIfPresent([String].self, forKey: .orgs) { return orgs }
        let legacy = try values.decodeIfPresent(String.self, forKey: .org) ?? ""
        return legacy.isEmpty ? [] : [legacy]
    }

    /// Earlier versions stored bare repository names, which belonged to the only organization.
    private static func qualified(_ repos: [String], defaultOwner: String?) -> [String] {
        repos.map { $0.contains("/") || defaultOwner == nil ? $0 : "\(defaultOwner!)/\($0)" }
    }

    /// The bare names of the ignored repositories that belong to `org`.
    public func ignoredRepositories(in org: String) -> Set<String> {
        let prefix = org.lowercased() + "/"
        return Set(ignoredRepos.compactMap { entry in
            entry.lowercased().hasPrefix(prefix) ? String(entry.dropFirst(prefix.count)) : nil
        })
    }
}
