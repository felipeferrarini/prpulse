import Foundation

public enum AuthSource: String, Codable, Sendable {
    case ghCli
    case personalToken
}

/// Where the mascot sits: the distance from the bottom right corner of one screen, so it follows that corner
/// when the screen changes size.
public struct MascotAnchor: Codable, Equatable, Sendable {
    public var screen: String
    public var right: Double
    public var bottom: Double

    public init(screen: String, right: Double, bottom: Double) {
        self.screen = screen
        self.right = right
        self.bottom = bottom
    }
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
    /// Comments and threads from bots do not ask the viewer to reply.
    public var ignoreBotComments: Bool
    /// Leaves the pull requests opened by bots out of the review list.
    public var ignoreBotPullRequests: Bool
    public var notificationsEnabled: Bool
    public var launchAtLogin: Bool
    public var automaticUpdates: Bool
    public var globalShortcut: Bool
    public var mascotEnabled: Bool
    public var mascotPack: String
    /// How many screen points one sprite pixel takes: 3, 4 or 6.
    public var mascotScale: Int
    public var mascotIntroduced: Bool
    public var mascotAnchor: MascotAnchor?
    /// Shows "Review with Claude" on the pull requests waiting for the viewer's review.
    public var reviewAgentEnabled: Bool
    /// `ReviewSkillCatalog.automaticChoice`, `noneChoice` or the name of a skill.
    public var reviewSkill: String
    /// Who decides when the agent wants to do more than read.
    /// Where "Review with…" takes a pull request: an app or a terminal.
    public var reviewDestination: ReviewDestination
    /// The terminal that runs the destinations made of a command: an app's bundle identifier or path, empty for the one macOS uses.
    public var reviewTerminal: String
    /// The command of the custom destination.
    public var reviewCustomCommand: String
    /// The words sent with the request; empty uses the built-in text.
    public var reviewPrompt: String
    /// The folder picked for one repository, by `owner/name`. An empty path means there is no folder to use.
    public var reviewFolders: [String: String]
    /// The default project of an organization, by owner: the folder every one of its sessions opens in.
    public var reviewOrgFolders: [String: String]
    public var hasCompletedSetup: Bool
    public var popoverLayout: PopoverLayout
    /// How each list in the popover is ordered.
    public var reviewSort: PullRequestSort
    public var mineSort: PullRequestSort
    /// Opens the list of changes after the app was updated.
    public var showNewsAfterUpdate: Bool
    /// The version whose changes the viewer was last shown; empty until the app has announced one.
    public var lastSeenVersion: String
    /// The client id of the OAuth App the team registered, for signing in from the browser; empty when there is none.
    public var oauthClientID: String
    /// Reacts when an author nudges the viewer to review again.
    public var nudgesEnabled: Bool
    public var nudgeSoundEnabled: Bool
    /// A `NudgeSoundChoice` id; an id that no longer resolves plays the default sound.
    public var nudgeSound: String
    /// Nudges that arrive before this are not played.
    public var nudgesPausedUntil: Date?

    public func areNudgesPaused(at date: Date) -> Bool {
        nudgesPausedUntil.map { date < $0 } ?? false
    }

    public static let defaults = AppSettings(
        orgs: [],
        authSource: .ghCli,
        refreshMinutes: 5,
        ignoredRepos: [],
        ignoredBots: defaultIgnoredBots,
        ignoreBotComments: true,
        ignoreBotPullRequests: true,
        notificationsEnabled: true,
        launchAtLogin: false,
        automaticUpdates: true,
        globalShortcut: true,
        mascotEnabled: true,
        mascotPack: "brasa",
        mascotScale: 4,
        mascotIntroduced: false,
        mascotAnchor: nil,
        reviewAgentEnabled: true,
        reviewSkill: ReviewSkillCatalog.automaticChoice,
        reviewDestination: .default,
        reviewTerminal: "",
        reviewCustomCommand: "",
        reviewPrompt: "",
        reviewFolders: [:],
        reviewOrgFolders: [:],
        hasCompletedSetup: false,
        popoverLayout: .single,
        reviewSort: .priority,
        mineSort: .priority,
        showNewsAfterUpdate: true,
        lastSeenVersion: "",
        oauthClientID: "",
        nudgesEnabled: true,
        nudgeSoundEnabled: true,
        nudgeSound: NudgeSoundChoice.defaultID,
        nudgesPausedUntil: nil
    )

