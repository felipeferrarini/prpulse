import PRPulseCore
import SwiftUI

/// The left half of the wizard: a live miniature of the popover that reacts to every choice.
struct WizardStage: View {
    @ObservedObject var model: SetupModel
    let step: SetupStep
    let slide: Int

    private var showsIcon: Bool { step == .welcome && slide == 0 }
    private var isConnected: Bool { step.rawValue >= SetupStep.organization.rawValue }
    private var showsToast: Bool { step.rawValue >= SetupStep.general.rawValue && model.draft.notificationsEnabled && isConnected }

    private var rows: [StageRow] {
        StageRow.samples(repositories: model.repositoryShortNames)
            .filter { !model.draft.ignoredRepos.contains($0.repo) || $0.requested }
    }

    var body: some View {
        ZStack(alignment: .top) {
            background
            MenuBarStrip(count: isConnected ? rows.count : 3, highlighted: showsIcon)
            BigIcon(count: isConnected ? rows.count : 3, isActive: showsIcon)
                .opacity(showsIcon ? 1 : 0)
                .offset(y: showsIcon ? 0 : -10)
                .frame(maxHeight: .infinity, alignment: .center)
                .padding(.bottom, 70)
            MiniPopover(org: OrganizationLabel.text(for: model.draft.orgs), rows: rows, isConnected: isConnected, interval: model.draft.refreshMinutes)
                .padding(.top, 56)
                .opacity(showsIcon ? 0 : 1)
                .offset(y: showsIcon ? 26 : 0)
                .scaleEffect(showsIcon ? 0.92 : 1, anchor: .top)
            Toast(count: rows.count, title: rows.first?.title ?? "")
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 118)
                .opacity(showsToast ? 1 : 0)
                .offset(y: showsToast ? 0 : 24)
            Caption(step: step, slide: slide)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(28)
        }
        .animation(.spring(response: 0.8, dampingFraction: 0.78), value: showsIcon)
        .animation(.spring(response: 0.7, dampingFraction: 0.8), value: showsToast)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: rows.map(\.id))
        .clipped()
    }

    private var background: some View {
        ZStack {
            WizardPalette.stageBase
            RadialGradient(colors: [WizardPalette.stageGlow.opacity(0.4), .clear], center: .topLeading, startRadius: 0, endRadius: 360)
            RadialGradient(colors: [WizardPalette.stageIndigo.opacity(0.32), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 380)
        }
    }
}

struct StageRow: Identifiable, Equatable {
    let id: Int
    let repo: String
    let title: String
    let who: String
    let age: String
    let requested: Bool
    let color: Color

    private static let fallbackRepos = ["web", "api", "docs", "infra", "mobile"]

    static func samples(repositories: [String]) -> [StageRow] {
        let repos = repositories.count >= 5 ? Array(repositories.prefix(5)) : fallbackRepos
        let template: [(String, String, String, Bool, UInt32)] = [
            ("Per-tenant session cache", "sam", "3d", true, 0xBB99FF),
            ("Fix pagination on /invoices", "mia", "7h", true, 0xFF8577),
            ("Onboarding guide v2", "noor", "4h", false, 0x52CF92),
            ("Remove the old backup job", "ivan", "5d", false, 0xF0C14B),
            ("Offline upload queue", "leo", "1d", false, 0x8AA4FF),
        ]
        return template.enumerated().map { index, item in
            StageRow(
                id: index, repo: repos[index], title: item.0, who: item.1, age: item.2, requested: item.3,
                color: Color(nsColor: NSColor(hex: item.4))
            )
        }
    }
}

private struct MenuBarStrip: View {
    let count: Int
    let highlighted: Bool

    var body: some View {
        HStack(spacing: 14) {
            Spacer()
            Text(Date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
            Text(Date().formatted(date: .omitted, time: .shortened))
            // The very image the menu bar shows.
            Image(nsImage: StatusIconRenderer.image(for: .pending(count), phase: 0))
                .background {
                    RippleRings(isActive: highlighted, rings: 1, period: 3, growth: 0.45, peakOpacity: 0.6, lineWidth: 2)
                        .padding(4)
                }
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.white.opacity(0.8))
        .padding(.horizontal, 16)
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.06))
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct BigIcon: View {
    let count: Int
    let isActive: Bool

    private static let height: CGFloat = 76

    var body: some View {
        BrandPill(count: count, height: Self.height)
            .shadow(color: WizardPalette.brandOrange.opacity(0.45), radius: 26)
            .background {
                RippleRings(isActive: isActive, rings: 1, period: 4.5, growth: 1.1, peakOpacity: 0.6, lineWidth: 2)
            }
            .accessibilityHidden(true)
    }
}

/// Outlines that leave a shape and spread outward while they fade, like the menu bar icon does for a new item.
/// They follow the clock instead of an implicit animation, so they always start on the shape they surround, and
/// the clock stops while they are hidden.
private struct RippleRings: View {
    let isActive: Bool
    let rings: Int
    let period: Double
    /// How much bigger than the shape a ring gets before it vanishes (1 is twice the size).
    let growth: Double
    let peakOpacity: Double
    let lineWidth: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isActive)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0 ..< rings, id: \.self) { index in
                    let phase = (time / period + Double(index) / Double(rings)).truncatingRemainder(dividingBy: 1)
                    let eased = 1 - pow(1 - phase, 2)
                    Capsule(style: .circular)
                        .stroke(Color(nsColor: BrandIcon.orangeTop), lineWidth: lineWidth)
                        .scaleEffect(1 + growth * eased)
                        .opacity(isActive ? peakOpacity * (1 - phase) : 0)
                }
            }
        }
    }
}

