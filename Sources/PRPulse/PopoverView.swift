import PRPulseCore
import SwiftUI

struct PopoverView: View {
    let data: ViewData
    @Binding var layout: PopoverLayout
    var openToken = 0
    var onMute: (PullRequestRef) -> Void = { _ in }
    /// The live popover is built anew each time it opens, so it plays its entrance when it appears.
    var entersOnAppear = false
    let onRefresh: () -> Void
    let onSettings: () -> Void

    @LocalState private var tab: PopoverTab
    @LocalState private var filter: ActionLane?
    @LocalState private var entered = true

    init(
        data: ViewData,
        layout: Binding<PopoverLayout>,
        openToken: Int = 0,
        onMute: @escaping (PullRequestRef) -> Void = { _ in },
        entersOnAppear: Bool = false,
        initialTab: PopoverTab = .review,
        initialFilter: ActionLane? = nil,
        onRefresh: @escaping () -> Void,
        onSettings: @escaping () -> Void
    ) {
        self.data = data
        _layout = layout
        self.openToken = openToken
        self.onMute = onMute
        self.entersOnAppear = entersOnAppear
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
            if summary.total == 0 && summary.waiting.isEmpty {
                EmptyStateView()
            } else {
                TabSegment(tab: $tab, reviewCount: summary.review.count, mineCount: summary.mine.count)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .folded(!isSingle, height: 50)
                LaneFilterBar(lanes: summary.activeLanes, summary: summary, selection: laneSelection(summary))
                    .padding(.bottom, 12)
                SummaryPanes(summary: summary, layout: layout, tab: tab, filter: filter, entered: entered, showsOwner: data.showsOwner, onMute: onMute)
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
    let entered: Bool
    let showsOwner: Bool
    let onMute: (PullRequestRef) -> Void

    @LocalState private var heights: [PopoverTab: CGFloat] = [:]

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
    }

    private func pane(_ kind: PopoverTab) -> some View {
        let rows = rows(for: kind)
        let hidden = isSingle && tab != kind
        return VStack(spacing: 0) {
            paneHeader(kind).folded(isSingle, height: Self.paneHeaderHeight)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        PullRequestRow(model: row, isDimmed: isDimmed(row), entranceIndex: index, entered: entered, onMute: { onMute(row.pr.ref) })
                    }
                    if kind == .mine && !summary.waiting.isEmpty { waitingSection(startIndex: rows.count) }
                    if rows.isEmpty && !(kind == .mine && !summary.waiting.isEmpty) { PaneEmptyText() }
                }
                .padding(.vertical, 4)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: PaneHeightKey.self, value: [kind: proxy.size.height])
                })
            }
            .frame(height: listHeight)
        }
        .accessibilityHidden(hidden)
        .allowsHitTesting(!hidden)
    }

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
            Text(isReview ? tr("popover.pane.review.count", summary.review.count) : tr("popover.pane.mine.count", summary.mine.count))
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(height: Self.paneHeaderHeight, alignment: .center)
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

private struct PaneEmptyText: View {
    var body: some View {
        Text(tr("popover.pane.empty"))
            .font(.system(size: 12.5))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, minHeight: 100)
    }
}
