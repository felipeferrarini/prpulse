import AppKit
import Combine
import PRPulseCore

/// What the viewer asked the panel to show about the agents: set when a review starts or a notification is opened.
struct AgentFocus: Equatable {
    var token = 0
    var isPending = false
    var run: UUID?
}

/// The reviews the agents are doing in the background, and the ones they did.
@MainActor
final class AgentRunStore: ObservableObject {
    private static let timeout: Duration = .seconds(20 * 60)
    /// How long a review that is ready keeps its conversation open for a follow-up.
    private static let idle: Duration = .seconds(15 * 60)
    private static let interruptGrace: Duration = .seconds(8)

    @Published private(set) var list: AgentRunList
    @Published private(set) var focus = AgentFocus()
    var onFinished: (AgentRun) -> Void = { _ in }
    var onNeedsApproval: (AgentRun) -> Void = { _ in }

    private let storage: URL?
    private var jobs: [UUID: ClaudeCLIProcess] = [:]
    private var timeouts: [UUID: Task<Void, Never>] = [:]
    private var idleTimers: [UUID: Task<Void, Never>] = [:]
    private var timedOut = Set<UUID>()
    private var interrupted = Set<UUID>()
    private var termination: NSObjectProtocol?

    nonisolated static var defaultStorage: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("PRPulse/agent-runs.json")
    }

    /// With a `storage` the runs come back after a restart; the ones that were still going cannot have finished.
    init(storage: URL? = AgentRunStore.defaultStorage, runs: AgentRunList? = nil) {
        self.storage = storage
        var loaded = runs ?? Self.load(storage)
        loaded.interrupt(at: Date(), message: tr("agents.run.interrupted"))
        list = loaded
        termination = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopAll() }
        }
    }

    var hasRunning: Bool { !list.running.isEmpty }

    // MARK: Starting and stopping

    @discardableResult
    func start(request: ReviewRequest, title: String, prompt: String, folder: URL?, skill: String?, approval: ReviewApproval, cli: URL) -> AgentRun {
        if let running = list.running(for: request.ref) { return running }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let session = UUID()
        let run = AgentRun(
            ref: request.ref, title: title, url: request.url, folder: (folder ?? home).path, skill: skill,
            startedAt: Date(), sessionID: session.uuidString.lowercased()
        )
        list.add(run)
        save()
        let name = "PRPulse \(request.ref.owner)/\(request.ref.repo)#\(request.ref.number)"
        begin(run.id, cli: cli, arguments: ClaudeCLI.reviewArguments(sessionID: session, name: name, folder: (folder ?? home).path, approval: approval), directory: folder ?? home, message: prompt)
        return run
    }

    /// Stops a run that is going, or takes a finished one off the list. A follow-up that is going is only interrupted:
    /// the review it comes after stays.
    func cancelOrRemove(_ id: UUID) {
        guard let run = list.run(id: id), run.isRunning, run.question != nil, let job = jobs[id] else { return remove(id) }
        interrupted.insert(id)
        job.interrupt()
        Task { [weak self] in
            try? await Task.sleep(for: Self.interruptGrace)
            guard let self, self.interrupted.contains(id) else { return }
            self.jobs[id]?.stop()
        }
    }

    func remove(_ id: UUID) {
        jobs[id]?.stop()
        list.remove(id)
        save()
    }

    func open(_ id: UUID) {
        list.markSeen(id)
        save()
    }

    func requestFocus(run: UUID?) {
        focus = AgentFocus(token: focus.token + 1, isPending: true, run: run)
    }

    func consumeFocus() {
        guard focus.isPending else { return }
        focus.isPending = false
    }

    // MARK: Talking to the agent

    /// Lets the agent use the tool it asked for, or tells it not to.
    func answer(_ id: UUID, allow: Bool) {
        guard let approval = list.run(id: id)?.approval else { return }
        jobs[id]?.answer(requestID: approval.requestID, allow: allow)
        list.setApproval(id, nil)
    }

    /// A question about a review that is ready, in the same conversation. It starts again from the saved session when the
    /// conversation was closed.
    func ask(_ id: UUID, question: String, approval: ReviewApproval, cli: URL?) {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, list.ask(id, question: text, at: Date()) else { return }
        save()
        idleTimers[id]?.cancel()
        idleTimers[id] = nil
        armTimeout(id)
        if let job = jobs[id], !job.isClosing { return job.ask(text) }
        guard let run = list.run(id: id), let session = run.sessionID, let cli else {
            return fail(id, message: tr("agents.cli.missing"))
        }
        begin(id, cli: cli, arguments: ClaudeCLI.resumeArguments(sessionID: session, folder: run.folder, approval: approval), directory: URL(fileURLWithPath: run.folder), message: text)
    }

    private func begin(_ id: UUID, cli: URL, arguments: [String], directory: URL, message: String) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let job = ClaudeCLIProcess(executable: cli, arguments: arguments, directory: directory, environment: ClaudeCLI.environment(home: home))
        jobs[id] = job
        do {
            try job.run(
                prompt: message,
                onEvent: { [weak self] event in MainActor.assumeIsolated { self?.handle(event, for: id) } },
                onExit: { [weak self] status, errors in MainActor.assumeIsolated { self?.exited(id, job: job, status: status, errors: errors) } }
            )
            armTimeout(id)
        } catch {
            jobs[id] = nil
            fail(id, message: error.localizedDescription)
        }
    }

    private func armTimeout(_ id: UUID) {
        timeouts[id]?.cancel()
        timeouts[id] = Task { [weak self] in
            try? await Task.sleep(for: Self.timeout)
            guard !Task.isCancelled else { return }
            self?.timeOut(id)
        }
    }

    private func disarmTimeout(_ id: UUID) {
        timeouts[id]?.cancel()
        timeouts[id] = nil
    }

    private func stopAll() {
        for job in jobs.values { job.stop() }
    }

    private func timeOut(_ id: UUID) {
        timedOut.insert(id)
        jobs[id]?.stop()
    }

    /// A review that is ready keeps its conversation open for a while, so a follow-up is quick.
    private func keepOpen(_ id: UUID) {
        idleTimers[id]?.cancel()
        guard jobs[id] != nil else { return }
        idleTimers[id] = Task { [weak self] in
            try? await Task.sleep(for: Self.idle)
            guard !Task.isCancelled else { return }
            self?.jobs[id]?.closeInput()
        }
    }

    // MARK: What the agent reports

    private func handle(_ event: ClaudeStreamEvent, for id: UUID) {
        switch event {
        case .session(let session):
            list.update(id) { $0.sessionID = session }
        case .tool(let name, let detail):
            list.update(id) { $0.activity = Self.activity(tool: name, detail: detail) }
        case .writing:
            list.update(id) { $0.activity = tr("agents.activity.writing") }
        case .permission(let request):
            list.setApproval(id, ToolApproval(requestID: request.id, tool: request.tool, summary: request.summary))
            if let run = list.run(id: id) { onNeedsApproval(run) }
        case .permissionCancelled(let requestID):
            if list.run(id: id)?.approval?.requestID == requestID { list.setApproval(id, nil) }
        case .result(let text, let isError, let session):
            if let session { list.update(id) { $0.sessionID = session } }
            if interrupted.remove(id) != nil { return finish(id, output: tr("agents.run.stopped")) }
            isError ? fail(id, message: text) : finish(id, output: text)
        }
    }

    private func exited(_ id: UUID, job: ClaudeCLIProcess, status: Int32, errors: String) {
        if jobs[id] === job { jobs[id] = nil }
        guard jobs[id] == nil else { return }
        disarmTimeout(id)
        idleTimers[id]?.cancel()
        idleTimers[id] = nil
        interrupted.remove(id)
        guard let run = list.run(id: id), run.isRunning else {
            timedOut.remove(id)
            return
        }
        if timedOut.remove(id) != nil { return fail(id, message: tr(run.approval == nil ? "agents.run.timeout" : "agents.run.approvalTimeout")) }
        if job.wasStopped { return run.question == nil ? remove(id) : fail(id, message: tr("agents.run.stopped")) }
        fail(id, message: errors.isEmpty ? tr("agents.run.exited", Int(status)) : errors)
    }

    private func finish(_ id: UUID, output: String) {
        disarmTimeout(id)
        list.finish(id, output: output, at: Date())
        save()
        keepOpen(id)
        if let run = list.run(id: id) { onFinished(run) }
    }

    private func fail(_ id: UUID, message: String) {
        disarmTimeout(id)
        list.fail(id, message: message, at: Date())
        save()
        if let run = list.run(id: id) { onFinished(run) }
    }

    private static func activity(tool: String, detail: String?) -> String {
        guard let detail else { return tr("agents.activity.other") }
        switch tool {
        case "Read": return tr("agents.activity.read", detail)
        case "Grep", "Glob": return tr("agents.activity.search", detail)
        case "Bash": return tr("agents.activity.command", detail)
        case "Skill": return tr("agents.activity.skill", detail)
        case "Task", "Agent": return tr("agents.activity.delegate", detail)
        default: return tr("agents.activity.other")
        }
    }

    // MARK: Saving

    private static func load(_ storage: URL?) -> AgentRunList {
        guard let storage, let data = try? Data(contentsOf: storage) else { return AgentRunList() }
        return (try? JSONDecoder().decode(AgentRunList.self, from: data)) ?? AgentRunList()
    }

    private func save() {
        guard let storage else { return }
        try? FileManager.default.createDirectory(at: storage.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(list) { try? data.write(to: storage, options: .atomic) }
    }
}
