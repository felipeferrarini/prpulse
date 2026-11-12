import PRPulseCore
import SwiftUI

enum SelectionState {
    case off, partial, on
}

/// A row that can be ticked to act on several at once.
struct RowSelection {
    let state: SelectionState
    let toggle: () -> Void
}

struct RowAction: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let perform: () -> Void
}

struct PullRequestRow: View {
    let model: RowModel
    let isDimmed: Bool
    let entranceIndex: Int
    let entered: Bool
    var onMute: (() -> Void)?
    /// What a click does instead of opening the pull request: a stack opens its own list.
    var onOpen: (() -> Void)?
    var selection: RowSelection?
    /// The menu of a row that stands for a stack.
    var groupActions: [RowAction] = []

    @Environment(\.nudging) private var nudging
    @Environment(\.reviewing) private var reviewing
    @LocalState private var isHovering = false
    @LocalState private var copied = false

    private static let barWidth: CGFloat = 46

    var body: some View {
        let waiting = Waiting(since: model.pr.createdAt, now: Date())
        return HStack(spacing: 0) {
            Button(action: tap) { openLabel(waiting) }
                .buttonStyle(.plain)
            actionsMenu.padding(.trailing, 10)
        }
        .background(isHovering ? Color.primary.opacity(0.07) : .clear)
        .onHover { isHovering = $0 }
        .contextMenu { menu }
        .help(model.title)
        .accessibilityLabel("\(model.title), \(model.subtitle), \(waiting.text)")
        .opacity(entered ? (isDimmed ? 0.28 : 1) : 0)
        .offset(y: entered ? 0 : 8)
        .animation(.easeInOut(duration: 0.25), value: isDimmed)
        .animation(.easeOut(duration: 0.42).delay(0.11 + Double(min(entranceIndex, 14)) * 0.028), value: entered)
    }

    private func tap() {
        if let selection { return selection.toggle() }
        if let onOpen { return onOpen() }
        nudging.opened(model.pr.url)
        NSWorkspace.shared.open(model.pr.url)
    }

    private func openLabel(_ waiting: Waiting) -> some View {
        HStack(spacing: 11) {
            if let selection { checkbox(selection.state) }
            lead.frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(model.subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Group {
                if model.offersCopy, isHovering || copied {
                    copyButton
                } else {
                    HStack(spacing: 4) {
                        if model.hasConflict { conflictFlag }
                        if let badge = model.stackBadge { chip(RowModel.Chip(id: "position", text: badge, tone: nil)) }
                        ForEach(model.chips) { chip($0) }
                    }
                }
            }
            .fixedSize()
            .layoutPriority(1)
            waitIndicator(waiting).frame(width: 62, alignment: .trailing)
            if model.isStack {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var menu: some View {
        if model.isStack {
            ForEach(groupActions) { action in
                Button(action: action.perform) { Label(action.title, systemImage: action.symbol) }
            }
        } else {
            pullRequestMenu
        }
    }

    @ViewBuilder private var pullRequestMenu: some View {
        Button {
            nudging.opened(model.pr.url)
            NSWorkspace.shared.open(model.pr.url)
        } label: { Label(tr("row.open"), systemImage: "arrow.up.right.square") }
        if model.kind == .review, let primary = reviewing.primary {
            Button { reviewing.review(model.pr, primary) } label: { Label(tr("row.reviewWith", primary.title), systemImage: "sparkles") }
            if !reviewing.others.isEmpty {
                Menu {
                    ForEach(reviewing.others, id: \.self) { destination in
                        Button { reviewing.review(model.pr, destination) } label: { Text(destination.title) }
                    }
                } label: {
                    Label(tr("row.reviewElsewhere"), systemImage: "arrow.up.forward.app")
                }
            }
        }
        Button(action: copyLink) { Label(tr("row.copyLink"), systemImage: "link") }
        nudgeMenu
        if model.canMute, let onMute {
            Divider()
            Button(action: onMute) { Label(tr("row.mute", model.pr.ref.repo), systemImage: "eye.slash") }
        }
    }

    @ViewBuilder private var nudgeMenu: some View {
        if model.kind == .mine { reviewNudgeMenu } else { mergeNudgeItems }
    }

    /// On one of the viewer's own pull requests: whoever may be asked to review it, with a click or with a line of text.
    @ViewBuilder private var reviewNudgeMenu: some View {
        let candidates = nudging.candidates(model.pr)
        let allowed = candidates.filter(\.isAllowed)
        if model.pr.isDraft || candidates.isEmpty {
            Button {} label: { Label(model.pr.isDraft ? tr("row.nudge.draft") : tr("row.nudge.empty"), systemImage: "hand.wave") }
                .disabled(true)
        } else {
            Menu {
                ForEach(candidates) { candidate in
                    if let block = candidate.block {
                        Button {} label: { Text(Self.blockText(block, login: candidate.login)) }.disabled(true)
                    } else {
                        Button { nudging.send(model.pr, candidate, false) } label: { Text(candidate.login) }
                    }
                }
            } label: {
                Label(tr("row.nudge"), systemImage: "hand.wave")
            }
            if !allowed.isEmpty {
                Menu {
                    ForEach(allowed) { candidate in
                        Button { nudging.send(model.pr, candidate, true) } label: { Text(candidate.login) }
                    }
                } label: {
                    Label(tr("row.nudge.withMessage"), systemImage: "hand.wave")
                }
            }
        }
    }

    /// On a pull request of someone else that the viewer reviewed and that has the reviews it needs: tell its author.
    @ViewBuilder private var mergeNudgeItems: some View {
        if let candidate = nudging.candidates(model.pr).first(where: { $0.kind == .merge }) {
            if let block = candidate.block {
                Button {} label: { Label(Self.blockText(block, login: candidate.login), systemImage: "arrow.triangle.merge") }.disabled(true)
            } else {
                Button { nudging.send(model.pr, candidate, false) } label: {
                    Label(tr("row.nudge.merge", candidate.login), systemImage: "arrow.triangle.merge")
                }
                Button { nudging.send(model.pr, candidate, true) } label: {
                    Label(tr("row.nudge.mergeMessage", candidate.login), systemImage: "arrow.triangle.merge")
                }
            }
        }
    }

    private static func blockText(_ block: NudgeBlock, login: String) -> String {
        switch block {
        case .noNewCommits: tr("row.nudge.block.noCommits", login)
        case .tooSoon(let date): tr("row.nudge.block.soon", login, date.formatted(date: .omitted, time: .shortened))
        case .limitReached: tr("row.nudge.block.limit", login)
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

    /// A small warning, in the colour of the conflict action, that the pull request cannot be merged as it is.
    private var conflictFlag: some View {
        Image(systemName: ActionLane.conflict.symbol)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(ActionLane.conflict.tone.opacity(0.85))
            .help(tr("row.conflict"))
            .accessibilityLabel(tr("row.conflict"))
            .padding(.trailing, 2)
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
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        case .stack:
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.review)
                .frame(width: 26, height: 26)
                .background(Palette.review.opacity(0.16), in: RoundedRectangle(cornerRadius: 7))
                .accessibilityHidden(true)
        }
    }

    private func checkbox(_ state: SelectionState) -> some View {
        let symbol = switch state {
        case .off: "circle"
        case .partial: "minus.circle.fill"
        case .on: "checkmark.circle.fill"
        }
        return Image(systemName: symbol)
            .font(.system(size: 16))
            .foregroundStyle(state == .off ? Color.secondary.opacity(0.6) : Palette.review)
            .frame(width: 18)
            .accessibilityHidden(true)
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
