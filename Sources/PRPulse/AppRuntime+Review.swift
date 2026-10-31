import AppKit
import PRPulseCore

private enum ReviewFolder {
    case use(URL)
    case without
    case cancel
}

/// Asking an agent on this Mac to review a pull request: in the background through the Claude Code command line when
/// it is ready, or as a draft in Claude Desktop.
extension AppRuntime {
    private var desktopIsReady: Bool { reviewAgent.availability() == .ready }

    var canReview: Bool {
        settings.settings.reviewAgentEnabled && (cliState.isReady || desktopIsReady)
    }

    /// The draft in Claude Desktop as a second choice, when the main action runs in the background.
    var offersDraft: Bool {
        canReview && cliState.isReady && desktopIsReady
    }

    var agentActions: AgentActions {
        AgentActions(
            open: { [weak self] in self?.agents.open($0) },
            remove: { [weak self] in self?.agents.cancelOrRemove($0) },
            answer: { [weak self] in self?.agents.answer($0, allow: $1) },
            ask: { [weak self] in self?.askFollowUp($0, $1) },
            retry: { [weak self] in self?.retry($0) },
            continueInDesktop: { [weak self] in self?.continueInDesktop($0) },
            continueInTerminal: { [weak self] in self?.continueInTerminal($0) },
            consumeFocus: { [weak self] in self?.agents.consumeFocus() }
        )
    }

    // MARK: Command line status