    public init(
        orgs: [String],
        authSource: AuthSource,
        refreshMinutes: Int,
        ignoredRepos: [String],
        ignoredBots: [String],
        ignoreBotComments: Bool = true,
        ignoreBotPullRequests: Bool = true,
        notificationsEnabled: Bool,
        launchAtLogin: Bool,
        automaticUpdates: Bool = true,
        globalShortcut: Bool = true,
        mascotEnabled: Bool = true,
        mascotPack: String = "brasa",
        mascotScale: Int = 4,
        mascotIntroduced: Bool = false,
        mascotAnchor: MascotAnchor? = nil,
        reviewAgentEnabled: Bool = true,
        reviewSkill: String = ReviewSkillCatalog.automaticChoice,
        reviewDestination: ReviewDestination = .default,
        reviewTerminal: String = "",
        reviewCustomCommand: String = "",
        reviewPrompt: String = "",
        reviewFolders: [String: String] = [:],
        reviewOrgFolders: [String: String] = [:],
        hasCompletedSetup: Bool,
        popoverLayout: PopoverLayout = .single,
        reviewSort: PullRequestSort = .priority,
        mineSort: PullRequestSort = .priority,
        showNewsAfterUpdate: Bool = true,
        lastSeenVersion: String = "",
        oauthClientID: String = "",
        nudgesEnabled: Bool = true,
        nudgeSoundEnabled: Bool = true,
        nudgeSound: String = NudgeSoundChoice.defaultID,
        nudgesPausedUntil: Date? = nil
    ) {
        self.orgs = orgs
        self.authSource = authSource
        self.refreshMinutes = refreshMinutes
        self.ignoredRepos = ignoredRepos
        self.ignoredBots = ignoredBots
        self.ignoreBotComments = ignoreBotComments
        self.ignoreBotPullRequests = ignoreBotPullRequests
        self.notificationsEnabled = notificationsEnabled
        self.launchAtLogin = launchAtLogin
        self.automaticUpdates = automaticUpdates
        self.globalShortcut = globalShortcut
        self.mascotEnabled = mascotEnabled
        self.mascotPack = mascotPack
        self.mascotScale = mascotScale
        self.mascotIntroduced = mascotIntroduced
        self.mascotAnchor = mascotAnchor
        self.reviewAgentEnabled = reviewAgentEnabled
        self.reviewSkill = reviewSkill
        self.reviewDestination = reviewDestination
        self.reviewTerminal = reviewTerminal
        self.reviewCustomCommand = reviewCustomCommand
        self.reviewPrompt = reviewPrompt
        self.reviewFolders = reviewFolders
        self.reviewOrgFolders = reviewOrgFolders
        self.hasCompletedSetup = hasCompletedSetup
        self.popoverLayout = popoverLayout
        self.reviewSort = reviewSort
        self.mineSort = mineSort
        self.showNewsAfterUpdate = showNewsAfterUpdate
        self.lastSeenVersion = lastSeenVersion
        self.oauthClientID = oauthClientID
        self.nudgesEnabled = nudgesEnabled
        self.nudgeSoundEnabled = nudgeSoundEnabled
        self.nudgeSound = nudgeSound
        self.nudgesPausedUntil = nudgesPausedUntil
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
        ignoreBotComments = try values.decodeIfPresent(Bool.self, forKey: .ignoreBotComments) ?? base.ignoreBotComments
        ignoreBotPullRequests = try values.decodeIfPresent(Bool.self, forKey: .ignoreBotPullRequests) ?? base.ignoreBotPullRequests
        notificationsEnabled = try values.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? base.notificationsEnabled
        launchAtLogin = try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? base.launchAtLogin
        automaticUpdates = try values.decodeIfPresent(Bool.self, forKey: .automaticUpdates) ?? base.automaticUpdates
        globalShortcut = try values.decodeIfPresent(Bool.self, forKey: .globalShortcut) ?? base.globalShortcut
        mascotEnabled = try values.decodeIfPresent(Bool.self, forKey: .mascotEnabled) ?? base.mascotEnabled
        mascotPack = try values.decodeIfPresent(String.self, forKey: .mascotPack) ?? base.mascotPack
        mascotScale = try values.decodeIfPresent(Int.self, forKey: .mascotScale) ?? base.mascotScale
        mascotIntroduced = try values.decodeIfPresent(Bool.self, forKey: .mascotIntroduced) ?? base.mascotIntroduced
        mascotAnchor = try values.decodeIfPresent(MascotAnchor.self, forKey: .mascotAnchor)
        reviewAgentEnabled = try values.decodeIfPresent(Bool.self, forKey: .reviewAgentEnabled) ?? base.reviewAgentEnabled
        reviewSkill = try values.decodeIfPresent(String.self, forKey: .reviewSkill) ?? base.reviewSkill
        reviewDestination = (try? values.decodeIfPresent(ReviewDestination.self, forKey: .reviewDestination)).flatMap { $0 } ?? base.reviewDestination
        reviewTerminal = try values.decodeIfPresent(String.self, forKey: .reviewTerminal) ?? base.reviewTerminal
        reviewCustomCommand = try values.decodeIfPresent(String.self, forKey: .reviewCustomCommand) ?? base.reviewCustomCommand
        reviewPrompt = try values.decodeIfPresent(String.self, forKey: .reviewPrompt) ?? base.reviewPrompt
        reviewFolders = try values.decodeIfPresent([String: String].self, forKey: .reviewFolders) ?? base.reviewFolders
        reviewOrgFolders = try values.decodeIfPresent([String: String].self, forKey: .reviewOrgFolders) ?? base.reviewOrgFolders
        hasCompletedSetup = try values.decodeIfPresent(Bool.self, forKey: .hasCompletedSetup) ?? base.hasCompletedSetup
        popoverLayout = try values.decodeIfPresent(PopoverLayout.self, forKey: .popoverLayout) ?? base.popoverLayout
        reviewSort = try values.decodeIfPresent(PullRequestSort.self, forKey: .reviewSort) ?? base.reviewSort
        mineSort = try values.decodeIfPresent(PullRequestSort.self, forKey: .mineSort) ?? base.mineSort
        showNewsAfterUpdate = try values.decodeIfPresent(Bool.self, forKey: .showNewsAfterUpdate) ?? base.showNewsAfterUpdate
        lastSeenVersion = try values.decodeIfPresent(String.self, forKey: .lastSeenVersion) ?? base.lastSeenVersion
        oauthClientID = try values.decodeIfPresent(String.self, forKey: .oauthClientID) ?? base.oauthClientID
        nudgesEnabled = try values.decodeIfPresent(Bool.self, forKey: .nudgesEnabled) ?? base.nudgesEnabled
        nudgeSoundEnabled = try values.decodeIfPresent(Bool.self, forKey: .nudgeSoundEnabled) ?? base.nudgeSoundEnabled
        nudgeSound = try values.decodeIfPresent(String.self, forKey: .nudgeSound) ?? base.nudgeSound
        nudgesPausedUntil = try values.decodeIfPresent(Date.self, forKey: .nudgesPausedUntil)
    }

