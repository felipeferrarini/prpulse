import PRPulseCore
import SwiftUI

struct PopoverView: View {
    let data: ViewData
    @Binding var layout: PopoverLayout
    @Binding var sorts: ListSorts
    /// The live popover draws its own outline around the arrow; the pictures draw this one.
    var showsBorder = true
    var openToken = 0
    var onMute: (PullRequestRef) -> Void = { _ in }
    /// The live popover is built anew each time it opens, so it plays its entrance when it appears.
    var entersOnAppear = false
    /// Called when something inside the popover changes what it needs to show, so its window can follow.
    var onContentChange: () -> Void = {}
    /// What the pictures of the README start with: a stack opened, pull requests ticked, pull requests ticked.
    var initialStack: (tab: PopoverTab, key: StackKey)?
    var initialSelection: (tab: PopoverTab, refs: Set<PullRequestRef>)?
    let onRefresh: () -> Void
    let onSettings: () -> Void

    @LocalState private var tab: PopoverTab
    @LocalState private var filter: ActionLane?
    @LocalState private var reviewFilter = ReviewFilter()
    @LocalState private var entered = true

    init(
        data: ViewData,
        layout: Binding<PopoverLayout>,
        sorts: Binding<ListSorts> = .constant(ListSorts()),
        showsBorder: Bool = true,
        openToken: Int = 0,
        onMute: @escaping (PullRequestRef) -> Void = { _ in },
        entersOnAppear: Bool = false,
        onContentChange: @escaping () -> Void = {},
        initialStack: (tab: PopoverTab, key: StackKey)? = nil,
        initialSelection: (tab: PopoverTab, refs: Set<PullRequestRef>)? = nil,
        initialTab: PopoverTab = .review,
        initialFilter: ActionLane? = nil,
        initialReviewFilter: ReviewFilter = ReviewFilter(),
        onRefresh: @escaping () -> Void,
        onSettings: @escaping () -> Void
    ) {
        self.data = data
        _layout = layout
        _sorts = sorts
        self.showsBorder = showsBorder
        self.openToken = openToken
        self.onMute = onMute
        self.entersOnAppear = entersOnAppear
        self.onContentChange = onContentChange
        self.initialStack = initialStack
        self.initialSelection = initialSelection
        self.onRefresh = onRefresh
        self.onSettings = onSettings
        _tab = LocalState(initialValue: initialTab)
        _filter = LocalState(initialValue: initialFilter)
        _reviewFilter = LocalState(initialValue: initialReviewFilter)
        _entered = LocalState(initialValue: !entersOnAppear)
    }

    private static let singleWidth: CGFloat = 560
    private static let splitWidth: CGFloat = 920

