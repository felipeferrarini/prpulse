import Foundation

/// A tool the agent waits for the viewer's answer to before it goes on.
public struct ToolApproval: Codable, Equatable, Sendable {
    public let requestID: String
    public let tool: String
    public let summary: String

    public init(requestID: String, tool: String, summary: String) {
        self.requestID = requestID
        self.tool = tool
        self.summary = summary
    }
}

/// One review an agent is doing, or did, in the background.
public struct AgentRun: Identifiable, Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable {
        case running
        case finished
        case failed
    }

    public let id: UUID
    public let ref: PullRequestRef
    public let title: String
    public let url: URL
    /// Where the agent works. Sessions belong to a folder, so it is also where a conversation is picked up again.
    public let folder: String
    public let skill: String?
    public let startedAt: Date
    public var state: State
    /// What the agent is doing right now, as a short line.
    public var activity: String?
    /// The review, or why the run failed.
    public var output: String?
    public var finishedAt: Date?
    public var sessionID: String?
    /// False until the viewer opens a run that finished.
    public var isSeen: Bool
    /// What the agent waits to be allowed to do.
    public var approval: ToolApproval?
    /// The follow-up being answered; its answer goes after the review instead of replacing it.
    public var question: String?
    /// All the pull requests, when the review is of several: `ref` and `url` are the first one.
    public var targets: [ReviewTarget]?
    public var scope: ReviewRequest.Scope?
    /// The folders of the other repositories, when the review reaches into more than one.
    public var extraFolders: [String]?

    public init(
        id: UUID = UUID(),
        ref: PullRequestRef,
        title: String,
        url: URL,
        folder: String,
        skill: String?,
        startedAt: Date,
        sessionID: String? = nil,
        targets: [ReviewTarget]? = nil,
        scope: ReviewRequest.Scope? = nil,
        extraFolders: [String]? = nil
    ) {
        self.id = id
        self.ref = ref
        self.title = title
        self.url = url
        self.folder = folder
        self.skill = skill
        self.startedAt = startedAt
        self.sessionID = sessionID
        self.targets = targets
        self.scope = scope
        self.extraFolders = extraFolders
        state = .running
        activity = nil
        output = nil
        finishedAt = nil
        isSeen = false
    }

    public var isRunning: Bool { state == .running }

    /// Every address of the review, the first one when it is of a single pull request.
    public var urls: [URL] { targets?.map(\.url) ?? [url] }
    public var isGroup: Bool { (targets?.count ?? 1) > 1 }

    fileprivate mutating func settle(at date: Date) {
        question = nil
        approval = nil
        activity = nil
        finishedAt = date
        isSeen = false
    }
}

/// The runs shown in the panel: the ones going on first, then the latest to finish.
public struct AgentRunList: Codable, Equatable, Sendable {
    public static let keptFinished = 20

    public private(set) var runs: [AgentRun]

    public init(runs: [AgentRun] = []) {
        self.runs = runs
    }

    public var running: [AgentRun] { runs.filter(\.isRunning) }
    public var hasUnseen: Bool { runs.contains { !$0.isRunning && !$0.isSeen } }
    public var needsApproval: Bool { runs.contains { $0.approval != nil } }

    public func run(id: UUID) -> AgentRun? { runs.first { $0.id == id } }

    /// The run that is still going for this pull request, if any.
    public func running(for ref: PullRequestRef) -> AgentRun? {
        runs.first { $0.isRunning && ($0.ref == ref || $0.targets?.contains { $0.ref == ref } == true) }
    }

    public mutating func add(_ run: AgentRun) {
        runs.insert(run, at: 0)
    }

    public mutating func update(_ id: UUID, _ change: (inout AgentRun) -> Void) {
        guard let index = runs.firstIndex(where: { $0.id == id }) else { return }
        change(&runs[index])
    }

    public static let separator = "\n\n──────────\n\n"

    public mutating func finish(_ id: UUID, output: String, at date: Date) {
        update(id) { run in
            guard run.isRunning else { return }
            run.state = .finished
            run.output = run.question == nil ? output : (run.output ?? "") + output
            run.settle(at: date)
        }
        trim()
    }

    /// A review that fails has nothing to show but why. A follow-up that fails leaves the review as it was.
    public mutating func fail(_ id: UUID, message: String, at date: Date) {
        update(id) { run in
            guard run.isRunning else { return }
            if run.question == nil {
                run.state = .failed
                run.output = message
            } else {
                run.state = .finished
                run.output = (run.output ?? "") + message
            }
            run.settle(at: date)
        }
        trim()
    }

    /// Takes a question about a review that is ready. The review stays on screen, with the question after it.
    @discardableResult
    public mutating func ask(_ id: UUID, question: String, at date: Date) -> Bool {
        guard let run = run(id: id), run.state == .finished else { return false }
        update(id) { run in
            run.state = .running
            run.question = question
            run.output = (run.output ?? "") + Self.separator + question + "\n\n"
            run.activity = nil
            run.approval = nil
            run.finishedAt = nil
            run.isSeen = true
        }
        return true
    }

    public mutating func setApproval(_ id: UUID, _ approval: ToolApproval?) {
        update(id) { run in
            guard run.isRunning else { return }
            run.approval = approval
        }
    }

    public mutating func markSeen(_ id: UUID) {
        update(id) { $0.isSeen = true }
    }

    public mutating func remove(_ id: UUID) {
        runs.removeAll { $0.id == id }
    }

    /// What was saved while PRPulse was closed cannot still be running.
    public mutating func interrupt(at date: Date, message: String) {
        for run in runs where run.isRunning { fail(run.id, message: message, at: date) }
    }

    private mutating func trim() {
        var finished = 0
        runs = runs.filter { run in
            if run.isRunning { return true }
            finished += 1
            return finished <= Self.keptFinished
        }
    }
}
