import Carbon.HIToolbox
import Foundation

/// A system wide shortcut (option command P). Carbon's hot key API needs no accessibility permission.
@MainActor
final class GlobalShortcut {
    static let display = "⌥⌘P"

    private static let signature = OSType(0x5052_5055) // "PRPU"
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let onTrigger: () -> Void

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
    }

    var isRegistered: Bool { hotKey != nil }

    /// Returns whether the shortcut is active afterwards; another app may already own the combination.
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        enabled ? register() : unregister()
        return isRegistered
    }

    private func register() {
        guard hotKey == nil else { return }
        installHandler()
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_P), UInt32(cmdKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
        hotKey = status == noErr ? ref : nil
    }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { shortcut.onTrigger() } }
            return noErr
        }, 1, &spec, context, &handler)
    }
}
