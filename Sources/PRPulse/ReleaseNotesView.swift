import PRPulseCore
import SwiftUI

/// The window an update opens: what changed since the last version the viewer was shown.
struct ReleaseNotesView: View {
    let releases: [ChangelogRelease]
    let onShowAfterUpdate: (Bool) -> Void
    let onClose: () -> Void

    @LocalState private var showAfterUpdate: Bool

    static let size = CGSize(width: 580, height: 660)

    init(
        releases: [ChangelogRelease],
        showAfterUpdate: Bool,
        onShowAfterUpdate: @escaping (Bool) -> Void = { _ in },
        onClose: @escaping () -> Void = {}
    ) {
        self.releases = releases
        self.onShowAfterUpdate = onShowAfterUpdate
        self.onClose = onClose
        _showAfterUpdate = LocalState(initialValue: showAfterUpdate)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header.staggered(0)
                    NewsContent(releases: releases, earlierTitle: tr("news.alsoInUpdate"))
                        .padding(.top, 22)
                }
                .padding(.horizontal, 40)
                .padding(.top, 38)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollBounceBehavior(.basedOnSize)
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .borderlessWindowChrome()
        .overlay(alignment: .topTrailing) {
            WindowCloseButton(action: onClose).padding(.top, 14).padding(.trailing, 14)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            badge
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("news.window.title", releases.first?.version ?? ""))
                    .font(.system(size: 25, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(WizardPalette.ink)
                Text(tr("news.window.lead"))
                    .font(.system(size: 14))
                    .foregroundStyle(WizardPalette.ink2)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The app icon the menu bar draws, as a tile.
    private var badge: some View {
        BrandGlyph(size: 30)
            .frame(width: 62, height: 62)
            .background(
                LinearGradient(
                    colors: [Color(nsColor: BrandIcon.orangeTop), Color(nsColor: BrandIcon.orangeBottom)],
                    startPoint: .top, endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5))
            .shadow(color: WizardPalette.brandOrange.opacity(0.4), radius: 14, y: 4)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Toggle(tr("news.option.title"), isOn: $showAfterUpdate)
                .toggleStyle(WizardSwitchStyle())
                .labelsHidden()
            Text(tr("news.option.title")).font(.system(size: 13)).foregroundStyle(WizardPalette.ink2)
            Spacer()
            Button(tr("news.window.done"), action: onClose)
                .buttonStyle(WizardPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 40)
        .padding(.top, 14)
        .padding(.bottom, 22)
        .overlay(alignment: .top) { Rectangle().fill(WizardPalette.line).frame(height: 1) }
        .onChange(of: showAfterUpdate) { _, isOn in onShowAfterUpdate(isOn) }
    }
}