private struct MiniPopover: View {
    let org: String
    let rows: [StageRow]
    let isConnected: Bool
    let interval: Int

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: 0) {
                if isConnected {
                    ForEach(rows) { row in
                        MiniRow(row: row)
                            .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .opacity))
                    }
                } else {
                    ForEach(0 ..< 4, id: \.self) { _ in SkeletonRow() }
                }
            }
            .frame(minHeight: 236, alignment: .top)
            .padding(.bottom, 6)
            footer
        }
        .frame(width: 310)
        .background(Color(nsColor: NSColor(hex: 0x20212A)).opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 18)
        .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(spacing: 8) {
            BrandGlyph(size: 12, color: Color(nsColor: NSColor(hex: 0x17181F)))
                .frame(width: 20, height: 20)
                .background(Color(nsColor: NSColor(hex: 0xF3F4F7)), in: RoundedRectangle(cornerRadius: 6))
            Text(org.isEmpty ? tr("wizard.stage.org") : org)
                .font(.system(size: 12.5, weight: org.isEmpty ? .medium : .semibold))
                .foregroundStyle(org.isEmpty ? Color.white.opacity(0.45) : .white)
            if isConnected {
                Text(tr("popover.pending.other", rows.count)).font(.system(size: 12.5)).foregroundStyle(Color.white.opacity(0.6))
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var footer: some View {
        HStack {
            Text(tr("wizard.stage.updated"))
            Spacer()
            Text(tr("wizard.stage.interval", interval)).fontWeight(.semibold).foregroundStyle(Color.white.opacity(0.8))
        }
        .font(.system(size: 10.5))
        .foregroundStyle(Color.white.opacity(0.55))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
    }
}

private struct MiniRow: View {
    let row: StageRow

    var body: some View {
        HStack(spacing: 9) {
            Text(row.who.prefix(1).uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(nsColor: NSColor(hex: 0x10131A)))
                .frame(width: 22, height: 22)
                .background(row.color, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                Text("\(row.repo), \(row.who)").font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.55))
            }
            Spacer(minLength: 4)
            Text(row.requested ? tr("chip.requested") : row.age)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(row.requested ? Color(nsColor: NSColor(hex: 0x9DB4FF)) : Color.white.opacity(0.6))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background((row.requested ? Color(nsColor: NSColor(hex: 0x8AA4FF)) : Color.white).opacity(row.requested ? 0.18 : 0.08), in: RoundedRectangle(cornerRadius: 5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}

private struct SkeletonRow: View {
    @LocalState private var shimmer = false

    var body: some View {
        HStack(spacing: 9) {
            Circle().fill(Color.white.opacity(0.08)).frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 6) {
                bar(width: 200)
                bar(width: 110)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .opacity(shimmer ? 1 : 0.55)
        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: shimmer)
        .onAppear { shimmer = true }
    }

    private func bar(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.1)).frame(width: width, height: 9)
    }
}

private struct Toast: View {
    let count: Int
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            BrandGlyph(size: 18)
                .frame(width: 34, height: 34)
                .background(
                    LinearGradient(colors: [Color(nsColor: BrandIcon.orangeTop), Color(nsColor: BrandIcon.orangeBottom)], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 9)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(tr("notification.title.other", count)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                Text(title).font(.system(size: 11.5)).foregroundStyle(Color.white.opacity(0.65)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(width: 290)
        .background(Color(nsColor: NSColor(hex: 0x30323E)).opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
        .accessibilityHidden(true)
    }
}

private struct Caption: View {
    let step: SetupStep
    let slide: Int

    var body: some View {
        let text = captionText
        VStack(alignment: .leading, spacing: 2) {
            Text(text.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            Text(text.body).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 270, alignment: .leading)
        .id("\(step.rawValue)-\(slide)")
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.4), value: step)
        .animation(.easeInOut(duration: 0.4), value: slide)
    }

    private var captionText: (title: String, body: String) {
        switch step {
        case .welcome:
            switch slide {
            case 0: (tr("wizard.cap.icon.title"), tr("wizard.cap.icon.body"))
            case 1: (tr("wizard.cap.list.title"), tr("wizard.cap.list.body"))
            default: (tr("wizard.cap.quiet.title"), tr("wizard.cap.quiet.body"))
            }
        case .connect: (tr("wizard.cap.connect.title"), tr("wizard.cap.connect.body"))
        case .organization: (tr("wizard.cap.org.title"), tr("wizard.cap.org.body"))
        case .exceptions: (tr("wizard.cap.exceptions.title"), tr("wizard.cap.exceptions.body"))
        case .general: (tr("wizard.cap.general.title"), tr("wizard.cap.general.body"))
        case .done: (tr("wizard.cap.done.title"), tr("wizard.cap.done.body"))
        }
    }
}
