import PRPulseCore
import SwiftUI

struct PullRequestRow: View {
    let model: RowModel
    let isDimmed: Bool
    let entranceIndex: Int
    let entered: Bool

    @LocalState private var isHovering = false

    private static let barWidth: CGFloat = 46

    var body: some View {
        let waiting = Waiting(since: model.pr.createdAt, now: Date())
        return Button { NSWorkspace.shared.open(model.pr.url) } label: {
            HStack(spacing: 11) {
                lead.frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.pr.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(model.subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                HStack(spacing: 4) { ForEach(model.chips) { chip($0) } }
                    .fixedSize()
                    .layoutPriority(1)
                waitIndicator(waiting).frame(width: 62, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(isHovering ? Color.primary.opacity(0.07) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(model.pr.title)
        .accessibilityLabel("\(model.pr.title), \(model.subtitle), \(waiting.text)")
        .opacity(entered ? (isDimmed ? 0.28 : 1) : 0)
        .offset(y: entered ? 0 : 8)
        .animation(.easeInOut(duration: 0.25), value: isDimmed)
        .animation(.easeOut(duration: 0.42).delay(0.11 + Double(min(entranceIndex, 14)) * 0.028), value: entered)
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
