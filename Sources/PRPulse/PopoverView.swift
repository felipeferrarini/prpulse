import PRPulseCore
import SwiftUI

struct PopoverView: View {
    let data: ViewData
    @Binding var layout: PopoverLayout
    var openToken = 0
    var onMute: (PullRequestRef) -> Void = { _ in }
    /// Set when an agent can be asked to review the pull requests waiting for the viewer.
    var onReview: ((PullRequestSnapshot) -> Void)?
    /// Set when the main action runs in the background and a draft in Claude Desktop is the other choice.
    var onReviewInDesktop: ((PullRequestSnapshot) -> Void)?
    /// Set when several pull requests can be given to an agent as one: a whole stack, or the ones the viewer chose.
    var onReviewGroup: (([PullRequestSnapshot], ReviewRequest.Scope) -> Void)?
    /// Set when several pull requests can each be given to an agent.
    var onReviewEach: (([PullRequestSnapshot]) -> Void)?
    var agentRuns = AgentRunList()
    var agentActions: AgentActions?
    var agentFocus = AgentFocus()
    /// The live popover is built anew each time it opens, so it plays its entrance when it appears.
    var entersOnAppear = false
    /// Called when something inside the popover changes what it needs to show, so its window can follow.
    var onContentChange: () -> Void = {}
    let onRefresh: () -> Void
    let onSettings: () -> Void

    @LocalState private var tab: PopoverTab
    @LocalState private var filter: ActionLane?
    @LocalState private var entered = true
    @LocalState private var showsAgents = false
    @LocalState private var openRun: UUID?

    init(
        data: ViewData,
        layout: Binding<PopoverLayout>,
        openToken: Int = 0,
        onMute: @escaping (PullRequestRef) -> Void = { _ in },
        onReview: ((PullRequestSnapshot) -> Void)? = nil,
        onReviewInDesktop: ((PullRequestSnapshot) -> Void)? = nil,
        onReviewGroup: (([PullRequestSnapshot], ReviewRequest.Scope) -> Void)? = nil,
        onReviewEach: (([PullRequestSnapshot]) -> Void)? = nil,
        agentRuns: AgentRunList = AgentRunList(),
        agentActions: AgentActions? = nil,
        agentFocus: AgentFocus = AgentFocus(),
        entersOnAppear: Bool = false,
        onContentChange: @escaping () -> Void = {},
        initialTab: PopoverTab = .review,
        initialFilter: ActionLane? = nil,
        onRefresh: @escaping () -> Void,
        onSettings: @escaping () -> Void
    ) {
        self.data = data
        _layout = layout
        self.openToken = openToken
        self.onMute = onMute
        self.onReview = onReview
        self.onReviewInDesktop = onReviewInDesktop
        self.onReviewGroup = onReviewGroup
        self.onReviewEach = onReviewEach
        self.agentRuns = agentRuns
        self.agentActions = agentActions
        self.agentFocus = agentFocus
        self.entersOnAppear = entersOnAppear
        self.onContentChange = onContentChange
        self.onRefresh = onRefresh
        self.onSettings = onSettings
        _tab = LocalState(initialValue: initialTab)
        _filter = LocalState(initialValue: initialFilter)
        _entered = LocalState(initialValue: !entersOnAppear)
    }

    private static let singleWidth: CGFloat = 560
    private static let splitWidth: CGFloat = 920

    var body: some View {
        VStack(spacing: 0) {
            if data.isOffline { OfflineBanner(text: data.summary == nil ? tr("popover.offline.noData") : tr("popover.offline")) }
            content
            Divider()
            PopoverFooter(lastUpdated: data.lastUpdated, onRefresh: onRefresh, onSettings: onSettings)
        }
        .frame(width: width)
        .clipShape(RoundedRectangle(cornerRadius: PopoverChrome.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PopoverChrome.cornerRadius, style: .continuous).strokeBorder(Palette.line))
        .focusEffectDisabled()
        .onChange(of: openToken) { _, _ in popoverOpened() }
        .onChange(of: agentFocus.token) { _, _ in applyAgentFocus() }
        .onChange(of: showsAgents) { _, _ in onContentChange() }
        .onChange(of: openRun) { _, _ in onContentChange() }
        .onChange(of: agentRuns) { _, _ in onContentChange() }
        .onAppear { if entersOnAppear { popoverOpened() } }
    }

