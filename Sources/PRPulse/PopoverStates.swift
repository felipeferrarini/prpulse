import PRPulseCore
import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Palette.merge)
                .frame(width: 64, height: 64)
                .background(Palette.merge.opacity(0.14), in: Circle())
                .padding(.bottom, 8)
            Text(tr("popover.empty.title")).font(.headline)
            Text(tr("popover.empty.body")).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 190)
        .padding(.horizontal, 24)
    }
}

struct LoadingStateView: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(tr("popover.loading")).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
    }
}

struct OfflineBanner: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Palette.conflict.opacity(0.16))
    }
}

struct FailureView: View {
    let failure: AppFailure
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").font(.title).foregroundStyle(Palette.changes)
            Text(title).font(.headline)
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(tr("error.openSettings"), action: onSettings)
        }
        .padding(24)
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

struct PopoverFooter: View {
    let lastUpdated: Date?
    let onRefresh: () -> Void
    let onSettings: () -> Void

    @LocalState private var turns = 0.0

    var body: some View {
        HStack(spacing: 8) {
            if let lastUpdated {
                Circle().fill(Palette.merge).frame(width: 7, height: 7).accessibilityHidden(true)
                Text(tr("popover.updated", lastUpdated.formatted(date: .omitted, time: .shortened)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            button("arrow.clockwise", help: tr("popover.refresh")) {
                withAnimation(.easeOut(duration: 0.8)) { turns += 360 }
                onRefresh()
            }
            .rotationEffect(.degrees(turns))
            .keyboardShortcut("r")
            button("slider.horizontal.3", help: tr("popover.settings"), action: onSettings)
            button("power", help: tr("popover.quit")) { NSApplication.shared.terminate(nil) }
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .padding(.vertical, 7)
    }

    private func button(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        FooterButton(symbol: symbol, help: help, action: action)
    }
}

private struct FooterButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    @LocalState private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(isHovering ? Color.primary : .secondary)
                .frame(width: 30, height: 28)
                .background(isHovering ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}
