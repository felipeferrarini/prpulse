import AppKit
import PRPulseCore
import SwiftUI

/// What a row needs to nudge a reviewer, handed down once instead of through every view in between.
struct NudgeActions {
    var candidates: (PullRequestSnapshot) -> [NudgeCandidate] = { _ in [] }
    var send: (PullRequestSnapshot, NudgeCandidate, _ withMessage: Bool) -> Void = { _, _, _ in }
    /// The viewer opened a pull request: a nudge about it has done its job.
    var opened: (URL) -> Void = { _ in }
}

private struct NudgeActionsKey: EnvironmentKey {
    static let defaultValue = NudgeActions()
}

extension EnvironmentValues {
    var nudging: NudgeActions {
        get { self[NudgeActionsKey.self] }
        set { self[NudgeActionsKey.self] = newValue }
    }
}

enum NudgePause {
    /// Nine in the morning of the next day, when a day of quiet should end.
    static func tomorrowMorning(from date: Date = Date(), calendar: Calendar = .current) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date.addingTimeInterval(86_400)
        return calendar.date(byAdding: .hour, value: 9, to: tomorrow) ?? tomorrow
    }
}

/// The sound of a nudge: the viewer's own recording when the app has one, a system sound until then. A louder nudge plays it
/// more times.
@MainActor
enum NudgeSound {
    private static let extensions = ["wav", "caf", "aiff", "m4a", "mp3"]
    private static let gap: TimeInterval = 0.25
    private static var playing: Task<Void, Never>?

    static func play(tone: Int) {
        playing?.cancel()
        let times = min(max(tone, 1), NudgeCodec.maxTone)
        playing = Task { @MainActor in
            for _ in 0 ..< times {
                guard !Task.isCancelled, let sound = make() else { return }
                sound.play()
                try? await Task.sleep(for: .seconds(sound.duration + gap))
            }
        }
    }

    private static func make() -> NSSound? {
        for ext in extensions {
            if let url = Bundle.module.url(forResource: "nudge", withExtension: ext), let sound = NSSound(contentsOf: url, byReference: false) {
                return sound
            }
        }
        return NSSound(named: "Sosumi")
    }
}

/// Asks for the line that goes with a nudge.
@MainActor
enum NudgePrompt {
    /// Nil when the author gave up; an empty string when they sent it with no text.
    static func ask(reviewer: String, title: String) -> String? {
        let alert = NSAlert()
        alert.messageText = tr("nudge.prompt.title", reviewer)
        alert.informativeText = tr("nudge.prompt.detail", title)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = tr("nudge.prompt.placeholder", NudgeCodec.maxMessageLength)
        alert.accessoryView = field
        alert.addButton(withTitle: tr("nudge.prompt.send"))
        alert.addButton(withTitle: tr("nudge.prompt.cancel"))
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }
}