    private var width: CGFloat {
        showsSummary && layout == .split ? Self.splitWidth : Self.singleWidth
    }

    private var showsSummary: Bool {
        data.isSetupComplete && data.summary != nil && !isFailed
    }

    private var isFailed: Bool {
        if case .failed = data.state { true } else { false }
    }

    @ViewBuilder private var content: some View {
        if !data.isSetupComplete {
            FailureView(failure: .notConfigured, onSettings: onSettings)
        } else if case .failed(let failure) = data.state {
            FailureView(failure: failure, onSettings: onSettings)
        } else if let summary = data.summary {
            summaryContent(summary)
        } else {
            LoadingStateView()
        }
    }

    private func summaryContent(_ summary: Summary) -> some View {
        let isSingle = layout == .single
        return VStack(spacing: 0) {
            PopoverHeader(org: data.orgLabel, total: summary.total, layout: $layout, agentRuns: agentRuns, showsAgents: $showsAgents)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 12)
            if showsAgents, let agentActions {
                AgentsPane(runs: agentRuns, actions: agentActions, openRun: $openRun)
            } else if summary.total == 0 && summary.waiting.isEmpty {
                EmptyStateView()
            } else {
                TabSegment(tab: $tab, reviewCount: summary.review.count, mineCount: summary.mine.count)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .folded(!isSingle, height: 50)
                LaneFilterBar(lanes: summary.activeLanes, summary: summary, selection: laneSelection(summary))
                    .padding(.bottom, 12)
                SummaryPanes(summary: summary, layout: layout, tab: tab, filter: filter, entered: entered, showsOwner: data.showsOwner, onMute: onMute, onReview: onReview, onReviewInDesktop: onReviewInDesktop, onReviewGroup: onReviewGroup, onReviewEach: onReviewEach, onContentChange: onContentChange)
            }
        }
    }

    private func laneSelection(_ summary: Summary) -> Binding<ActionLane?> {
        Binding(
            get: { filter },
            set: { lane in
                filter = lane
                guard let lane, layout == .single else { return }
                withAnimation(PopoverMotion.spring) { tab = lane == .review ? .review : .mine }
            }
        )
    }

    private var hasMineContent: Bool {
        guard let summary = data.summary else { return false }
        return !summary.mine.isEmpty || !summary.waiting.isEmpty
    }

    private func popoverOpened() {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            entered = false
            filter = nil
            tab = (data.summary?.review.isEmpty ?? true) && hasMineContent ? .mine : .review
            showsAgents = false
            openRun = nil
        }
        DispatchQueue.main.async { entered = true }
        applyAgentFocus()
    }

    /// A review was just started, or its notification was opened: show the agents, and the review if there is one.
    private func applyAgentFocus() {
        guard agentFocus.isPending, let agentActions else { return }
        withAnimation(PopoverMotion.spring) {
            showsAgents = true
            openRun = agentFocus.run
        }
        agentActions.consumeFocus()
    }
}

private struct PaneHeightKey: PreferenceKey {
    static let defaultValue: [PopoverTab: CGFloat] = [:]

    static func reduce(value: inout [PopoverTab: CGFloat], nextValue: () -> [PopoverTab: CGFloat]) {
        value.merge(nextValue()) { max($0, $1) }
    }
}

private struct SummaryPanes: View {
    let summary: Summary
    let layout: PopoverLayout
    let tab: PopoverTab
    let filter: ActionLane?
    let entered: Bool
    let showsOwner: Bool
    let onMute: (PullRequestRef) -> Void
    let onReview: ((PullRequestSnapshot) -> Void)?
    let onReviewInDesktop: ((PullRequestSnapshot) -> Void)?
    let onReviewGroup: (([PullRequestSnapshot], ReviewRequest.Scope) -> Void)?
    let onReviewEach: (([PullRequestSnapshot]) -> Void)?
    let onContentChange: () -> Void

