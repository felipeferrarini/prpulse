import PRPulseCore
import SwiftUI

/// What the panel can do with a review that an agent made in the background.
struct AgentActions {
    var open: (UUID) -> Void = { _ in }
    var remove: (UUID) -> Void = { _ in }
    var answer: (UUID, Bool) -> Void = { _, _ in }
    var ask: (UUID, String) -> Void = { _, _ in }
    var retry: (AgentRun) -> Void = { _ in }
    var continueInDesktop: (AgentRun) -> Void = { _ in }
    var continueInTerminal: (AgentRun) -> Void = { _ in }
    var consumeFocus: () -> Void = {}
}

/// The header button that opens the reviews of the agents.
struct AgentsToggle: View {
    let runs: AgentRunList
    @Binding var isOn: Bool

    var body: some View {
        Button { withAnimation(PopoverMotion.spring) { isOn.toggle() } } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isOn ? Color.primary : .secondary)
                    .frame(width: 30, height: 30)
                    .background(isOn ? Palette.thumb : Palette.surface, in: RoundedRectangle(cornerRadius: 9))
                badge
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tr("agents.tab.help"))
        .accessibilityLabel(tr("agents.tab.help"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    @ViewBuilder private var badge: some View {
        if !runs.running.isEmpty {
            Text("\(runs.running.count)")
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(minWidth: 15, minHeight: 15)
                .background(runs.needsApproval ? Palette.ci : Palette.review, in: Capsule())
                .offset(x: 4, y: -4)
        } else if runs.hasUnseen {
            Circle().fill(Palette.merge).frame(width: 9, height: 9).offset(x: 3, y: -3)
        }
    }
}

/// The reviews in progress and done, and one of them opened.
struct AgentsPane: View {
    let runs: AgentRunList
    let actions: AgentActions
    @Binding var openRun: UUID?

    private static let rowHeight: CGFloat = 54
    private static let maxHeight: CGFloat = 410

    var body: some View {
        if let id = openRun, let run = runs.run(id: id) {
            AgentRunDetail(run: run, actions: actions) { openRun = nil }
                .frame(height: Self.maxHeight)
        } else {
            list.frame(height: listHeight)
        }
    }

    private var listHeight: CGFloat {
        min(max(CGFloat(runs.runs.count) * Self.rowHeight + 8, 120), Self.maxHeight)
    }

    @ViewBuilder private var list: some View {
        if runs.runs.isEmpty {
            Text(tr("agents.pane.empty"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(runs.runs) { run in
                        AgentRunRow(run: run, onOpen: { open(run) }, onRemove: { actions.remove(run.id) })
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func open(_ run: AgentRun) {
        actions.open(run.id)
        openRun = run.id
    }
}

private struct AgentRunRow: View {
    let run: AgentRun
    let onOpen: () -> Void
    let onRemove: () -> Void

    @LocalState private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onOpen) { label }.buttonStyle(.plain)
            removeButton.padding(.trailing, 10)
        }
        .background(isHovering ? Color.primary.opacity(0.07) : .clear)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
    }

    private var label: some View {
        HStack(spacing: 11) {
            lead.frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.heading(of: run)).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            trailing
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 7)
        .frame(height: 54)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var lead: some View {
        switch run.state {
        case .running where run.approval != nil:
            Image(systemName: "hand.raised.fill").font(.system(size: 14)).foregroundStyle(Palette.ci)
        case .running:
            ProgressView().controlSize(.small)
        case .finished:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).foregroundStyle(Palette.merge)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 14)).foregroundStyle(Palette.ci)
        }
    }

    private var subtitle: String {
        switch run.state {
        case .running: run.approval.map { tr("agents.run.needsApproval", $0.tool) } ?? run.activity ?? tr("agents.run.starting")
        case .finished: tr("agents.run.finished", Self.relative(run.finishedAt ?? run.startedAt))
        case .failed: tr("agents.run.failed", run.output?.split(separator: "\n").first.map(String.init) ?? "")
        }
    }

    @ViewBuilder private var trailing: some View {
        if run.isRunning {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Self.elapsed(from: run.startedAt, to: context.date))
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } else if !run.isSeen {
            Circle().fill(Palette.review).frame(width: 8, height: 8)
        }
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: run.isRunning ? "stop.circle" : "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isHovering ? Color.primary : Color.secondary.opacity(0.5))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(run.isRunning ? tr("agents.run.cancel") : tr("agents.run.remove"))
        .accessibilityLabel(run.isRunning ? tr("agents.run.cancel") : tr("agents.run.remove"))
    }

    private static func heading(of run: AgentRun) -> String {
        run.isGroup ? run.title : "\(run.ref.repo) #\(run.ref.number)  \(run.title)"
    }

    static func elapsed(from start: Date, to end: Date) -> String {
        let seconds = max(Int(end.timeIntervalSince(start)), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func relative(_ date: Date) -> String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}

private struct AgentRunDetail: View {
    let run: AgentRun
    let actions: AgentActions
    let onBack: () -> Void

    @LocalState private var copied = false
    @LocalState private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            top
            Divider()
            content
            if run.state == .finished {
                Divider()
                followUp
                Divider()
                Text(tr("agents.detail.desktopHint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            Divider()
            bottom
        }
    }

    private var top: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Label(tr("agents.detail.back"), systemImage: "chevron.left")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.review)
            }
            .buttonStyle(.plain)
            Text(run.isGroup ? run.title : "\(run.ref.owner)/\(run.ref.repo) #\(run.ref.number)  \(run.title)")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
    }

    @ViewBuilder private var content: some View {
        if run.isRunning && run.question == nil {
            VStack(spacing: 10) {
                if let approval = run.approval {
                    approvalCard(approval)
                } else {
                    ProgressView().controlSize(.regular)
                    Text(run.activity ?? tr("agents.run.starting")).font(.system(size: 13)).foregroundStyle(.secondary)
                    Text(tr("agents.detail.running")).font(.system(size: 12)).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    Text(Self.formatted(run.output ?? ""))
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                if run.isRunning {
                    Divider()
                    waiting
                }
            }
        }
    }

    /// Under a review that is being followed up: what the agent does, or what it asks to be allowed to do.
    @ViewBuilder private var waiting: some View {
        if let approval = run.approval {
            approvalCard(approval).padding(12)
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(run.activity ?? tr("agents.run.starting")).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
        }
    }

    private func approvalCard(_ approval: ToolApproval) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(tr("agents.approval.ask", approval.tool), systemImage: "hand.raised.fill")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Palette.ci)
            ScrollView {
                Text(approval.summary)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 96)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            Text(tr("agents.approval.detail")).font(.system(size: 11)).foregroundStyle(.tertiary)
            HStack(spacing: 8) {
                action(tr("agents.approval.allow"), symbol: "checkmark") { actions.answer(run.id, true) }
                action(tr("agents.approval.deny"), symbol: "xmark") { actions.answer(run.id, false) }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var followUp: some View {
        HStack(spacing: 8) {
            TextField(tr("agents.followUp.placeholder"), text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(canSend ? Palette.review : Color.secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .help(tr("agents.followUp.send"))
            .accessibilityLabel(tr("agents.followUp.send"))
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend else { return }
        actions.ask(run.id, draft)
        draft = ""
    }

    private var bottom: some View {
        HStack(spacing: 8) {
            if run.state == .finished {
                Text(tr("agents.detail.continue")).font(.system(size: 11.5)).foregroundStyle(.secondary)
                action(tr("agents.detail.continueDesktop"), symbol: "bubble.left.and.text.bubble.right") { actions.continueInDesktop(run) }
                action(tr("agents.detail.continueTerminal"), symbol: "terminal") { actions.continueInTerminal(run) }
                Divider().frame(height: 16)
                action(copied ? tr("agents.detail.copied") : tr("agents.detail.copy"), symbol: copied ? "checkmark" : "doc.on.doc", perform: copy)
            } else if run.state == .failed {
                action(tr("agents.detail.retry"), symbol: "arrow.clockwise") { actions.retry(run) }
            } else if run.isRunning {
                action(tr("agents.run.cancel"), symbol: "stop.circle") { actions.remove(run.id) }
            }
            Spacer(minLength: 0)
            action(tr("agents.detail.openPR"), symbol: "arrow.up.right.square") { NSWorkspace.shared.open(run.url) }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
    }

    private func action(_ title: String, symbol: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Palette.review)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(Palette.review.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(run.output ?? "", forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
    }

    /// Markdown for the parts a line can show, with the line breaks kept.
    private static func formatted(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
