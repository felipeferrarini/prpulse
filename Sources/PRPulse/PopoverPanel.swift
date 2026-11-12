import AppKit
import Combine
import PRPulseCore
import SwiftUI

enum PopoverChrome {
    static let cornerRadius: CGFloat = 12
    static let screenMargin: CGFloat = 6
    static let gapBelowStatusItem: CGFloat = 2
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
    var onContentChange: () -> Void = {}

    var body: some View {
        PopoverView(
            data: runtime.data,
            layout: Binding(get: { runtime.popoverLayout }, set: { runtime.setPopoverLayout($0) }),
            sorts: Binding(get: { runtime.listSorts }, set: { runtime.setListSorts($0) }),
            showsBorder: false,
            openToken: runtime.openCount,
            onMute: { runtime.muteRepository(of: $0) },
            entersOnAppear: true,
            onContentChange: onContentChange,
            onRefresh: { runtime.refresh() },
            onSettings: onSettings
        )
        .environment(\.nudging, runtime.nudgeActions)
        .environment(\.reviewing, runtime.reviewActions)
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
    var panel: PopoverPanel!
    /// Holds the popover only while the panel is open: a long list of rows is worth tens of megabytes.
    private var hosting: NSHostingView<AnyView>!
    /// What the panel is made of, from the back: the blurred background cut to the outline, the content and the hairline.
    var shell: NSView!
    private var backdrop: NSVisualEffectView!
    private var border: PopoverBorderView!
    private var anchorMaxX: CGFloat = 0
    private var anchorTop: CGFloat = 0
    /// Where the menu bar icon is, so the arrow points at it however the panel had to be moved to fit the screen.
    var iconMidX: CGFloat = 0
    private var isClosing = false
    private var cancellables = Set<AnyCancellable>()
    private var outsideClick: Any?
    private var lastHide = Date.distantPast
    private var followTimer: Timer?
    private var followUntil = Date.distantPast
    /// Looks now and then, while the panel is open, at what the content wants, for the changes nobody announces.
    private var sizeCheckTimer: Timer?

    init(runtime: AppRuntime) {
        self.runtime = runtime
        super.init()
        buildPanel()
        buildStatusItem()
        observeIcon()
        observeContent()
        runtime.onShortcut = { [weak self] in self?.toggleFromOutside() }
        runtime.onOpenPanel = { [weak self] in self?.showFromOutside() }
    }

    private func buildPanel() {
        hosting = NSHostingView(rootView: Self.emptyRoot)

        backdrop = NSVisualEffectView()
        backdrop.material = .popover
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.addSubview(hosting)

        border = PopoverBorderView()
        border.radius = PopoverChrome.cornerRadius

        shell = NSView()
        shell.wantsLayer = true
        shell.addSubview(backdrop)
        shell.addSubview(border)

        let root = NSView()
        root.addSubview(shell)

        panel = PopoverPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.contentView = root
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.hide() }
    }

    /// Fits the layers to the panel and cuts the background to the outline, with the arrow where the icon is.
    private func layoutShell() {
        let size = panel.frame.size
        let caretX = iconMidX - panel.frame.minX
        shell.frame = NSRect(origin: .zero, size: size)
        backdrop.frame = shell.bounds
        border.frame = shell.bounds
        hosting.frame = NSRect(x: 0, y: 0, width: size.width, height: max(0, size.height - PopoverShape.arrowHeight))
        border.caretX = caretX
        backdrop.maskImage = PopoverShape.mask(size: size, caretX: caretX, radius: PopoverChrome.cornerRadius)
        panel.invalidateShadow()
    }

    private func setPanelFrame(_ frame: NSRect, display: Bool) {
        panel.setFrame(frame, display: display)
        layoutShell()
    }

    private static let emptyRoot = AnyView(EmptyView())

    private func makeRoot() -> AnyView {
        AnyView(PopoverRoot(
            runtime: runtime,
            onSettings: { [weak self] in
                self?.hide()
                self?.runtime.openSettings()
            },
            onContentChange: { [weak self] in self?.followContentSize() }
        ))
    }