    @LocalState private var heights: [PopoverTab: CGFloat] = [:]
    @LocalState private var openStacks: [PopoverTab: StackKey] = [:]
    @LocalState private var selecting = false
    @LocalState private var selection: Set<PullRequestRef> = []

    private static let minListHeight: CGFloat = 120
    private static let maxListHeight: CGFloat = 410
    private static let singleWidth: CGFloat = 560
    private static let splitWidth: CGFloat = 920
    private static let paneHeaderHeight: CGFloat = 36

    private var isSingle: Bool { layout == .single }
    private var paneWidth: CGFloat { isSingle ? Self.singleWidth : Self.splitWidth / 2 }
    private var canSelect: Bool { onReviewGroup != nil || onReviewEach != nil }

    private var listHeight: CGFloat {
        let tallest = max(heights[.review] ?? 0, heights[.mine] ?? 0)
        return min(max(tallest, Self.minListHeight), Self.maxListHeight)
    }

    var body: some View {
        HStack(spacing: 0) {
            pane(.review).frame(width: paneWidth)
            pane(.mine).frame(width: paneWidth).background(alignment: .leading) {
                if !isSingle { Rectangle().fill(Palette.line).frame(width: 1) }
            }
        }
        .offset(x: isSingle && tab == .mine ? -paneWidth : 0)
        .frame(width: isSingle ? Self.singleWidth : Self.splitWidth, alignment: .leading)
        .clipped()
        .onPreferenceChange(PaneHeightKey.self) { heights = $0 }
        .animation(PopoverMotion.glide, value: layout)
        .animation(PopoverMotion.spring, value: tab)
        .onChange(of: openStacks) { _, _ in onContentChange() }
        .onChange(of: selecting) { _, _ in onContentChange() }
    }

    // MARK: Panes

