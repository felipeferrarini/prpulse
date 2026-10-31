import Foundation

/// One pull request of a review.
public struct ReviewTarget: Hashable, Codable, Sendable {
    public let ref: PullRequestRef
    public let url: URL

    public init(ref: PullRequestRef, url: URL) {
        self.ref = ref
        self.url = url
    }
}

/// What the viewer asks an agent to review: one pull request, several to be seen together, or a whole stack.
public struct ReviewRequest: Equatable, Sendable {
    public enum Scope: String, Codable, Equatable, Sendable {
        case single
        /// Pull requests chosen one by one, from one repository or several, reviewed as one change.
        case together
        /// The pull requests of a stack, bottom first.
        case stack
    }

    public let targets: [ReviewTarget]
    public let scope: Scope

    public init(ref: PullRequestRef, url: URL) {
        targets = [ReviewTarget(ref: ref, url: url)]
        scope = .single
    }

    /// `targets` must not be empty.
    public init(targets: [ReviewTarget], scope: Scope) {
        precondition(!targets.isEmpty, "a review needs at least one pull request")
        self.targets = targets
        self.scope = targets.count == 1 ? .single : scope
    }

    /// The first pull request: where the run is named and where its folder comes from.
    public var ref: PullRequestRef { targets[0].ref }
    public var url: URL { targets[0].url }
    public var isGroup: Bool { targets.count > 1 }
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
