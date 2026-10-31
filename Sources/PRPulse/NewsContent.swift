import PRPulseCore
import SwiftUI

/// What changed in each version of the app, read from the changelog that ships with it.
struct NewsContent: View {
    let releases: [ChangelogRelease]

    @LocalState private var opened: Set<String> = []

    init(releases: [ChangelogRelease] = NewsContent.bundledReleases()) {
        self.releases = releases
    }

    static func bundledReleases() -> [ChangelogRelease] {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Changelog.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let latest = releases.first {
                versionLine(latest).staggered(2)
                sections(of: latest).staggered(3)
                earlier.staggered(4)
            } else {
                Text(tr("news.unavailable")).font(.system(size: 13.5)).foregroundStyle(WizardPalette.ink2)
            }
        }
    }

    // MARK: Releases

    private func versionLine(_ release: ChangelogRelease) -> some View {
        Text(Self.label(of: release))
            .font(.system(size: 12.5).monospacedDigit())
            .foregroundStyle(WizardPalette.ink3)
            .padding(.bottom, 4)
    }

    private func sections(of release: ChangelogRelease) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(release.sections, id: \.title) { section in
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.title(of: section))
                        .font(.system(size: 11.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(WizardPalette.ink3)
                        .padding(.bottom, 4)
                    ForEach(section.items, id: \.self) { item in row(item, symbol: Self.symbol(of: section)) }
                }
            }
        }
        .padding(.top, 14)
    }

    @ViewBuilder private var earlier: some View {
        if releases.count > 1 {
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("news.earlier"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WizardPalette.ink)
                    .padding(.bottom, 6)
                ForEach(releases.dropFirst()) { release in disclosure(release) }
            }
            .padding(.top, 30)
        }
    }

    private func disclosure(_ release: ChangelogRelease) -> some View {
        DisclosureGroup(isExpanded: binding(for: release.version)) {
            sections(of: release).padding(.bottom, 10)
        } label: {
            Text(Self.label(of: release))
                .font(.system(size: 13.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(WizardPalette.ink2)
        }
        .padding(.vertical, 6)
    }

    private func binding(for version: String) -> Binding<Bool> {
        Binding(
            get: { opened.contains(version) },
            set: { isOpen in
                if isOpen { opened.insert(version) } else { opened.remove(version) }
            }
        )
    }

    private func row(_ text: String, symbol: String) -> some View {
        let parts = Self.split(text)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WizardPalette.accent)
                .frame(width: 20, height: 20)
                .background(WizardPalette.soft, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                if let lead = parts.lead {
                    Text(lead).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(WizardPalette.ink)
                }
                if !parts.body.isEmpty {
                    Text(Self.formatted(parts.body))
                        .font(.system(size: 13))
                        .foregroundStyle(parts.lead == nil ? WizardPalette.ink : WizardPalette.ink2)
                }
            }
            .lineSpacing(3)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }

    // MARK: Words

    static func label(of release: ChangelogRelease) -> String {
        release.date.map { "v\(release.version) · \($0)" } ?? "v\(release.version)"
    }

    private static func title(of section: ChangelogSection) -> String {
        switch section.title.lowercased() {
        case "added": tr("news.added")
        case "changed": tr("news.changed")
        case "fixed": tr("news.fixed")
        case "notes": tr("news.notes")
        default: section.title
        }
    }

    private static func symbol(of section: ChangelogSection) -> String {
        switch section.title.lowercased() {
        case "added": "plus"
        case "changed": "arrow.triangle.2.circlepath"
        case "fixed": "wrench.adjustable"
        default: "info"
        }
    }

    /// An item that opens with a bold phrase gives it as a lead: `**Follow-ups.** More text` is `Follow-ups.` and `More text`.
    static func split(_ item: String) -> (lead: String?, body: String) {
        guard item.hasPrefix("**"), let close = item.range(of: "**", range: item.index(item.startIndex, offsetBy: 2) ..< item.endIndex) else {
            return (nil, item)
        }
        let lead = String(item[item.index(item.startIndex, offsetBy: 2) ..< close.lowerBound])
        return (lead, String(item[close.upperBound...]).trimmingCharacters(in: .whitespaces))
    }

    /// Markdown for the parts a line can show: bold and code.
    private static func formatted(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