    private func pane(_ kind: PopoverTab) -> some View {
        let entries = entries(for: kind)
        let open = openGroup(in: entries, for: kind)
        let hidden = isSingle && tab != kind
        return VStack(spacing: 0) {
            if let open {
                stackHeader(open, kind)
                stackActions(open, kind)
            } else {
                paneHeader(kind).folded(isSingle, height: Self.paneHeaderHeight)
                if isSingle && kind == .review && canSelect && !summary.review.isEmpty { selectRow }
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let open { stackRows(open, kind) } else { listRows(entries, kind) }
                }
                .padding(.vertical, 4)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: PaneHeightKey.self, value: [kind: proxy.size.height])
                })
            }
            .frame(height: listHeight)
            if kind == .review && selecting { selectionBar }
        }
        .accessibilityHidden(hidden)
        .allowsHitTesting(!hidden)
    }

    @ViewBuilder private func listRows(_ entries: [ListEntry<RowModel>], _ kind: PopoverTab) -> some View {
        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
            switch entry {
            case .single(let row, _): singleRow(row, index: index, kind: kind)
            case .stack(let group): stackRow(group, index: index, kind: kind)
            }
        }
        if kind == .mine && !summary.waiting.isEmpty { waitingSection(startIndex: entries.count) }
        if entries.isEmpty && !(kind == .mine && !summary.waiting.isEmpty) { PaneEmptyText() }
    }

    private func singleRow(_ row: RowModel, index: Int, kind: PopoverTab) -> some View {
        PullRequestRow(
            model: row, isDimmed: isDimmed(row), entranceIndex: index, entered: entered,
            onMute: { onMute(row.pr.ref) },
            onReview: onReview.map { review in { review(row.pr) } },
            onReviewInDesktop: onReviewInDesktop.map { review in { review(row.pr) } },
            selection: selection(of: row, kind: kind)
        )
    }

    private func stackRow(_ group: StackGroup<RowModel>, index: Int, kind: PopoverTab) -> some View {
        let model = RowModel.stack(group, showsOwner: showsOwner)
        return PullRequestRow(
            model: model, isDimmed: isDimmed(model), entranceIndex: index, entered: entered,
            onOpen: { open(group.key, kind: kind) },
            selection: selection(of: group, kind: kind),
            groupActions: actions(for: group, kind: kind)
        )
    }

    private func stackRows(_ group: StackGroup<RowModel>, _ kind: PopoverTab) -> some View {
        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, row in
            singleRow(row, index: index, kind: kind)
        }
    }

    // MARK: The stack that is open

    private func stackHeader(_ group: StackGroup<RowModel>, _ kind: PopoverTab) -> some View {
        HStack(spacing: 10) {
            Button { close(kind) } label: {
                Label(kind == .review ? tr("popover.review") : tr("popover.mine"), systemImage: "chevron.left")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.review)
            }
            .buttonStyle(.plain)
            Text(tr("stack.header", showsOwner ? "\(group.key.owner)/\(group.key.repo)" : group.key.repo))
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(group.isComplete ? tr("chip.stack", group.size) : tr("stack.partial", group.members.count, group.size))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(height: Self.paneHeaderHeight, alignment: .center)
    }

    @ViewBuilder private func stackActions(_ group: StackGroup<RowModel>, _ kind: PopoverTab) -> some View {
        if kind == .review, onReviewGroup != nil || onReviewEach != nil {
            HStack(spacing: 8) {
                if let onReviewGroup {
                    PillButton(title: tr("stack.review"), symbol: "sparkles") { onReviewGroup(group.members.map(\.pr), .stack) }
                }
                if let onReviewEach {
                    PillButton(title: tr("stack.reviewEach"), symbol: "list.bullet") { onReviewEach(group.members.map(\.pr)) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    private func entries(for kind: PopoverTab) -> [ListEntry<RowModel>] {
        StackGrouping.entries(rows(for: kind), pr: \.pr)
    }

    private func openGroup(in entries: [ListEntry<RowModel>], for kind: PopoverTab) -> StackGroup<RowModel>? {
        guard let key = openStacks[kind] else { return nil }
        for case .stack(let group) in entries where group.key == key { return group }
        return nil
    }

    private func open(_ key: StackKey, kind: PopoverTab) {
        withAnimation(PopoverMotion.spring) { openStacks[kind] = key }
    }

    private func close(_ kind: PopoverTab) {
        withAnimation(PopoverMotion.spring) { openStacks[kind] = nil }
    }

    private func actions(for group: StackGroup<RowModel>, kind: PopoverTab) -> [RowAction] {
        var actions: [RowAction] = []
        if kind == .review, let onReviewGroup {
            actions.append(RowAction(id: "stack", title: tr("stack.review"), symbol: "sparkles") { onReviewGroup(group.members.map(\.pr), .stack) })
        }
        if kind == .review, let onReviewEach {
            actions.append(RowAction(id: "each", title: tr("stack.reviewEach"), symbol: "list.bullet") { onReviewEach(group.members.map(\.pr)) })
        }
        actions.append(RowAction(id: "open", title: tr("stack.open"), symbol: "arrow.up.right.square") { NSWorkspace.shared.open(group.bottom.url) })
        actions.append(RowAction(id: "copy", title: tr("stack.copy"), symbol: "link") { Self.copyLinks(of: group) })
        return actions
    }

    private static func copyLinks(of group: StackGroup<RowModel>) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(group.members.map(\.pr.url.absoluteString).joined(separator: "\n"), forType: .string)
    }

    // MARK: Choosing several

    private func selection(of row: RowModel, kind: PopoverTab) -> RowSelection? {
        guard selecting, kind == .review, row.kind == .review else { return nil }
        let ref = row.pr.ref
        return RowSelection(state: selection.contains(ref) ? .on : .off) { toggle(ref) }
    }

    private func selection(of group: StackGroup<RowModel>, kind: PopoverTab) -> RowSelection? {
        guard selecting, kind == .review else { return nil }
        let refs = group.refs
        let chosen = refs.filter(selection.contains).count
        let state: SelectionState = chosen == 0 ? .off : (chosen == refs.count ? .on : .partial)
        return RowSelection(state: state) {
            if state == .on { selection.subtract(refs) } else { selection.formUnion(refs) }
        }
    }

    private func toggle(_ ref: PullRequestRef) {
        if !selection.insert(ref).inserted { selection.remove(ref) }
    }

    private func chosenPullRequests() -> [PullRequestSnapshot] {
        summary.review.map(\.pr).filter { selection.contains($0.ref) }
    }

    private func endSelecting() {
        withAnimation(PopoverMotion.spring) {
            selecting = false
            selection = []
        }
    }

    private var selectionBar: some View {
        let chosen = chosenPullRequests()
        return HStack(spacing: 8) {
            Text(tr("batch.count", chosen.count)).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if let onReviewEach {
                PillButton(title: tr("batch.each"), symbol: "list.bullet", isEnabled: !chosen.isEmpty) {
                    onReviewEach(chosen)
                    endSelecting()
                }
            }
            if let onReviewGroup {
                PillButton(title: tr("batch.together"), symbol: "sparkles", isEnabled: chosen.count > 1) {
                    onReviewGroup(chosen, .together)
                    endSelecting()
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    // MARK: Headers and the rest

    private func waitingSection(startIndex: Int) -> some View {
        let rows = summary.waiting.map { RowModel.waiting($0, showsOwner: showsOwner) }
        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "hourglass").font(.system(size: 11, weight: .semibold))
                Text(tr("popover.waiting.title")).font(.system(size: 12, weight: .semibold))
                Text("\(rows.count)").font(.system(size: 12)).foregroundStyle(.tertiary)
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, startIndex == 0 ? 6 : 14)
            .padding(.bottom, 4)
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                PullRequestRow(model: row, isDimmed: isDimmed(row), entranceIndex: startIndex + index, entered: entered)
            }
        }
    }

    private func paneHeader(_ kind: PopoverTab) -> some View {
        let isReview = kind == .review
        return HStack {
            Label(isReview ? tr("popover.review") : tr("popover.mine"), systemImage: isReview ? "eye" : "arrow.triangle.branch")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isReview ? Palette.review : Color.primary)
            Spacer()
            if isReview && canSelect && !summary.review.isEmpty && !isSingle { selectButton }
            Text(isReview ? tr("popover.pane.review.count", summary.review.count) : tr("popover.pane.mine.count", summary.mine.count))
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(height: Self.paneHeaderHeight, alignment: .center)
    }

    /// Where the button to choose several sits when the header of the pane is folded into the tabs.
    private var selectRow: some View {
        HStack {
            Spacer(minLength: 0)
            selectButton
        }
        .padding(.horizontal, 14)
        .frame(height: 26)
    }

    private var selectButton: some View {
        Button {
            if selecting { endSelecting() } else { withAnimation(PopoverMotion.spring) { selecting = true } }
        } label: {
            Label(selecting ? tr("batch.cancel") : tr("batch.select"), systemImage: selecting ? "xmark" : "checklist")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.review)
        }
        .buttonStyle(.plain)
        .padding(.trailing, isSingle ? 0 : 6)
        .help(tr("batch.help"))
    }

    private func rows(for kind: PopoverTab) -> [RowModel] {
        switch kind {
        case .review: summary.review.map { RowModel.review($0, showsOwner: showsOwner) }
        case .mine: summary.mine.map { RowModel.mine($0, showsOwner: showsOwner) }
        }
    }

    private func isDimmed(_ row: RowModel) -> Bool {
        guard let filter else { return false }
        return !row.lanes.contains(filter)
    }
}

/// A small button with an icon, in the colour of the actions.
struct PillButton: View {
    let title: String
    let symbol: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Palette.review)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(Palette.review.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

private struct PaneEmptyText: View {
    var body: some View {
        Text(tr("popover.pane.empty"))
            .font(.system(size: 12.5))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, minHeight: 100)
    }
}
