import AppKit
import PRPulseCore
import SwiftUI

struct DiagnosticsContent: View {
    let report: () -> DiagnosticsReport

    @LocalState private var copied = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let current = report()
            VStack(spacing: 0) {
                ForEach(Array(rows(for: current, now: context.date).enumerated()), id: \.offset) { index, row in
                    line(row).staggered(index + 1)
                }
                copyRow(current, now: context.date).staggered(12)
            }
        }
    }

    private struct Row {
        let title: String
        let value: String
        var tone: Tone = .plain

        enum Tone { case plain, good, bad }
    }

    private func rows(for report: DiagnosticsReport, now: Date) -> [Row] {
        [
            Row(title: tr("diag.version"), value: report.appVersion),
            Row(title: tr("diag.system"), value: "macOS \(report.systemVersion)"),
            Row(title: tr("diag.signin"), value: report.authSource == .ghCli ? tr("diag.signin.gh") : tr("diag.signin.token")),
            Row(title: tr("diag.orgs"), value: "\(report.organizationCount)"),
            Row(title: tr("diag.refresh"), value: tr("setup.general.minutes", report.refreshMinutes)),
            statusRow(report),
            Row(title: tr("diag.sync"), value: lastSyncText(report.lastSync, now: now)),
            Row(title: tr("diag.counts"), value: tr("diag.counts.value", report.reviewCount, report.mineCount)),
            Row(title: tr("diag.rate"), value: rateText(report.rateLimit, now: now)),
            Row(title: tr("diag.shortcut"), value: report.shortcutActive ? GlobalShortcut.display : tr("diag.off")),
            Row(title: tr("diag.updates"), value: report.automaticUpdates ? tr("diag.on") : tr("diag.off")),
        ]
    }

    private func statusRow(_ report: DiagnosticsReport) -> Row {
        switch report.status {
        case .neverSynced: Row(title: tr("diag.status"), value: tr("diag.status.never"))
        case .ok: Row(title: tr("diag.status"), value: tr("diag.status.ok"), tone: .good)
        case .offline: Row(title: tr("diag.status"), value: tr("diag.status.offline"), tone: .bad)
        case .failed(let reason): Row(title: tr("diag.status"), value: tr("diag.status.failed", reason), tone: .bad)
        }
    }

    private func lastSyncText(_ date: Date?, now: Date) -> String {
        guard let date else { return tr("diag.never") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }

    private func rateText(_ rateLimit: RateLimit?, now: Date) -> String {
        guard let rateLimit else { return "—" }
        let minutes = max(Int(rateLimit.resetsAt.timeIntervalSince(now)) / 60, 0)
        return tr("diag.rate.value", rateLimit.remaining, rateLimit.limit, minutes)
    }

    private func line(_ row: Row) -> some View {
        HStack(spacing: 8) {
            Text(row.title).font(.system(size: 13.5)).foregroundStyle(WizardPalette.ink2)
            Spacer()
            if row.tone != .plain {
                Circle().fill(row.tone == .good ? WizardPalette.success : WizardPalette.danger).frame(width: 7, height: 7)
            }
            Text(row.value).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(WizardPalette.ink)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Rectangle().fill(WizardPalette.line).frame(height: 1) }
    }

    private func copyRow(_ report: DiagnosticsReport, now: Date) -> some View {
        HStack {
            Text(tr("diag.copy.detail")).font(.system(size: 12.5)).foregroundStyle(WizardPalette.ink2)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(report.text(now: now), forType: .string)
                withAnimation(.easeOut(duration: 0.2)) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { copied = false } }
            } label: {
                Label(copied ? tr("diag.copied") : tr("diag.copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WizardPalette.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 16)
    }
}
