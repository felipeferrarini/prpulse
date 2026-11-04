import Foundation

/// Which sound a nudge plays: one that ships with macOS, or a file the viewer dropped into the app's sounds folder.
public enum NudgeSoundChoice: Equatable, Sendable {
    case system(String)
    case user(String)

    public static let fallback: NudgeSoundChoice = .system("Sosumi")
    public static let defaultID = fallback.id
    /// A longer file is cut here, so a loud nudge never plays for half a minute.
    public static let maxPlayback: TimeInterval = 3

    private static let systemPrefix = "system:"
    private static let userPrefix = "user:"

    public init?(id: String) {
        if id.hasPrefix(Self.systemPrefix), let name = Self.fileName(id.dropFirst(Self.systemPrefix.count)) {
            self = .system(name)
        } else if id.hasPrefix(Self.userPrefix), let name = Self.fileName(id.dropFirst(Self.userPrefix.count)) {
            self = .user(name)
        } else {
            return nil
        }
    }

    public var id: String {
        switch self {
        case let .system(name): Self.systemPrefix + name
        case let .user(file): Self.userPrefix + file
        }
    }

    /// What a menu shows: the file name without its extension for the viewer's own sounds.
    public var name: String {
        switch self {
        case let .system(name): name
        case let .user(file): (file as NSString).deletingPathExtension
        }
    }

    /// A bare file name: a sound id never reaches outside the folder it names.
    private static func fileName(_ text: Substring) -> String? {
        let name = String(text)
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains(":") else { return nil }
        return name
    }
}
