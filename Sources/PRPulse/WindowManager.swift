import AppKit
import SwiftUI

enum WindowChrome {
    case standard
    /// No title bar and no system buttons: the content draws its own edges and close button.
    case borderless
}

private final class BorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class WindowManager {
    private var windows: [String: NSWindow] = [:]
    private var observers: [String: NSObjectProtocol] = [:]

    func show<Content: View>(id: String, title: String, chrome: WindowChrome = .standard, @ViewBuilder content: () -> Content) {
        if let existing = windows[id] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = makeWindow(chrome)
        window.title = title
        let hosting = NSHostingView(rootView: content())
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        window.isReleasedWhenClosed = false
        window.center()
        windows[id] = window
        observers[id] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.forget(id) }
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close(id: String) {
        windows[id]?.close()
    }

    private func makeWindow(_ chrome: WindowChrome) -> NSWindow {
        switch chrome {
        case .standard:
            return NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        case .borderless:
            let window = BorderlessWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            return window
        }
    }

    private func forget(_ id: String) {
        windows[id] = nil
        if let observer = observers.removeValue(forKey: id) { NotificationCenter.default.removeObserver(observer) }
    }
}
