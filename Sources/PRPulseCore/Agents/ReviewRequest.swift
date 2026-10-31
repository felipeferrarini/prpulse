import Foundation

/// A pull request the viewer asks an agent to review.
public struct ReviewRequest: Equatable, Sendable {
    public let ref: PullRequestRef
    public let url: URL

    public init(ref: PullRequestRef, url: URL) {
        self.ref = ref
        self.url = url
    }
}

/// What an agent is started with: the words to say and, when there is one, the clone to work in.
public struct AgentLaunch: Equatable, Sendable {
    public let prompt: String
    public let folder: URL?

    public init(prompt: String, folder: URL?) {
        self.prompt = prompt
        self.folder = folder
    }
}

public enum AgentAvailability: Equatable, Sendable {
    case ready
    case notInstalled
}

/// A coding agent on this Mac that can be asked to review a pull request.
public protocol ReviewAgent: Sendable {
    var id: String { get }
    var title: String { get }
    func availability() -> AgentAvailability
    @MainActor func launch(_ launch: AgentLaunch) throws
}

extension PullRequestRef {
    /// How a repository is named in the saved clone folders: `owner/name`, in lower case.
    public var folderKey: String { "\(owner)/\(repo)".lowercased() }

    /// How an organization is named in the default project folders: the owner, in lower case.
    public var ownerKey: String { owner.lowercased() }
}
