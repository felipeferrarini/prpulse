import AppKit
import PRPulseCore
import SwiftUI

/// Renders the pictures used in the README: the real views with fake data, floating over a soft backdrop.
/// Run it with `make screenshots`; it needs `PRPULSE_SNAPSHOT_DIR` and `PRPULSE_SNAPSHOT_STYLE=readme`.
@MainActor
enum ReadmeShots {
    private static let settle: TimeInterval = 1.6

    static func writeAll(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = DemoMode.pending.viewData
        for scheme in [ColorScheme.dark, .light] {
            let tag = scheme == .dark ? "dark" : "light"
            render(HeroScene(scheme: scheme, data: data), named: "hero-\(tag)", scheme: scheme, to: directory)
            render(floating(popover(data, scheme, layout: .single), radius: 12, scheme: scheme), named: "popover-\(tag)", scheme: scheme, to: directory)
            render(floating(popover(data, scheme, layout: .split), radius: 12, scheme: scheme), named: "popover-split-\(tag)", scheme: scheme, to: directory)
            render(floating(DemoSnapshot.wizard(.exceptions), radius: 16, scheme: scheme), named: "wizard-\(tag)", scheme: scheme, to: directory)
            render(floating(DemoSnapshot.settings(.organization, login: "octocat"), radius: 16, scheme: scheme), named: "settings-\(tag)", scheme: scheme, to: directory)
            render(StatesStrip(scheme: scheme), named: "menubar-\(tag)", scheme: scheme, to: directory)
        }
    }

    private static func popover(_ data: ViewData, _ scheme: ColorScheme, layout: PopoverLayout) -> some View {
        PopoverView(data: data, layout: .constant(layout), onRefresh: {}, onSettings: {})
            .background(Color(nsColor: scheme == .dark ? NSColor(hex: 0x24252B) : NSColor(hex: 0xF5F5F8)))
    }

    private static func floating<Content: View>(_ view: Content, radius: CGFloat, scheme: ColorScheme) -> some View {
        view
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
            .shadow(color: .black.opacity(scheme == .dark ? 0.55 : 0.26), radius: 28, y: 16)
            .padding(56)
            .environment(\.colorScheme, scheme)
    }

    private static func render(_ view: some View, named name: String, scheme: ColorScheme, to directory: URL) {
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme).environment(\.controlActiveState, .key))
        host.appearance = appearance
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = appearance
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(settle))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: directory.appendingPathComponent("\(name).png"))
        window.orderOut(nil)
    }
}

// MARK: - Hero

private struct HeroScene: View {
    let scheme: ColorScheme
    let data: ViewData

    var body: some View {
        ZStack(alignment: .topTrailing) {
            wallpaper
            VStack(spacing: 0) {
                MenuBarMock(scheme: scheme, count: data.summary?.total ?? 0)
                Spacer()
            }
            PopoverView(data: data, layout: .constant(.split), onRefresh: {}, onSettings: {})
                .background(Color(nsColor: scheme == .dark ? NSColor(hex: 0x24252B) : NSColor(hex: 0xF5F5F8)))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
                .shadow(color: .black.opacity(scheme == .dark ? 0.6 : 0.3), radius: 34, y: 20)
                .padding(.top, 42)
                .padding(.trailing, 40)
        }
        .frame(width: 1020, height: 660, alignment: .topTrailing)
        .environment(\.colorScheme, scheme)
    }

    private var wallpaper: some View {
        let colors: [Color] = scheme == .dark
            ? [Color(nsColor: NSColor(hex: 0x0A0E2A)), Color(nsColor: NSColor(hex: 0x1D1456)), Color(nsColor: NSColor(hex: 0x3E1F6E))]
            : [Color(nsColor: NSColor(hex: 0xCFE0FF)), Color(nsColor: NSColor(hex: 0xE6D8F7)), Color(nsColor: NSColor(hex: 0xFFE3CC))]
        return ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(nsColor: NSColor(hex: 0x2F55FF)).opacity(scheme == .dark ? 0.35 : 0.22), .clear], center: .topLeading, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Color(nsColor: NSColor(hex: 0xFF8A3D)).opacity(scheme == .dark ? 0.28 : 0.3), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 560)
        }
    }
}

private struct MenuBarMock: View {
    let scheme: ColorScheme
    let count: Int

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "applelogo")
            Text("Finder").fontWeight(.semibold)
            Text("File")
            Text("Edit")
            Text("View")
            Text("Window")
            Text("Help")
            Spacer()
            Image(systemName: "magnifyingglass")
            Image(systemName: "wifi")
            Image(systemName: "battery.75")
            Image(nsImage: StatusIconRenderer.image(for: .pending(count), phase: 0))
            Text("Thu Oct 29  2:32 PM")
        }
        .font(.system(size: 13))
        .foregroundStyle(scheme == .dark ? Color.white.opacity(0.88) : Color.black.opacity(0.82))
        .padding(.horizontal, 16)
        .frame(height: 30)
        .background(scheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.45))
    }
}

// MARK: - Icon states

private struct StatesStrip: View {
    let scheme: ColorScheme

    private let states: [(IconState, Double, String)] = [
        (.upToDate, 0, "Up to date"), (.pending(4), 0, "Needs you"), (.fresh(5), 0.3, "New item"), (.error, 0, "Can't update"),
    ]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, entry in
                let image = StatusIconRenderer.image(for: entry.0, phase: entry.1)
                VStack(spacing: 10) {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: image.size.width * 2.6, height: image.size.height * 2.6)
                        .foregroundStyle(scheme == .dark ? Color.white : Color.black)
                        .frame(width: 168, height: 78)
                        .background(scheme == .dark ? Color(nsColor: NSColor(hex: 0x2A2B33)) : Color(nsColor: NSColor(hex: 0xE9E9EE)), in: RoundedRectangle(cornerRadius: 14))
                    Text(entry.2).font(.system(size: 13, weight: .medium)).foregroundStyle(scheme == .dark ? Color.white.opacity(0.75) : Color.black.opacity(0.65))
                }
            }
        }
        .padding(24)
        .environment(\.colorScheme, scheme)
    }
}