    private func buildStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(toggle)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
    }

    private func observeIcon() {
        runtime.$iconState
            .combineLatest(runtime.$pulsePhase)
            .sink { [weak self] state, phase in
                guard let button = self?.statusItem.button else { return }
                button.image = StatusIconRenderer.image(for: state, phase: phase)
                button.setAccessibilityLabel(Self.accessibilityLabel(for: state))
                button.toolTip = Self.accessibilityLabel(for: state)
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

    private static func accessibilityLabel(for state: IconState) -> String {
        switch state {
        case .upToDate: "PRPulse, \(tr("popover.upToDate"))"
        case .pending(let count), .fresh(let count): "PRPulse, \(tr("notification.title.other", count))"
        case .error: "PRPulse, \(tr("menu.status.error"))"
        }
    }

    @objc private func toggle() {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            hide()
            showMenu()
            return
        }
        togglePanel()
    }

    /// Opens or closes the panel on behalf of the mascot or the shortcut.
    func showFromOutside() {
        guard !panel.isVisible else { return }
        NSApp.activate(ignoringOtherApps: true)
        show()
    }

    func toggleFromOutside() {
        if !panel.isVisible { NSApp.activate(ignoringOtherApps: true) }
        togglePanel()
    }

    private func togglePanel() {
        if isClosing { return }
        if panel.isVisible {
            hide()
        } else if Date().timeIntervalSince(lastHide) > 0.2 {
            show()
        }
    }

    private func show() {
        guard let buttonWindow = statusItem.button?.window else { return }
        runtime.popoverOpened()
        hosting.rootView = makeRoot()
        hosting.layoutSubtreeIfNeeded()
        let size = panelSize(for: hosting.fittingSize)
        let buttonFrame = buttonWindow.frame
        anchorTop = buttonFrame.minY - PopoverChrome.gapBelowStatusItem
        iconMidX = buttonFrame.midX
        anchorMaxX = buttonFrame.midX + size.width / 2
        setPanelFrame(frame(for: size, on: buttonWindow.screen), display: false)
        prepareEntrance()
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        followContentSize()
        sizeCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyIdealSize() }
        }
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    private func hide() {
        guard panel.isVisible, !isClosing else { return }
        isClosing = true
        lastHide = Date()
        sizeCheckTimer?.invalidate()
        sizeCheckTimer = nil
        if let outsideClick { NSEvent.removeMonitor(outsideClick) }
        outsideClick = nil
        playExit { [weak self] in
            guard let self else { return }
            panel.orderOut(nil)
            hosting.rootView = Self.emptyRoot
            isClosing = false
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func applyIdealSize() {
        guard panel.isVisible else { return }
        let content = hosting.fittingSize
        guard content.width > 0, content.height > 0 else { return }
        let target = frame(for: panelSize(for: content), on: panel.screen)
        guard target != panel.frame else { return }
        setPanelFrame(target, display: true)
    }

    /// The panel is the content with room above it for the arrow.
    private func panelSize(for content: NSSize) -> NSSize {
        NSSize(width: content.width, height: content.height + PopoverShape.arrowHeight)
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
}

// MARK: - Context menu

extension PopoverController {
    private func showMenu() {
        guard let button = statusItem.button else { return }
        buildMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let status = NSMenuItem(title: statusText(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        menu.addItem(item(tr("menu.refresh"), symbol: "arrow.clockwise", key: "r", action: #selector(refreshNow)))
        menu.addItem(githubItem())
        menu.addItem(.separator())

        let notifications = item(tr("setup.general.notifications"), symbol: "bell", action: #selector(toggleNotifications))
        notifications.state = runtime.notificationsEnabled ? .on : .off
        menu.addItem(notifications)
        let mascot = item(tr("menu.mascot"), symbol: "face.smiling", action: #selector(toggleMascot))
        mascot.state = runtime.mascotEnabled ? .on : .off
        menu.addItem(mascot)
        menu.addItem(item(tr("menu.settings"), symbol: "slider.horizontal.3", key: ",", action: #selector(openSettings)))
        menu.addItem(.separator())

        menu.addItem(item(tr("menu.updates"), symbol: "arrow.down.circle", action: #selector(checkForUpdates)))
        menu.addItem(item(tr("menu.about"), symbol: "info.circle", action: #selector(openAbout)))
        menu.addItem(item(tr("menu.quit"), symbol: "power", key: "q", action: #selector(quit)))
        return menu
    }

    private func item(_ title: String, symbol: String, key: String = "", action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    private func githubItem() -> NSMenuItem {
        let parent = NSMenuItem(title: tr("menu.github"), action: nil, keyEquivalent: "")
        parent.image = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: nil)
        let orgs = runtime.organizations
        let qualifiers = orgs.map { "org:\($0)" }.joined(separator: " ")
        parent.isEnabled = !orgs.isEmpty
        let submenu = NSMenu()
        for (title, query) in [(tr("popover.review"), "review-requested:@me"), (tr("popover.mine"), "author:@me")] {
            let entry = NSMenuItem(title: title, action: #selector(openGitHub(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = "https://github.com/pulls?q=\("is:open is:pr archived:false \(qualifiers) \(query)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            submenu.addItem(entry)
        }
        parent.submenu = submenu
        return parent
    }

    private func statusText() -> String {
        let label = OrganizationLabel.text(for: runtime.organizations)
        let name = label.isEmpty ? "PRPulse" : label
        switch runtime.iconState {
        case .upToDate: return "\(name): \(tr("popover.empty.title"))"
        case .pending(let count), .fresh(let count): return "\(name): \(tr("notification.title.other", count))"
        case .error: return "\(name): \(tr("menu.status.error"))"
        }
    }

    @objc private func refreshNow() { runtime.refresh() }

    @objc private func toggleNotifications() { runtime.toggleNotifications() }

    @objc private func toggleMascot() { runtime.setMascotEnabled(!runtime.mascotEnabled) }

    @objc private func openSettings() { runtime.openSettings() }

    @objc private func checkForUpdates() { runtime.checkForUpdates() }

    @objc private func openAbout() {
        if let url = URL(string: "https://github.com/felipeferrarini/prpulse") { NSWorkspace.shared.open(url) }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openGitHub(_ sender: NSMenuItem) {
        if let link = sender.representedObject as? String, let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }
}

// MARK: - Entrance and exit

extension PopoverController {
    /// The popover comes out of the icon: it grows from a point under the arrow, with a little give, while it fades in.
    func prepareEntrance() {
        guard let layer = shell.layer, !Self.reducesMotion else { return }
        layer.removeAllAnimations()
        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = NSValue(caTransform3D: scaled(0.55, in: layer))
        spring.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        spring.mass = 1
        spring.stiffness = 360
        spring.damping = 25
        spring.duration = spring.settlingDuration
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.14
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(spring, forKey: "enter")
        layer.add(fade, forKey: "fadeIn")
        DispatchQueue.main.asyncAfter(deadline: .now() + spring.duration) { [weak self] in self?.panel.invalidateShadow() }
    }

    /// The way back is quicker than the way out: a small shrink toward the icon and a fade.
    func playExit(completion: @escaping () -> Void) {
        guard let layer = shell.layer, !Self.reducesMotion else {
            completion()
            return
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            layer.removeAllAnimations()
            layer.opacity = 1
            layer.transform = CATransform3DIdentity
            completion()
        }
        layer.opacity = 0
        layer.transform = scaled(0.9, in: layer)
        let shrink = CABasicAnimation(keyPath: "transform")
        shrink.fromValue = NSValue(caTransform3D: CATransform3DIdentity)
        shrink.toValue = NSValue(caTransform3D: scaled(0.9, in: layer))
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        for animation in [shrink, fade] {
            animation.duration = 0.12
            animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
            layer.add(animation, forKey: animation.keyPath)
        }
        CATransaction.commit()
    }

    private static var reducesMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// A scale about the tip of the arrow, which is where the popover comes from: the layer scales about its centre, so the
    /// shift puts the tip back in place.
    private func scaled(_ scale: CGFloat, in layer: CALayer) -> CATransform3D {
        let size = layer.bounds.size
        let tip = CGPoint(x: min(max(iconMidX - panel.frame.minX, 0), size.width), y: size.height)
        let shift = CATransform3DMakeTranslation((1 - scale) * (tip.x - size.width / 2), (1 - scale) * (tip.y - size.height / 2), 0)
        return CATransform3DScale(shift, scale, scale, 1)
    }
}
