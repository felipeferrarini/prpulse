import AppKit
import PRPulseCore

extension AppRuntime {
    private static let reminderDelay: TimeInterval = 15 * 60

    var nudgeActions: NudgeActions {
        NudgeActions(
            candidates: { [weak self] in self?.nudgeCandidates(for: $0) ?? [] },
            send: { [weak self] pr, candidate, withMessage in self?.startNudge(pr, candidate, withMessage: withMessage) },
            opened: { [weak self] in self?.model?.acknowledgeNudges(openedURL: $0) }
        )
    }

    var nudgesPaused: Bool { settings.settings.areNudgesPaused(at: Date()) }

    func pauseNudges(until date: Date?) {
        settings.settings.nudgesPausedUntil = date
    }

    // MARK: Sending

    private func nudgeCandidates(for pr: PullRequestSnapshot) -> [NudgeCandidate] {
        guard let viewer = model?.viewerLogin else { return [] }
        let bots = Set(settings.settings.ignoredBots)
        let team = model?.lastSummary.map { TeamDirectory.members(in: $0, viewer: viewer, ignoredBots: bots) } ?? []
        return NudgeEligibility.candidates(for: pr, viewer: viewer, team: team, ignoredBots: bots, now: Date())
    }

    private func startNudge(_ pr: PullRequestSnapshot, _ candidate: NudgeCandidate, withMessage: Bool) {
        var message: String?
        if withMessage {
            guard let typed = NudgePrompt.ask(reviewer: candidate.login, title: pr.title) else { return }
            message = NudgeCodec.clean(typed)
        }
        let request = NudgeRequest(
            ref: pr.ref,
            reviewer: candidate.login,
            tone: candidate.tone,
            message: message,
            text: Self.commentText(reviewer: candidate.login, tone: candidate.tone, message: message, kind: candidate.kind),
            kind: candidate.kind
        )
        let nudger = ClientFactory.nudger(settings: settings)
        Task { @MainActor in
            do {
                let outcome = try await nudger.nudge(request)
                report(outcome == .sent ? tr("nudge.sent", candidate.login) : tr("nudge.sentCommentOnly", candidate.login), detail: pr.title)
                refresh()
            } catch {
                report(tr("nudge.failed", candidate.login), detail: Self.reason(for: error))
            }
        }
    }

    private static func commentText(reviewer: String, tone: Int, message: String?, kind: NudgeKind) -> String {
        let marks = String(repeating: kind == .merge ? "🚀" : "👋", count: min(max(tone, 1), NudgeCodec.maxTone))
        let line = kind == .merge ? tr("nudge.merge.comment", marks, reviewer) : tr("nudge.comment", marks, reviewer)
        return message.map { "\(line): \($0)" } ?? line
    }

    private static func reason(for error: Error) -> String {
        switch error {
        case ProviderError.malformed(let text): text
        case ProviderError.rateLimited: tr("setup.error.network")
        default: error.localizedDescription
        }
    }

    private func report(_ title: String, detail: String) {
        guard mascotConfig.enabled else {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = detail
            alert.runModal()
            return
        }
        showMascotBubble(title: title, detail: detail, seconds: 6)
    }

    // MARK: Receiving

    /// Plays a nudge the first time the model reports it: the sound, a bubble, and a reminder if the viewer never looks.
    func receiveNudge(from model: AppModel) {
        guard let nudge = model.pendingNudges.last, nudge.id != lastNudgeID else { return }
        lastNudgeID = nudge.id
        if settings.settings.nudgeSoundEnabled { NudgeSound.play(tone: nudge.nudge.tone, id: settings.settings.nudgeSound) }
        let sender = nudge.nudge.author.login
        let title = nudge.nudge.kind == .merge ? tr("nudge.merge.bubble.title", sender) : tr("nudge.bubble.title", sender)
        showMascotBubble(title: title, detail: nudge.nudge.message ?? nudge.title, seconds: 12)
        scheduleReminder(for: nudge)
    }

    private func scheduleReminder(for nudge: IncomingNudge) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.reminderDelay))
            guard let self, self.model?.pendingNudges.contains(where: { $0.id == nudge.id }) == true else { return }
            await self.notifier.remind(nudge)
        }
    }
}
