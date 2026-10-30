import AppKit
import PRPulseCore
import SwiftUI

/// Plays a mood of a mascot pack, one sprite pixel to `scale` points, with hard pixel edges.
/// A core animation layer swaps the frames on a timer, which costs far less than redrawing a SwiftUI view.
struct MascotSprite: NSViewRepresentable {
    let pack: MascotPack
    let mood: MascotMood
    let scale: CGFloat
    var isAnimating = true

    func makeNSView(context: Context) -> SpriteView {
        SpriteView()
    }

    func updateNSView(_ view: SpriteView, context: Context) {
        view.fps = pack.fps
        view.isAnimating = isAnimating
        view.set(frames: pack.frames(for: mood))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SpriteView, context: Context) -> CGSize? {
        CGSize(width: pack.frameSize.width * scale, height: pack.frameSize.height * scale)
    }

    final class SpriteView: NSView {
        var fps = 8.0
        var isAnimating = true { didSet { if isAnimating != oldValue { restart() } } }
        private var frames: [CGImage] = []
        private var index = 0
        private var timer: Timer?

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.magnificationFilter = .nearest
            layer?.minificationFilter = .nearest
            layer?.contentsGravity = .resizeAspect
        }

        required init?(coder: NSCoder) { nil }

        deinit { timer?.invalidate() }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func set(frames next: [CGImage]) {
            let unchanged = next.count == frames.count && (next.first as AnyObject?) === (frames.first as AnyObject?)
            guard !unchanged else { return }
            frames = next
            index = 0
            show()
            restart()
        }

        private func restart() {
            timer?.invalidate()
            timer = nil
            guard isAnimating, frames.count > 1 else { return show() }
            let timer = Timer(timeInterval: 1 / fps, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.advance() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }

        private func advance() {
            index = (index + 1) % frames.count
            show()
        }

        private func show() {
            layer?.contents = frames.indices.contains(index) ? frames[index] : nil
        }
    }
}

/// The count that sits on a mascot's shoulder, like the one on the menu bar icon.
struct MascotBadge: View {
    let count: Int

    var body: some View {
        Text(StatusIconRenderer.label(count))
            .font(.system(size: 11, weight: .heavy).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 20)
            .background(Color(nsColor: NSColor(hex: 0xFF3B30)), in: Capsule(style: .circular))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
    }
}

/// What the mascot says: the same words as the notification.
struct MascotBubbleView: View {
    let title: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12.5, weight: .semibold))
            if let detail { Text(detail).font(.system(size: 11.5)).foregroundStyle(Color(nsColor: NSColor(hex: 0x4A5070))).lineLimit(2) }
        }
        .foregroundStyle(Color(nsColor: NSColor(hex: 0x14172A)))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: 230, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: NSColor(hex: 0xF4F5FA)), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        .padding(14)
    }
}