    /// Looks again at the Claude Code command line, at most every 20 seconds unless `force` is set.
    func refreshCLI(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastCLICheck) > 20 else { return }
        lastCLICheck = Date()
        Task { cliState = await CLIState.check() }
    }

    func checkCLI() async -> CLIState {
        lastCLICheck = Date()
        cliState = await CLIState.check()
        return cliState
    }

    // MARK: Asking for a review

    func requestReview(of pr: PullRequestSnapshot) {
        begin(pr, inBackground: cliState.isReady)
    }

    func requestDraftReview(of pr: PullRequestSnapshot) {
        begin(pr, inBackground: false)
    }

    /// Opens a session that asks for nothing but a reply, to see that the connection works.
    func testReviewAgent() {
        guard desktopIsReady else { return showAlert(tr("agents.missing.title"), tr("agents.missing.detail")) }
        launch(AgentLaunch(prompt: tr("agents.test.prompt"), folder: nil))
    }

    private func begin(_ pr: PullRequestSnapshot, inBackground: Bool) {
        if inBackground {
            if let running = agents.list.running(for: pr.ref) { return agents.requestFocus(run: running.id) }
        } else if !desktopIsReady {
            return showAlert(tr("agents.missing.title"), tr("agents.missing.detail"))
        }
        let request = ReviewRequest(ref: pr.ref, url: pr.url)
        Task { await startReview(request, title: pr.title, inBackground: inBackground) }
    }

    private func retry(_ run: AgentRun) {
        agents.remove(run.id)
        Task { await startReview(ReviewRequest(ref: run.ref, url: run.url), title: run.title, inBackground: true) }
    }

    private func startReview(_ request: ReviewRequest, title: String, inBackground: Bool) async {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folder: URL?
        switch await reviewFolder(for: request.ref, home: home) {
        case .use(let url): folder = url
        case .without: folder = nil
        case .cancel: return
        }
        let current = settings.settings
        let skills = await Task.detached { ReviewSkillCatalog.discover(home: home) }.value
        let skill = ReviewSkillCatalog.resolve(choice: current.reviewSkill, from: skills)
        let template = ReviewPrompt.template(
            custom: current.reviewPrompt, generic: tr("agents.prompt.generic"), withSkill: tr("agents.prompt.skill"), skill: skill?.name
        )
        let prompt = ReviewPrompt.render(template, for: request, skill: skill?.name)
        guard inBackground else { return launch(AgentLaunch(prompt: prompt, folder: folder)) }
        guard let cli = ClaudeCLI.locate(home: home) else { return showAlert(tr("agents.run.failedTitle"), tr("agents.cli.missing")) }
        agents.start(request: request, title: title, prompt: prompt, folder: folder, skill: skill?.name, approval: current.reviewApproval, cli: cli)
        agents.requestFocus(run: nil)
    }

    // MARK: What happens after

    func agentFinished(_ run: AgentRun) {
        let title = run.state == .finished ? tr("agents.done.title") : tr("agents.run.failedTitle")
        showMascotBubble(title: title, detail: "\(run.ref.shortName) \(run.title)", seconds: 8)
        if settings.settings.notificationsEnabled { Task { await notifier.deliver(run: run) } }
    }

    func agentNeedsApproval(_ run: AgentRun) {
        guard let approval = run.approval else { return }
        showMascotBubble(title: tr("agents.approval.title"), detail: "\(run.ref.shortName) \(approval.tool)", seconds: 10)
        if settings.settings.notificationsEnabled { Task { await notifier.deliver(run: run) } }
    }

    private func askFollowUp(_ id: UUID, _ question: String) {
        agents.ask(id, question: question, approval: settings.settings.reviewApproval, cli: ClaudeCLI.locate(home: FileManager.default.homeDirectoryForCurrentUser))
    }

    func openAgentRun(_ id: UUID) {
        agents.requestFocus(run: id)
        onOpenPanel()
    }

    private func continueInDesktop(_ run: AgentRun) {
        guard desktopIsReady else { return showAlert(tr("agents.missing.title"), tr("agents.missing.detail")) }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let folder = run.folder == home ? nil : URL(fileURLWithPath: run.folder)
        launch(AgentLaunch(prompt: ClaudeCLI.continuationPrompt(url: run.url, review: run.output ?? ""), folder: folder))
    }

    private func continueInTerminal(_ run: AgentRun) {
        guard let cli = ClaudeCLI.locate(home: FileManager.default.homeDirectoryForCurrentUser), let session = run.sessionID else { return }
        let script = ClaudeCLI.resumeScript(cli: cli, folder: run.folder, sessionID: session)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("PRPulse-resume-\(run.id.uuidString).command")
        do {
            try script.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            NSWorkspace.shared.open(file)
        } catch {
            showAlert(tr("agents.failed.title"), error.localizedDescription)
        }
    }

    private func launch(_ launch: AgentLaunch) {
        do {
            try reviewAgent.launch(launch)
        } catch {
            showAlert(tr("agents.failed.title"), tr("agents.failed.detail"))
        }
    }

    // MARK: Folder

    /// What the viewer chose (the repository's folder, else its organization's default project), else a clone found in
    /// the usual folders, else the folder the viewer points to now.
    private func reviewFolder(for ref: PullRequestRef, home: URL) async -> ReviewFolder {
        let current = settings.settings
        switch ReviewFolders.saved(for: ref, repositories: current.reviewFolders, organizations: current.reviewOrgFolders, isFolder: Self.isFolder) {
        case .use(let url): return .use(url)
        case .without: return .without
        case nil: break
        }
        let found = await Task.detached {
            RepositoryLocator.find(owner: ref.owner, repo: ref.repo, roots: RepositoryLocator.roots(home: home))
        }.value
        if let found { return .use(found) }
        return askForFolder(of: ref)
    }

    private static func isFolder(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func askForFolder(of ref: PullRequestRef) -> ReviewFolder {
        let name = "\(ref.owner)/\(ref.repo)"
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = tr("agents.folder.title", name)
        alert.informativeText = tr("agents.folder.detail")
        alert.addButton(withTitle: tr("agents.folder.choose"))
        alert.addButton(withTitle: tr("agents.folder.without"))
        alert.addButton(withTitle: tr("agents.folder.cancel"))
        let forTheWholeOrganization = NSButton(checkboxWithTitle: tr("agents.folder.all", ref.owner), target: nil, action: nil)
        alert.accessoryView = forTheWholeOrganization
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.message = tr("agents.folder.panel", name)
            guard panel.runModal() == .OK, let url = panel.url else { return .cancel }
            if forTheWholeOrganization.state == .on {
                settings.settings.reviewOrgFolders[ref.ownerKey] = url.path
            } else {
                remember(url.path, for: ref)
            }
            return .use(url)
        case .alertSecondButtonReturn:
            remember("", for: ref)
            return .without
        default:
            return .cancel
        }
    }

    private func remember(_ path: String, for ref: PullRequestRef) {
        settings.settings.reviewFolders[ref.folderKey] = path
    }

    private func showAlert(_ title: String, _ detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }
}
