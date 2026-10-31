import PRPulseCore
import SwiftUI

enum PopoverTab: Hashable {
    case review, mine
}

enum PopoverMotion {
    static let spring = Animation.spring(response: 0.45, dampingFraction: 0.78)
    static let glide = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.55)
}

struct PopoverHeader: View {
    let org: String
    let total: Int
    @Binding var layout: PopoverLayout
    var agentRuns = AgentRunList()
    @Binding var showsAgents: Bool

    init(org: String, total: Int, layout: Binding<PopoverLayout>, agentRuns: AgentRunList = AgentRunList(), showsAgents: Binding<Bool> = .constant(false)) {
        self.org = org
        self.total = total
        _layout = layout
        self.agentRuns = agentRuns
        _showsAgents = showsAgents
    }

    var body: some View {
        HStack(spacing: 10) {
            BrandGlyph(size: 14, color: Color(nsColor: .windowBackgroundColor))
                .frame(width: 24, height: 24)
                .background(Color.primary, in: RoundedRectangle(cornerRadius: 7))
                .accessibilityHidden(true)
            Text(org).font(.system(size: 13, weight: .semibold))
            Text(pendingText).font(.system(size: 13)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if !agentRuns.runs.isEmpty || showsAgents { AgentsToggle(runs: agentRuns, isOn: $showsAgents) }
            LayoutToggle(layout: $layout)
        }
    }

    private var pendingText: String {
        switch total {
        case 0: tr("popover.upToDate")
        case 1: tr("popover.pending.one")
        default: tr("popover.pending.other", total)
        }
    }
}

struct LayoutToggle: View {
    @Binding var layout: PopoverLayout
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            option(.single, symbol: "rectangle", help: tr("popover.layout.single"))
            option(.split, symbol: "rectangle.split.2x1", help: tr("popover.layout.split"))
        }
        .padding(2)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 9))
    }

    private func option(_ value: PopoverLayout, symbol: String, help: String) -> some View {
        let selected = layout == value
        return Button { withAnimation(PopoverMotion.glide) { layout = value } } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? Color.primary : .secondary)
                .frame(width: 30, height: 26)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 7).fill(Palette.thumb)
                            .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                            .matchedGeometryEffect(id: "thumb", in: thumb)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct TabSegment: View {
    @Binding var tab: PopoverTab
    let reviewCount: Int
    let mineCount: Int
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            segment(.review, title: tr("popover.tab.review"), symbol: "eye", count: reviewCount)
            segment(.mine, title: tr("popover.tab.mine"), symbol: "arrow.triangle.branch", count: mineCount)
        }
        .padding(3)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 11))
    }

    private func segment(_ value: PopoverTab, title: String, symbol: String, count: Int) -> some View {
        let selected = tab == value
        return Button { withAnimation(PopoverMotion.spring) { tab = value } } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                Text(title).font(.system(size: 13.5, weight: .semibold))
                countBadge(count, tinted: value == .review)
            }
            .foregroundStyle(selected ? Color.primary : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 8).fill(Palette.thumb)
                        .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                        .matchedGeometryEffect(id: "thumb", in: thumb)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func countBadge(_ count: Int, tinted: Bool) -> some View {
        Text("\(count)")
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundStyle(tinted ? Palette.review : .secondary)
            .frame(minWidth: 20, minHeight: 20)
            .padding(.horizontal, 3)
            .background((tinted ? Palette.review : Color.primary).opacity(tinted ? 0.22 : 0.08), in: Capsule())
    }
}

struct LaneFilterBar: View {
    let lanes: [ActionLane]
    let summary: Summary
    @Binding var selection: ActionLane?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(lanes, id: \.self) { lane in chip(lane) }
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 28)
    }

    private func chip(_ lane: ActionLane) -> some View {
        let selected = selection == lane
        return Button { withAnimation(.easeInOut(duration: 0.25)) { selection = selected ? nil : lane } } label: {
            HStack(spacing: 5) {
                Circle().fill(lane.tone).frame(width: 7, height: 7)
                Text(lane.filterTitle).font(.system(size: 11.5))
                Text("\(summary.count(for: lane))").font(.system(size: 11.5, weight: .semibold).monospacedDigit())
            }
            .foregroundStyle(selected ? Color.primary : .secondary)
            .padding(.leading, 7)
            .padding(.trailing, 8)
            .frame(height: 28)
            .background(selected ? lane.tone.opacity(0.16) : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? lane.tone : Palette.line, lineWidth: selected ? 1.5 : 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("popover.filter.label", lane.filterTitle, summary.count(for: lane)))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension View {
    /// Collapses a view to nothing while keeping the change animatable (a `nil` height is not).
    func folded(_ hidden: Bool, height: CGFloat) -> some View {
        frame(height: hidden ? 0 : height, alignment: .top)
            .clipped()
            .opacity(hidden ? 0 : 1)
            .accessibilityHidden(hidden)
    }
}
