import PRPulseCore
import SwiftUI

struct PopoverView: View {
    let data: ViewData
    let onRefresh: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if data.isOffline { banner(data.summary == nil ? tr("popover.offline.noData") : tr("popover.offline")) }
            content
            Divider()
            footer
        }
        .frame(width: 420)
    }

    @ViewBuilder private var content: some View {
        if !data.isSetupComplete {
            FailureView(failure: .notConfigured, onSettings: onSettings)
        } else {
            stateContent
        }
    }

    @ViewBuilder private var stateContent: some View {
        switch data.state {
        case .failed(let failure):
            FailureView(failure: failure, onSettings: onSettings)
        default:
            if let summary = data.summary {
                summaryContent(summary)
            } else {
                placeholder
            }
        }
    }

    @ViewBuilder private func summaryContent(_ summary: Summary) -> some View {
        if summary.total == 0 {
            EmptyStateView()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !summary.mine.isEmpty { mineSection(summary.mine) }
                    if !summary.review.isEmpty { reviewSection(summary.review) }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 460)
        }
    }

    private func mineSection(_ items: [MineItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: tr("popover.mine"), count: items.count)
            ForEach(items, id: \.pr.ref) { item in
                PullRequestRow(pr: item.pr, chips: item.reasons.map(ReasonChip.make), detail: nil)
            }
        }
    }

    private func reviewSection(_ items: [ReviewItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: tr("popover.review"), count: items.count)
            ForEach(items, id: \.pr.ref) { item in
                PullRequestRow(pr: item.pr, chips: reviewChips(item.pr), detail: reviewDetail(item.pr))
            }
        }
    }

    private func reviewChips(_ pr: PullRequestSnapshot) -> [ReasonChip] {
        pr.isDraft ? [.needsReview, .draft] : [.needsReview]
    }

    private func reviewDetail(_ pr: PullRequestSnapshot) -> String {
        let age = RelativeDateTimeFormatter().localizedString(for: pr.createdAt, relativeTo: Date())
        return "\(pr.author.login) · \(age)"
    }

    private var placeholder: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(tr("popover.loading")).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 90)
    }

    private func banner(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.yellow.opacity(0.18))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let updated = data.lastUpdated {
                Text(tr("popover.updated", updated.formatted(date: .omitted, time: .shortened)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            FooterButton(symbol: "arrow.clockwise", help: tr("popover.refresh"), action: onRefresh)
                .keyboardShortcut("r")
            FooterButton(symbol: "gearshape", help: tr("popover.settings"), action: onSettings)
            FooterButton(symbol: "power", help: tr("popover.quit")) { NSApplication.shared.terminate(nil) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct SectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        Text("\(title) · \(count)")
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }
}

private struct FooterButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.borderless)
            .help(help)
    }
}

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle").font(.largeTitle).foregroundStyle(.green)
            Text(tr("popover.empty.title")).font(.headline)
            Text(tr("popover.empty.body")).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 130)
    }
}

private struct FailureView: View {
    let failure: AppFailure
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").font(.title).foregroundStyle(.red)
            Text(title).font(.headline)
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(tr("error.openSettings"), action: onSettings)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }

    private var title: String {
        switch failure {
        case .unauthenticated: tr("error.unauthenticated.title")
        case .ssoRequired: tr("error.sso.title")
        case .notConfigured: tr("error.notConfigured.title")
        case .organizationNotAccessible: tr("error.org.title")
        }
    }

    private var message: String {
        switch failure {
        case .unauthenticated: tr("error.unauthenticated.body")
        case .ssoRequired: tr("error.sso.body")
        case .notConfigured: tr("error.notConfigured.body")
        case .organizationNotAccessible(let org): tr("error.org.body", org)
        }
    }
}