    private enum CodingKeys: String, CodingKey {
        case orgs, org, authSource, refreshMinutes, ignoredRepos, ignoredBots, ignoreBotComments, ignoreBotPullRequests, notificationsEnabled
        case launchAtLogin, automaticUpdates, globalShortcut, hasCompletedSetup, popoverLayout, reviewSort, mineSort
        case mascotEnabled, mascotPack, mascotScale, mascotIntroduced, mascotAnchor
        case reviewAgentEnabled, reviewSkill, reviewDestination, reviewTerminal, reviewCustomCommand, reviewPrompt, reviewFolders, reviewOrgFolders
        case showNewsAfterUpdate, lastSeenVersion, oauthClientID
        case nudgesEnabled, nudgeSoundEnabled, nudgeSound, nudgesPausedUntil
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(orgs, forKey: .orgs)
        try values.encode(authSource, forKey: .authSource)
        try values.encode(refreshMinutes, forKey: .refreshMinutes)
        try values.encode(ignoredRepos, forKey: .ignoredRepos)
        try values.encode(ignoredBots, forKey: .ignoredBots)
        try values.encode(ignoreBotComments, forKey: .ignoreBotComments)
        try values.encode(ignoreBotPullRequests, forKey: .ignoreBotPullRequests)
        try values.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try values.encode(launchAtLogin, forKey: .launchAtLogin)
        try values.encode(automaticUpdates, forKey: .automaticUpdates)
        try values.encode(globalShortcut, forKey: .globalShortcut)
        try values.encode(mascotEnabled, forKey: .mascotEnabled)
        try values.encode(mascotPack, forKey: .mascotPack)
        try values.encode(mascotScale, forKey: .mascotScale)
        try values.encode(mascotIntroduced, forKey: .mascotIntroduced)
        try values.encodeIfPresent(mascotAnchor, forKey: .mascotAnchor)
        try values.encode(reviewAgentEnabled, forKey: .reviewAgentEnabled)
        try values.encode(reviewSkill, forKey: .reviewSkill)
        try values.encode(reviewDestination, forKey: .reviewDestination)
        try values.encode(reviewTerminal, forKey: .reviewTerminal)
        try values.encode(reviewCustomCommand, forKey: .reviewCustomCommand)
        try values.encode(reviewPrompt, forKey: .reviewPrompt)
        try values.encode(reviewFolders, forKey: .reviewFolders)
        try values.encode(reviewOrgFolders, forKey: .reviewOrgFolders)
        try values.encode(hasCompletedSetup, forKey: .hasCompletedSetup)
        try values.encode(popoverLayout, forKey: .popoverLayout)
        try values.encode(reviewSort, forKey: .reviewSort)
        try values.encode(mineSort, forKey: .mineSort)
        try values.encode(showNewsAfterUpdate, forKey: .showNewsAfterUpdate)
        try values.encode(lastSeenVersion, forKey: .lastSeenVersion)
        try values.encode(oauthClientID, forKey: .oauthClientID)
        try values.encode(nudgesEnabled, forKey: .nudgesEnabled)
        try values.encode(nudgeSoundEnabled, forKey: .nudgeSoundEnabled)
        try values.encode(nudgeSound, forKey: .nudgeSound)
        try values.encodeIfPresent(nudgesPausedUntil, forKey: .nudgesPausedUntil)
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
