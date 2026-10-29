import AppKit
import Combine
import PRPulseCore
import SwiftUI

enum PopoverChrome {
    static let cornerRadius: CGFloat = 12
    static let screenMargin: CGFloat = 6
    static let gapBelowStatusItem: CGFloat = 4
}

/// The window of the menu bar popover. It can take key focus without activating the app.
final class PopoverPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

struct PopoverRoot: View {
    @ObservedObject var runtime: AppRuntime
    let onSettings: () -> Void

    var body: some View {
        PopoverView(
            data: runtime.data,
            layout: Binding(get: { runtime.popoverLayout }, set: { runtime.setPopoverLayout($0) }),
            openToken: runtime.openCount,
            onRefresh: { runtime.refresh() },
            onSettings: onSettings
        )
    }
}

/// Owns the status item and the panel that opens under it.
///
/// The panel keeps its top right corner fixed while its size changes, so switching between the single and the
/// side by side layout never makes it jump, and it draws its own rounded, blurred background and shadow.
@MainActor
final class PopoverController: NSObject, NSWindowDelegate {
    private let runtime: AppRuntime
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var panel: PopoverPanel!
    private var hosting: NSHostingView<PopoverRoot>!
    private var anchorMaxX: CGFloat = 0
    private var anchorTop: CGFloat = 0
    private var cancellables = Set<AnyCancellable>()
    private var outsideClick: Any?
    private var lastHide = Date.distantPast
    private var followTimer: Timer?
    private var followUntil = Date.distantPast

    init(runtime: AppRuntime) {
        self.runtime = runtime
        super.init()
        buildPanel()
        buildStatusItem()
        observeIcon()
        observeContent()
    }

    private func buildPanel() {
        hosting = NSHostingView(rootView: PopoverRoot(
            runtime: runtime,
            onSettings: { [weak self] in
                self?.hide()
                self?.runtime.openSettings()
            }
        ))

        let backdrop = NSVisualEffectView()
        backdrop.material = .popover
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.maskImage = Self.roundedMask(radius: PopoverChrome.cornerRadius)
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = backdrop.bounds
        backdrop.addSubview(hosting)

        panel = PopoverPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.contentView = backdrop
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.hide() }
    }

    private func buildStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(toggle)
        button.sendAction(on: [.leftMouseUp])
        button.imagePosition = .imageOnly
    }

    private func observeIcon() {
        runtime.$iconState
            .combineLatest(runtime.$pulsePhase)
            .sink { [weak self] state, phase in
                self?.statusItem.button?.image = StatusIconRenderer.image(for: state, phase: phase)
            }
            .store(in: &cancellables)
    }

    /// SwiftUI animates layout and data changes, so the panel follows the view's ideal size for a moment after each one.
    private func observeContent() {
        Publishers.Merge(
            runtime.$popoverLayout.dropFirst().map { _ in () },
            runtime.$data.dropFirst().map { _ in () }
        )
        .sink { [weak self] in self?.followContentSize() }
        .store(in: &cancellables)
    }

    private func followContentSize() {
        guard panel.isVisible else { return }
        followUntil = Date().addingTimeInterval(1)
        guard followTimer == nil else { return }
        followTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.followTick() }
        }
    }

    private func followTick() {
        applyIdealSize()
        guard Date() > followUntil || !panel.isVisible else { return }
        followTimer?.invalidate()
        followTimer = nil
    }

    @objc private func toggle() {
        if panel.isVisible {
            hide()
        } else if Date().timeIntervalSince(lastHide) > 0.2 {
            show()
        }
    }

    private func show() {
        guard let buttonWindow = statusItem.button?.window else { return }
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let buttonFrame = buttonWindow.frame
        anchorTop = buttonFrame.minY - PopoverChrome.gapBelowStatusItem
        anchorMaxX = buttonFrame.midX + size.width / 2
        panel.setFrame(frame(for: size, on: buttonWindow.screen), display: false)
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        runtime.popoverOpened()
        followContentSize()
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    private func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        lastHide = Date()
        if let outsideClick { NSEvent.removeMonitor(outsideClick) }
        outsideClick = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func applyIdealSize() {
        guard panel.isVisible else { return }
        let size = hosting.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        let target = frame(for: size, on: panel.screen)
        guard target != panel.frame else { return }
        panel.setFrame(target, display: true)
        panel.invalidateShadow()
    }

    /// A frame of the given size hanging from the anchored top right corner, kept inside the screen.
    private func frame(for size: NSSize, on screen: NSScreen?) -> NSRect {
        var x = anchorMaxX - size.width
        if let visible = (screen ?? NSScreen.main)?.visibleFrame {
            let margin = PopoverChrome.screenMargin
            x = max(visible.minX + margin, min(x, visible.maxX - size.width - margin))
        }
        return NSRect(x: x, y: anchorTop - size.height, width: size.width, height: size.height)
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