    var body: some View {
        VStack(spacing: 0) {
            if data.isOffline { OfflineBanner(text: data.summary == nil ? tr("popover.offline.noData") : tr("popover.offline")) }
            content
            Divider()
            PopoverFooter(lastUpdated: data.lastUpdated, isRefreshing: data.isRefreshing, onRefresh: onRefresh, onSettings: onSettings)
        }
        .frame(width: width)
        .clipShape(RoundedRectangle(cornerRadius: PopoverChrome.cornerRadius, style: .continuous))
        .overlay { if showsBorder { RoundedRectangle(cornerRadius: PopoverChrome.cornerRadius, style: .continuous).strokeBorder(Palette.line) } }
        .focusEffectDisabled()
        .onChange(of: openToken) { _, _ in popoverOpened() }
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
            PopoverHeader(org: data.orgLabel, total: summary.total, layout: $layout)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 12)
            if summary.total == 0 && summary.mine.isEmpty && summary.review.isEmpty {
                EmptyStateView()
            } else {
                TabSegment(tab: $tab, reviewCount: summary.awaitingReviewCount, mineCount: summary.mine.count)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .folded(!isSingle, height: 50)
                LaneFilterBar(lanes: summary.activeLanes, summary: summary, selection: laneSelection(summary))
                    .padding(.bottom, 12)
                SummaryPanes(summary: summary, layout: layout, tab: tab, filter: filter, sorts: $sorts, reviewFilter: $reviewFilter, entered: entered, showsOwner: data.showsOwner, onMute: onMute, initialStack: initialStack, initialSelection: initialSelection, onContentChange: onContentChange)
            }
        }
    }

    private func laneSelection(_ summary: Summary) -> Binding<ActionLane?> {
        Binding(
            get: { filter },
            set: { lane in
                filter = lane
                guard let lane, layout == .single else { return }
                if let target = lane.tab { withAnimation(PopoverMotion.spring) { tab = target } }
            }
        )
    }

    private var hasMineContent: Bool {
        guard let summary = data.summary else { return false }
        return !summary.mine.isEmpty
    }

    private func popoverOpened() {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            entered = false
            filter = nil
            reviewFilter = ReviewFilter()
            tab = (data.summary?.awaitingReviewCount ?? 0) == 0 && hasMineContent ? .mine : .review
        }
        DispatchQueue.main.async { entered = true }
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
    @Binding var sorts: ListSorts
    @Binding var reviewFilter: ReviewFilter
    let entered: Bool
    let showsOwner: Bool
    let onMute: (PullRequestRef) -> Void
    @Environment(\.reviewing) private var reviewing
    @Environment(\.nudging) private var nudging
    var initialStack: (tab: PopoverTab, key: StackKey)?
    var initialSelection: (tab: PopoverTab, refs: Set<PullRequestRef>)?
    let onContentChange: () -> Void

    @LocalState private var heights: [PopoverTab: CGFloat] = [:]
    @LocalState private var openStacks: [PopoverTab: StackKey] = [:]
    /// The pane in which pull requests are being chosen.
    @LocalState private var selecting: PopoverTab? = nil
    @LocalState private var selection: Set<PullRequestRef> = []
    @LocalState private var copied = false

    private static let minListHeight: CGFloat = 120
    private static let maxListHeight: CGFloat = 410
    private static let singleWidth: CGFloat = 560
    private static let splitWidth: CGFloat = 920
    private static let paneHeaderHeight: CGFloat = 36

    private var isSingle: Bool { layout == .single }
    private var paneWidth: CGFloat { isSingle ? Self.singleWidth : Self.splitWidth / 2 }

    private var listHeight: CGFloat {
        let tallest = max(heights[.review] ?? 0, heights[.mine] ?? 0)
        return min(max(tallest, Self.minListHeight), Self.maxListHeight)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
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
        .onChange(of: tab) { _, _ in if selecting != nil { endSelecting() } }
        .onAppear {
            if let initialStack { openStacks[initialStack.tab] = initialStack.key }
            if let initialSelection {
                selecting = initialSelection.tab
                selection = initialSelection.refs
            }
        }
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
                controls(kind)
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
            .frame(height: max(listHeight - chipsHeight(for: kind, showsStack: open != nil), Self.minListHeight / 2))
            .animation(.easeOut(duration: 0.2), value: chipsHeight(for: kind, showsStack: open != nil))
            if selecting == kind { selectionBar(kind) }
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
        if entries.isEmpty { emptyList(kind) }
    }

    private func singleRow(_ row: RowModel, index: Int, kind: PopoverTab) -> some View {
        PullRequestRow(
            model: row, isDimmed: isDimmed(row), entranceIndex: index, entered: entered,
            onMute: { onMute(row.pr.ref) },
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
        if kind == .review, reviewing.isAvailable {
            HStack(spacing: 8) {
                PillButton(title: tr("stack.review"), symbol: "sparkles") { reviewing.reviewTogether(group.members.map(\.pr), .stack) }
                if reviewing.canReviewEach {
                    PillButton(title: tr("stack.reviewEach"), symbol: "list.bullet") { reviewing.reviewEach(group.members.map(\.pr)) }
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
        if kind == .review, reviewing.isAvailable {
            actions.append(RowAction(id: "stack", title: tr("stack.review"), symbol: "sparkles") { reviewing.reviewTogether(group.members.map(\.pr), .stack) })
            if reviewing.canReviewEach {
                actions.append(RowAction(id: "each", title: tr("stack.reviewEach"), symbol: "list.bullet") { reviewing.reviewEach(group.members.map(\.pr)) })
            }
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
        guard selecting == kind else { return nil }
        let ref = row.pr.ref
        return RowSelection(state: selection.contains(ref) ? .on : .off) { toggle(ref) }
    }

    private func selection(of group: StackGroup<RowModel>, kind: PopoverTab) -> RowSelection? {
        guard selecting == kind else { return nil }
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

    /// The pull requests to review that the filter lets through, in the order chosen.
    private var visibleReview: [ReviewItem] {
        reviewFilter.apply(to: ListOrder.sorted(summary.review, by: sorts.review))
    }

    private var sortedMine: [MineItem] { ListOrder.sorted(summary.mine, by: sorts.mine) }

    private func chosenPullRequests(in kind: PopoverTab) -> [PullRequestSnapshot] {
        let shown = kind == .review ? visibleReview.map(\.pr) : sortedMine.map(\.pr)
        return shown.filter { selection.contains($0.ref) }
    }

    private func endSelecting() {
        withAnimation(PopoverMotion.spring) {
            selecting = nil
            selection = []
            copied = false
        }
    }

    private func selectionBar(_ kind: PopoverTab) -> some View {
        let chosen = chosenPullRequests(in: kind)
        return ViewThatFits(in: .horizontal) {
            selectionBar(kind, chosen: chosen, compact: false)
            selectionBar(kind, chosen: chosen, compact: true)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    private func selectionBar(_ kind: PopoverTab, chosen: [PullRequestSnapshot], compact: Bool) -> some View {
        HStack(spacing: 8) {
            Text(tr("batch.count", chosen.count)).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if kind == .review && reviewing.isAvailable {
                if reviewing.canReviewEach {
                    PillButton(title: tr("batch.each"), symbol: "list.bullet", isEnabled: !chosen.isEmpty) {
                        reviewing.reviewEach(chosen)
                        endSelecting()
                    }
                }
                PillButton(title: tr("batch.together"), symbol: "sparkles", isEnabled: chosen.count > 1) {
                    reviewing.reviewTogether(chosen, .together)
                    endSelecting()
                }
            }
            if kind == .mine { nudgeMenu(chosen, showsTitle: !compact) }
            copyMenu(chosen, showsTitle: !compact)
            shareLink(chosen)
        }
    }

    /// Whoever can be nudged on at least one of the pull requests picked, with how many of them.
    private func nudgeMenu(_ chosen: [PullRequestSnapshot], showsTitle: Bool) -> some View {
        let targets = NudgeBatch.targets(for: chosen, candidates: nudging.candidates)
        return Menu {
            ForEach(targets) { target in
                Button(nudgeTitle(target, of: chosen.count)) { send(target, withMessage: false) }
            }
            Menu(tr("batch.nudge.withMessage")) {
                ForEach(targets) { target in
                    Button(nudgeTitle(target, of: chosen.count)) { send(target, withMessage: true) }
                }
            }
        } label: {
            PillLabel(title: tr("batch.nudge"), symbol: "hand.wave", showsTitle: showsTitle)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(targets.isEmpty)
        .opacity(targets.isEmpty ? 0.4 : 1)
        .help(chosen.isEmpty || !targets.isEmpty ? tr("batch.nudge.help") : tr("batch.nudge.none"))
    }

    private func nudgeTitle(_ target: NudgeTarget, of chosen: Int) -> String {
        target.items.count == chosen ? target.login : tr("batch.nudge.person", target.login, target.items.count, chosen)
    }

    private func send(_ target: NudgeTarget, withMessage: Bool) {
        nudging.sendMany(target.login, target.items, withMessage)
        endSelecting()
    }

    private func copyMenu(_ chosen: [PullRequestSnapshot], showsTitle: Bool) -> some View {
        HStack(spacing: 2) {
            Button { copy(chosen, as: .links) } label: {
                PillLabel(
                    title: copied ? tr("batch.copied") : tr("batch.copy"), symbol: copied ? "checkmark" : "link", showsTitle: showsTitle || copied
                )
            }
            .buttonStyle(.plain)
            .help(tr("batch.copy.help"))
            Menu {
                ForEach(LinkFormat.allCases, id: \.self) { format in
                    Button(format.title) { copy(chosen, as: format) }
                }
            } label: {
                PillLabel(title: tr("batch.format"), symbol: "chevron.down", showsTitle: false)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            .help(tr("batch.format"))
        }
        .disabled(chosen.isEmpty || copied)
        .opacity(chosen.isEmpty ? 0.4 : 1)
    }

    private func shareLink(_ chosen: [PullRequestSnapshot]) -> some View {
        ShareLink(item: LinkFormat.titled.text(for: chosen)) {
            PillLabel(title: tr("batch.share"), symbol: "square.and.arrow.up", showsTitle: false)
        }
        .buttonStyle(.plain)
        .disabled(chosen.isEmpty)
        .opacity(chosen.isEmpty ? 0.4 : 1)
        .help(tr("batch.share.help"))
    }

    private func copy(_ chosen: [PullRequestSnapshot], as format: LinkFormat) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(format.text(for: chosen), forType: .string)
        withAnimation(.easeOut(duration: 0.15)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { if copied { endSelecting() } }
    }

    // MARK: Headers and the rest

    /// The chips of the filters make the list below them shorter instead of the pane taller, so the popover keeps its height and
    /// the other pane stays where it is.
    private func chipsHeight(for kind: PopoverTab, showsStack: Bool) -> CGFloat {
        guard kind == .review, !showsStack, !summary.review.isEmpty else { return 0 }
        return ReviewControls.showsChips(filter: reviewFilter, sort: sorts.review) ? ReviewControls.chipsHeight : 0
    }

    @ViewBuilder private func controls(_ kind: PopoverTab) -> some View {
        switch kind {
        case .review where !summary.review.isEmpty:
            ReviewControls(
                items: summary.review, shown: visibleReview.count, filter: $reviewFilter, sort: $sorts.review, showsOwner: showsOwner,
                select: isSingle ? selectControl(.review) : nil
            )
                .padding(.bottom, 4)
        case .mine where !summary.mine.isEmpty:
            MineControls(sort: $sorts.mine, select: isSingle ? selectControl(.mine) : nil).padding(.bottom, 4)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private func emptyList(_ kind: PopoverTab) -> some View {
        if kind == .review && reviewFilter.isActive && !summary.review.isEmpty {
            NoMatchesView { withAnimation(PopoverMotion.spring) { reviewFilter = ReviewFilter() } }
        } else {
            PaneEmptyText()
        }
    }

    private func paneHeader(_ kind: PopoverTab) -> some View {
        let isReview = kind == .review
        let hasRows = isReview ? !summary.review.isEmpty : !summary.mine.isEmpty
        return HStack {
            Label(isReview ? tr("popover.review") : tr("popover.mine"), systemImage: isReview ? "eye" : "arrow.triangle.branch")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isReview ? Palette.review : Color.primary)
            Spacer()
            if !isSingle && hasRows { selectButton(kind) }
            Text(isReview ? tr("popover.pane.review.count", summary.review.count) : tr("popover.pane.mine.count", summary.mine.count))
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(height: Self.paneHeaderHeight, alignment: .center)
    }

    private func toggleSelecting(_ kind: PopoverTab) {
        if selecting == kind { return endSelecting() }
        withAnimation(PopoverMotion.spring) {
            selecting = kind
            selection = []
            copied = false
        }
    }

    private func selectControl(_ kind: PopoverTab) -> SelectControl {
        SelectControl(isOn: selecting == kind, help: selectHelp(kind)) { toggleSelecting(kind) }
    }

    private func selectHelp(_ kind: PopoverTab) -> String {
        kind == .review && reviewing.isAvailable ? tr("batch.help.review") : tr("batch.help")
    }

    private func selectButton(_ kind: PopoverTab) -> some View {
        let isOn = selecting == kind
        return Button { toggleSelecting(kind) } label: {
            Label(isOn ? tr("batch.cancel") : tr("batch.select"), systemImage: isOn ? "xmark" : "checklist")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(kind == .review ? Palette.review : Color.primary)
        }
        .buttonStyle(.plain)
        .padding(.trailing, isSingle ? 0 : 6)
        .help(selectHelp(kind))
    }

    private func rows(for kind: PopoverTab) -> [RowModel] {
        switch kind {
        case .review: visibleReview.map { RowModel.review($0, showsOwner: showsOwner) }
        case .mine: sortedMine.map { RowModel.mine($0, showsOwner: showsOwner) }
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
        Button(action: action) { PillLabel(title: title, symbol: symbol) }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// What a pill shows. Without its title it keeps only the icon, and the title stays for those who cannot see it.
struct PillLabel: View {
    let title: String
    let symbol: String
    var showsTitle = true

    var body: some View {
        Group {
            if showsTitle {
                Label(title, systemImage: symbol)
            } else {
                Image(systemName: symbol).frame(width: 14).accessibilityLabel(title)
            }
        }
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(Palette.review)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Palette.review.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
        .fixedSize()
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

private struct NoMatchesView: View {
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(tr("filter.empty")).font(.system(size: 12.5)).foregroundStyle(.tertiary)
            PillButton(title: tr("filter.clear"), symbol: "xmark", action: onClear)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }
}
