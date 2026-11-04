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

/// A sound the viewer can pick: one of macOS's, or a file in the sounds folder.
struct NudgeSoundOption: Identifiable, Equatable {
    let choice: NudgeSoundChoice
    let url: URL

    var id: String { choice.id }
    var name: String { choice.name }
}

/// Finds the system sounds and the ones the viewer dropped into the support folder.
enum NudgeSoundLibrary {
    private static let systemFolder = URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true)
    private static let extensions: Set<String> = ["wav", "caf", "aiff", "aif", "m4a", "mp3"]

    static var userFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PRPulse/Sounds", isDirectory: true)
    }

    static func system() -> [NudgeSoundOption] {
        files(in: systemFolder).map { NudgeSoundOption(choice: .system($0.deletingPathExtension().lastPathComponent), url: $0) }
    }

    /// Only files macOS can play: one it cannot open would leave a nudge silent.
    static func user() -> [NudgeSoundOption] {
        files(in: userFolder)
            .filter { NSSound(contentsOf: $0, byReference: true) != nil }
            .map { NudgeSoundOption(choice: .user($0.lastPathComponent), url: $0) }
    }

    /// The sound for this id, or the default one when the file is gone or broken.
    static func sound(id: String) -> NSSound? {
        let choice = NudgeSoundChoice(id: id) ?? .fallback
        if let url = url(for: choice), let sound = NSSound(contentsOf: url, byReference: false) { return sound }
        return NSSound(named: NudgeSoundChoice.fallback.name)
    }

    static func openFolder() {
        try? FileManager.default.createDirectory(at: userFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(userFolder)
    }

    private static func url(for choice: NudgeSoundChoice) -> URL? {
        switch choice {
        case let .system(name): systemFolder.appendingPathComponent(name + ".aiff")
        case let .user(file): userFolder.appendingPathComponent(file)
        }
    }

    private static func files(in folder: URL) -> [URL] {
        let found = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return found
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }
}

/// The sound of a nudge. A louder nudge plays it more times, and a long file is cut short.
@MainActor
enum NudgeSound {
    private static let gap: TimeInterval = 0.25
    private static var playing: Task<Void, Never>?
    private static var current: NSSound?

    static func play(tone: Int, id: String) {
        stop()
        let times = min(max(tone, 1), NudgeCodec.maxTone)
        playing = Task { @MainActor in
            for _ in 0 ..< times {
                guard !Task.isCancelled, let sound = NudgeSoundLibrary.sound(id: id) else { return }
                current = sound
                sound.play()
                try? await Task.sleep(for: .seconds(min(sound.duration, NudgeSoundChoice.maxPlayback)))
                sound.stop()
                try? await Task.sleep(for: .seconds(gap))
            }
        }
    }

    static func stop() {
        playing?.cancel()
        current?.stop()
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
