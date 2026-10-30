import AppKit
import Combine
import PRPulseCore
import SwiftUI

@MainActor
final class MascotModel: ObservableObject {
    @Published var pack: MascotPack?
    @Published var mood = MascotMood.calm
    @Published var count = 0
    @Published var scale = 4
}

private struct MascotRoot: View {
    @ObservedObject var model: MascotModel

    private var showsBadge: Bool {
        model.count > 0 && [.alert, .joy, .worried].contains(model.mood)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let pack = model.pack {
                MascotSprite(pack: pack, mood: model.mood, scale: CGFloat(model.scale))
            }
            if showsBadge { MascotBadge(count: model.count).transition(.scale.combined(with: .opacity)) }
        }
        .animation(.spring(duration: 0.3), value: showsBadge)
        .padding(MascotController.margin)
    }
}

/// Takes the mouse for the whole window: a click opens the panel, a drag moves the mascot, a right click opens its menu.
private final class MascotHostView: NSView {
    var onClick: () -> Void = {}
    var onMove: () -> Void = {}
    var onMoved: () -> Void = {}
    var makeMenu: () -> NSMenu? = { nil }

    private var drag: (mouse: NSPoint, origin: NSPoint)?
    private var didMove = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { self }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { return rightMouseDown(with: event) }
        guard let window else { return }
        drag = (NSEvent.mouseLocation, window.frame.origin)
        didMove = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag, let window else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - drag.mouse.x, dy = mouse.y - drag.mouse.y
        if !didMove, hypot(dx, dy) < 4 { return }
        didMove = true
        window.setFrameOrigin(NSPoint(x: drag.origin.x + dx, y: drag.origin.y + dy))
        onMove()
    }

    override func mouseUp(with event: NSEvent) {
        defer { drag = nil }
        guard drag != nil else { return }
        if didMove { onMoved() } else { onClick() }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = makeMenu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

private final class MascotPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A small friend that lives in a corner of the screen, follows the status of the pull requests and can be dragged.
@MainActor
final class MascotController: NSObject {
    static let margin: CGFloat = 10
    private static let defaultInset: CGFloat = 14
    private static let bubbleLifetime: TimeInterval = 0.2

    private let runtime: AppRuntime
    private let model = MascotModel()
    private let onOpen: () -> Void
    private var panel: MascotPanel?
    private var hosting: NSHostingView<MascotRoot>?
    private var bubblePanel: NSPanel?
    private var shownBubble: UUID?
    private var loadedPackID: String?
    private var cancellables = Set<AnyCancellable>()

    init(runtime: AppRuntime, onOpen: @escaping () -> Void) {
        self.runtime = runtime
        self.onOpen = onOpen
        super.init()
        Publishers.CombineLatest3(runtime.$mascotConfig, runtime.$mascotState, runtime.$mascotBubble)
            .sink { [weak self] config, state, bubble in self?.apply(config, state, bubble) }
            .store(in: &cancellables)
        runtime.$mascotPlacementToken.dropFirst()
            .sink { [weak self] _ in self?.place() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.place() }
            .store(in: &cancellables)
    }

    // MARK: Following the app

    private func apply(_ config: MascotConfig, _ state: MascotState, _ bubble: MascotBubble?) {
        guard config.enabled else { return tearDown() }
        if loadedPackID != config.packID {
            model.pack = MascotLibrary.load(id: config.packID)
            loadedPackID = config.packID
        }
        model.mood = state.mood
        model.count = state.count
        model.scale = config.scale

        let isNew = panel == nil
        let panel = ensurePanel()
        let size = windowSize()
        if isNew {
            panel.setFrame(targetFrame(size: size), display: false)
        } else if panel.frame.size != size {
            let old = panel.frame
            panel.setFrame(NSRect(x: old.maxX - size.width, y: old.minY, width: size.width, height: size.height), display: true)
            persistPosition()
        }
        panel.orderFrontRegardless()
        showBubble(bubble)
    }

    private func tearDown() {
        hideBubble(animated: false)
        panel?.orderOut(nil)
        panel = nil
        hosting = nil
        model.pack = nil
        loadedPackID = nil
    }

    // MARK: Window

    private func ensurePanel() -> MascotPanel {
        if let panel { return panel }
        let size = windowSize()
        let panel = MascotPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let host = MascotHostView(frame: NSRect(origin: .zero, size: size))
        host.onClick = { [weak self] in self?.onOpen() }
        host.onMove = { [weak self] in self?.placeBubble() }
        host.onMoved = { [weak self] in self?.persistPosition() }
        host.makeMenu = { [weak self] in self?.makeMenu() }
        let hosting = NSHostingView(rootView: MascotRoot(model: model))
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.frame = host.bounds
        hosting.autoresizingMask = [.width, .height]
        host.addSubview(hosting)
        panel.contentView = host
        self.panel = panel
        self.hosting = hosting
        return panel
    }

    private func windowSize() -> NSSize {
        let frame = model.pack?.frameSize ?? CGSize(width: 28, height: 28)
        let scale = CGFloat(model.scale)
        return NSSize(width: frame.width * scale + Self.margin * 2, height: frame.height * scale + Self.margin * 2)
    }

    // MARK: Position

    private static func id(of screen: NSScreen) -> String {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? "main"
    }

    private func screen(forID id: String?) -> NSScreen? {
        guard let id else { return nil }
        return NSScreen.screens.first { Self.id(of: $0) == id }
    }

    private func targetFrame(size: NSSize) -> NSRect {
        let anchor = runtime.mascotAnchor
        let target = screen(forID: anchor?.screen) ?? NSScreen.main ?? NSScreen.screens.first
        let visible = target?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let right = anchor?.right ?? Self.defaultInset, bottom = anchor?.bottom ?? Self.defaultInset
        let origin = NSPoint(x: visible.maxX - right - size.width, y: visible.minY + bottom)
        return Self.clamp(NSRect(origin: origin, size: size), to: visible)
    }

    private static func clamp(_ frame: NSRect, to visible: NSRect) -> NSRect {
        var result = frame
        result.origin.x = min(max(frame.minX, visible.minX), max(visible.maxX - frame.width, visible.minX))
        result.origin.y = min(max(frame.minY, visible.minY), max(visible.maxY - frame.height, visible.minY))
        return result
    }

    /// Puts the mascot back where the saved position says, or in the bottom right corner.
    private func place() {
        guard let panel else { return }
        panel.setFrame(targetFrame(size: windowSize()), display: true)
        placeBubble()
    }

    private func persistPosition() {
        guard let panel else { return }
        let frame = panel.frame
        let center = NSPoint(x: frame.midX, y: frame.midY)
        guard let target = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main else { return }
        let visible = target.visibleFrame
        runtime.setMascotAnchor(MascotAnchor(screen: Self.id(of: target), right: visible.maxX - frame.maxX, bottom: frame.minY - visible.minY))
        placeBubble()
    }

    // MARK: Bubble

    private func showBubble(_ bubble: MascotBubble?) {
        guard let bubble else { return hideBubble(animated: true) }
        guard shownBubble != bubble.id else { return }
        shownBubble = bubble.id
        let hosting = NSHostingView(rootView: MascotBubbleView(title: bubble.title, detail: bubble.detail))
        hosting.sizingOptions = [.intrinsicContentSize]
        let size = hosting.fittingSize
        let window = bubblePanel ?? makeBubblePanel()
        window.contentView = hosting
        window.setContentSize(size)
        placeBubble()
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2; window.animator().alphaValue = 1 }
    }

    private func hideBubble(animated: Bool) {
        shownBubble = nil
        guard let window = bubblePanel, window.isVisible else { return }
        guard animated else { return window.orderOut(nil) }
        NSAnimationContext.runAnimationGroup({ $0.duration = Self.bubbleLifetime; window.animator().alphaValue = 0 }, completionHandler: {
            Task { @MainActor [weak self] in
                guard self?.shownBubble == nil else { return }
                window.orderOut(nil)
            }
        })
    }

    private func makeBubblePanel() -> NSPanel {
        let window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        bubblePanel = window
        return window
    }

    /// Above the mascot, lined up with its right edge; below it when there is no room on top.
    private func placeBubble() {
        guard let bubble = bubblePanel, bubble.isVisible || shownBubble != nil, let panel else { return }
        let mascot = panel.frame, size = bubble.frame.size
        let visible = (NSScreen.screens.first { $0.frame.contains(NSPoint(x: mascot.midX, y: mascot.midY)) } ?? NSScreen.main)?.visibleFrame ?? mascot
        var origin = NSPoint(x: mascot.maxX - size.width + 4, y: mascot.maxY - 18)
        if origin.y + size.height > visible.maxY { origin.y = mascot.minY - size.height + 18 }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        bubble.setFrameOrigin(origin)
    }

    // MARK: Menu

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item(tr("mascot.menu.open"), action: #selector(openPanel)))
        menu.addItem(.separator())

        let characters = NSMenuItem(title: tr("mascot.menu.character"), action: nil, keyEquivalent: "")
        let list = NSMenu()
        for info in MascotLibrary.available() {
            let entry = item(info.name, action: #selector(pickCharacter(_:)))
            entry.representedObject = info.id
            entry.state = info.id == runtime.mascotConfig.packID ? .on : .off
            list.addItem(entry)
        }
        characters.submenu = list
        menu.addItem(characters)

        let sizes = NSMenuItem(title: tr("mascot.menu.size"), action: nil, keyEquivalent: "")
        let sizeList = NSMenu()
        for (title, scale) in [(tr("mascot.size.s"), 3), (tr("mascot.size.m"), 4), (tr("mascot.size.l"), 6)] {
            let entry = item(title, action: #selector(pickSize(_:)))
            entry.tag = scale
            entry.state = scale == runtime.mascotConfig.scale ? .on : .off
            sizeList.addItem(entry)
        }
        sizes.submenu = sizeList
        menu.addItem(sizes)
        menu.addItem(item(tr("mascot.menu.reset"), action: #selector(resetPosition)))
        menu.addItem(.separator())
        menu.addItem(item(tr("mascot.menu.hide"), action: #selector(hide)))
        menu.addItem(item(tr("menu.settings"), action: #selector(openSettings)))
        return menu
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openPanel() { onOpen() }
    @objc private func pickCharacter(_ sender: NSMenuItem) { (sender.representedObject as? String).map(runtime.setMascotPack) }
    @objc private func pickSize(_ sender: NSMenuItem) { runtime.setMascotScale(sender.tag) }
    @objc private func resetPosition() { runtime.resetMascotPosition() }
    @objc private func hide() { runtime.setMascotEnabled(false) }
    @objc private func openSettings() { runtime.openSettings() }
}
