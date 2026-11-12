import AppKit
import PRPulseCore

private enum ReviewFolder {
    case use(URL)
    case without
    case cancel
}

/// Taking a pull request to the app or the terminal the viewer chose, with the words, the folder and the skill in place.
extension AppRuntime {
    // MARK: What can be done

    private func isReady(_ destination: ReviewDestination) -> Bool {
        if destination == .custom { return !settings.settings.reviewCustomCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let link = destination.appLink else { return true }
        return NSWorkspace.shared.urlForApplication(toOpen: link) != nil
    }

    /// Which destinations are there to use now: the apps that are installed, the terminals, and the custom command once it is written.
    func destinationStatuses() -> [ReviewDestination: Bool] {
        Dictionary(uniqueKeysWithValues: ReviewDestination.allCases.map { ($0, isReady($0)) })
    }

    /// What the viewer chose, or the first app that is installed when that one is not, or Claude Code.
    private var primaryDestination: ReviewDestination {
        let chosen = settings.settings.reviewDestination
        if isReady(chosen) { return chosen }
        return ReviewDestination.allCases.first { $0.style == .link && isReady($0) } ?? .claudeCode
    }

    var reviewActions: ReviewActions {
        guard settings.settings.reviewAgentEnabled else { return ReviewActions() }
        let primary = primaryDestination
        return ReviewActions(
            primary: primary,
            others: ReviewDestination.allCases.filter { $0 != primary && isReady($0) },
            review: { [weak self] pr, destination in self?.requestReview(of: pr, in: destination) },
            reviewTogether: { [weak self] prs, scope in self?.requestReview(of: prs, scope: scope) },
            reviewEach: { [weak self] prs in self?.requestEachReview(of: prs) }
        )
    }

    // MARK: Asking for a review

    func requestReview(of pr: PullRequestSnapshot, in destination: ReviewDestination) {
        let request = ReviewRequest(ref: pr.ref, url: pr.url)
        Task { await startReview(request, in: destination) }
    }

    /// Several pull requests in one conversation, to be seen as one change: a whole stack, or the ones the viewer chose.
    func requestReview(of prs: [PullRequestSnapshot], scope: ReviewRequest.Scope) {
        guard !prs.isEmpty else { return }
        guard prs.count > 1 else { return requestReview(of: prs[0], in: primaryDestination) }
        let request = ReviewRequest(targets: prs.map { ReviewTarget(ref: $0.ref, url: $0.url) }, scope: scope)
        Task { await startReview(request, in: primaryDestination) }
    }

    /// One conversation for each pull request, one after the other: the folder of a repository may have to be asked for.
    func requestEachReview(of prs: [PullRequestSnapshot]) {
        let destination = primaryDestination
        Task {
            for pr in prs { await startReview(ReviewRequest(ref: pr.ref, url: pr.url), in: destination) }
        }
    }

    /// Opens the destination with a message that asks for nothing but a reply, to see that the way there works.
    func testReviewDestination() {
        let request = ReviewRequest(ref: PullRequestRef(owner: "", repo: "", number: 0), url: URL(string: "https://github.com")!)
        run(prompt: tr("agents.test.prompt"), folder: nil, request: request, in: primaryDestination)
    }

    private func startReview(_ request: ReviewRequest, in destination: ReviewDestination) async {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folder: URL?
        switch await reviewFolder(for: request.ref, home: home) {
        case .use(let url): folder = url
        case .without: folder = nil
        case .cancel: return
        }
        let current = settings.settings
        var skill: ReviewSkill?
        if destination.namesSkills {
            let skills = await Task.detached { ReviewSkillCatalog.discover(home: home) }.value
            skill = ReviewSkillCatalog.resolve(choice: current.reviewSkill, from: skills)
        }
        let words = promptWords(for: request.scope)
        let template = ReviewPrompt.template(custom: current.reviewPrompt, generic: words.generic, withSkill: words.withSkill, skill: skill?.name)
        run(prompt: ReviewPrompt.render(template, for: request, skill: skill?.name), folder: folder, request: request, in: destination)
    }

    private func run(prompt: String, folder: URL?, request: ReviewRequest, in destination: ReviewDestination) {
        let current = settings.settings
        do {
            let launch = try ReviewLauncher.plan(
                for: destination, prompt: prompt, folder: folder, request: request,
                customCommand: current.reviewCustomCommand, cliMissing: { tr("agents.cli.notFound", $0) }
            )
            try ReviewRunner.run(launch, terminal: current.reviewTerminal)
        } catch {
            showAlert(tr("agents.failed.title"), Self.failureDetail(error, destination))
        }
    }

    private static func failureDetail(_ error: Error, _ destination: ReviewDestination) -> String {
        switch error {
        case ReviewLaunchError.slashPrompt: tr("agents.failed.slash")
        case ReviewLaunchError.tooLong: tr("agents.failed.tooLong")
        case ReviewLaunchError.missingCommand: tr("agents.failed.noCommand")
        case ReviewLaunchError.emptyPrompt: tr("agents.failed.empty")
        case ReviewLaunchFailure.script(let text): text
        default: tr("agents.failed.detail", destination.title)
        }
    }

    private func promptWords(for scope: ReviewRequest.Scope) -> (generic: String, withSkill: String) {
        switch scope {
        case .single: (tr("agents.prompt.generic"), tr("agents.prompt.skill"))
        case .together: (tr("agents.prompt.together"), tr("agents.prompt.together.skill"))
        case .stack: (tr("agents.prompt.stack"), tr("agents.prompt.stack.skill"))
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
