import PRPulseCore
import SwiftUI

struct PullRequestRow: View {
    let pr: PullRequestSnapshot
    let chips: [ReasonChip]
    let detail: String?

    @LocalState private var isHovering = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(pr.ref.shortName).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
                Text(pr.title).font(.callout).lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    ForEach(Array(chips.enumerated()), id: \.element.id) { index, chip in
                        ChipView(chip: chip, isPrimary: index == 0)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovering ? Color.primary.opacity(0.07) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private func open() {
        NSWorkspace.shared.open(pr.url)
    }
}

private struct ChipView: View {
    let chip: ReasonChip
    let isPrimary: Bool

    var body: some View {
        Text(chip.text)
            .font(isPrimary ? .caption.weight(.semibold) : .caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(isPrimary ? chip.color : .secondary)
            .background((isPrimary ? chip.color : Color.gray).opacity(0.16), in: Capsule())
    }
}
