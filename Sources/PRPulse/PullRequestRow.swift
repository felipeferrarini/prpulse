import PRPulseCore
import SwiftUI

struct PullRequestRow: View {
    let model: RowModel
    let isDimmed: Bool
    let entranceIndex: Int
    let entered: Bool
    var onMute: (() -> Void)?

    @LocalState private var isHovering = false
    @LocalState private var copied = false

    private static let barWidth: CGFloat = 46

    var body: some View {
        let waiting = Waiting(since: model.pr.createdAt, now: Date())
        return HStack(spacing: 0) {
            Button { NSWorkspace.shared.open(model.pr.url) } label: { openLabel(waiting) }
                .buttonStyle(.plain)
            actionsMenu.padding(.trailing, 10)
        }
        .background(isHovering ? Color.primary.opacity(0.07) : .clear)
        .onHover { isHovering = $0 }
        .contextMenu { menu }
        .help(model.pr.title)
        .accessibilityLabel("\(model.pr.title), \(model.subtitle), \(waiting.text)")
        .opacity(entered ? (isDimmed ? 0.28 : 1) : 0)
        .offset(y: entered ? 0 : 8)
        .animation(.easeInOut(duration: 0.25), value: isDimmed)
        .animation(.easeOut(duration: 0.42).delay(0.11 + Double(min(entranceIndex, 14)) * 0.028), value: entered)
    }

    private func openLabel(_ waiting: Waiting) -> some View {
        HStack(spacing: 11) {
            lead.frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.pr.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(model.subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Group {
                if model.kind == .waiting, isHovering || copied {
                    copyButton
                } else {
                    HStack(spacing: 4) { ForEach(model.chips) { chip($0) } }
                }
            }
            .fixedSize()
            .layoutPriority(1)
            waitIndicator(waiting).frame(width: 62, alignment: .trailing)
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var menu: some View {
        Button { NSWorkspace.shared.open(model.pr.url) } label: { Label(tr("row.open"), systemImage: "arrow.up.right.square") }
        Button(action: copyLink) { Label(tr("row.copyLink"), systemImage: "link") }
        if model.canMute, let onMute {
            Divider()
            Button(action: onMute) { Label(tr("row.mute", model.pr.ref.repo), systemImage: "eye.slash") }
        }
    }

    private var actionsMenu: some View {
        Menu { menu } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isHovering ? Color.primary : Color.secondary.opacity(0.6))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(tr("row.actions"))
    }

    private var copyButton: some View {
        Button(action: copyLink) {
            Label(copied ? tr("row.copied") : tr("row.copyLink"), systemImage: copied ? "checkmark" : "link")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(copied ? Palette.merge : Palette.review)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background((copied ? Palette.merge : Palette.review).opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func copyLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.pr.url.absoluteString, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
    }

    @ViewBuilder private var lead: some View {
        switch model.lead {
        case .avatar(let login):
            Text(login.prefix(1).uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.black.opacity(0.75))
                .frame(width: 26, height: 26)
                .background(Self.avatarColor(login), in: Circle())
                .accessibilityHidden(true)
        case .lane(let lane):
            Image(systemName: lane.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(lane.tone)
                .accessibilityHidden(true)
        case .waiting:
            Image(systemName: "hourglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private func chip(_ chip: RowModel.Chip) -> some View {
        let tone = chip.tone
        return Text(chip.text)
            .font(.system(size: 11.5, weight: tone == nil ? .medium : .semibold))
            .foregroundStyle(tone ?? .secondary)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background((tone ?? .primary).opacity(tone == nil ? 0.08 : 0.14), in: RoundedRectangle(cornerRadius: 6))
    }

    private func waitIndicator(_ waiting: Waiting) -> some View {
        let color = Palette.tone(waiting.tone)
        return VStack(alignment: .trailing, spacing: 4) {
            Text(waiting.text)
                .font(.system(size: 11.5, weight: waiting.tone == .hot ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(color ?? .secondary)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(color ?? Color.secondary.opacity(0.7))
                    .frame(width: Self.barWidth * waiting.fraction)
                    .scaleEffect(x: entered ? 1 : 0, anchor: .leading)
            }
            .frame(width: Self.barWidth, height: 4)
        }
        .accessibilityHidden(true)
    }

    private static let avatarColors: [Color] = [0x8AA4FF, 0xFF9A62, 0x52CF92, 0xBB99FF, 0xF0C14B, 0xFF8577].map {
        Color(nsColor: NSColor(hex: $0))
    }

    private static func avatarColor(_ login: String) -> Color {
        avatarColors[login.unicodeScalars.reduce(0) { $0 + Int($1.value) } % avatarColors.count]
    }
}
