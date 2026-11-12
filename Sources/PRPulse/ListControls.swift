import PRPulseCore
import SwiftUI

/// How the viewer ordered each list of the popover.
struct ListSorts: Equatable {
    var review = PullRequestSort.priority
    var mine = PullRequestSort.priority
}

extension PullRequestSort {
    var title: String {
        switch self {
        case .priority: tr("sort.priority")
        case .oldest: tr("sort.oldest")
        case .newest: tr("sort.newest")
        case .activity: tr("sort.activity")
        case .repository: tr("sort.repository")
        case .author: tr("sort.author")
        }
    }
}

/// The one rounded bar the controls above a list live in, split by hairlines. It lights up while the search has the keyboard.
private struct ControlBar<Content: View>: View {
    var isFocused = false
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) { content }
            .frame(height: 32)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isFocused ? Palette.review.opacity(0.7) : Palette.line, lineWidth: isFocused ? 1.5 : 1)
            )
    }
}

private struct BarDivider: View {
    var body: some View {
        Rectangle().fill(Palette.line).frame(width: 1, height: 16)
    }
}

/// Every control in the bar is a 22 point box with its symbol in the middle, set 5 points from the edges of the bar and from
/// its neighbours, so the room around a symbol is the same all round whether or not the box is lit.
private enum BarSlot {
    static let box: CGFloat = 22
    static let margin: CGFloat = 5
    static let radius: CGFloat = 6
}

/// A menu in the bar: a symbol, the name of what it chose when `value` is set, and a tint behind it while it changes the list.
private struct BarMenu<Content: View>: View {
    let symbol: String
    var value: String?
    var isActive = false
    let help: String
    @ViewBuilder let content: Content

    var body: some View {
        Menu {
            content
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                if let value { Text(value).font(.system(size: 12, weight: .semibold)).lineLimit(1) }
            }
            .padding(.horizontal, value == nil ? 0 : 8)
            .frame(minWidth: BarSlot.box, minHeight: BarSlot.box)
            .background(isActive ? Palette.review.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: BarSlot.radius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: BarSlot.radius, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(isActive ? Palette.review : Color.secondary)
        .padding(BarSlot.margin)
        .layoutPriority(2)
        .help(help)
        .accessibilityLabel(value.map { "\(help): \($0)" } ?? help)
    }
}

/// The button that starts choosing several pull requests, when there is no room for it elsewhere.
struct SelectControl {
    let isOn: Bool
    let toggle: () -> Void
}

private struct BarSelect: View {
    let control: SelectControl

    var body: some View {
        Button(action: control.toggle) {
            Image(systemName: control.isOn ? "xmark" : "checklist")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(control.isOn ? Palette.review : Color.secondary)
                .frame(width: BarSlot.box, height: BarSlot.box)
                .background(control.isOn ? Palette.review.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: BarSlot.radius, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: BarSlot.radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(BarSlot.margin)
        .layoutPriority(2)
        .help(control.isOn ? tr("batch.cancel") : tr("batch.help"))
        .accessibilityLabel(control.isOn ? tr("batch.cancel") : tr("batch.select"))
    }
}

private struct BarSearch: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(tr("filter.search.placeholder")).font(.system(size: 12.5)).foregroundStyle(.secondary).allowsHitTesting(false)
                }
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused(isFocused)
                    .onExitCommand(perform: escape)
                    .accessibilityLabel(tr("filter.search.placeholder"))
            }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(tr("filter.search.clear"))
                .accessibilityLabel(tr("filter.search.clear"))
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minWidth: 150)
    }

    /// Escape clears the words first; with none left it closes the popover, as everywhere else.
    private func escape() {
        if text.isEmpty { NSApp.keyWindow?.cancelOperation(nil) } else { text = "" }
    }
}

private struct SortOptions: View {
    let options: [PullRequestSort]
    @Binding var selection: PullRequestSort

    var body: some View {
        ForEach(options, id: \.self) { option in
            Button { selection = option } label: {
                if option == selection { Label(option.title, systemImage: "checkmark") } else { Text(option.title) }
            }
        }
    }
}

private struct ChoiceOptions: View {
    let allTitle: String
    let choices: [ReviewFilter.Choice]
    @Binding var selection: String?
    var display: (String) -> String = { $0 }

    var body: some View {
        Button { selection = nil } label: {
            if selection == nil { Label(allTitle, systemImage: "checkmark") } else { Text(allTitle) }
        }
        Divider()
        ForEach(choices, id: \.value) { choice in
            Button { selection = choice.value } label: {
                let text = "\(display(choice.value))  \(choice.count)"
                if choice.value.caseInsensitiveCompare(selection ?? "") == .orderedSame { Label(text, systemImage: "checkmark") } else { Text(text) }
            }
        }
    }
}

/// What is narrowing or reordering the list, named, each with a way to undo it.
private struct ActiveChip: View {
    let symbol: String
    let text: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
            Text(text).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 14, height: 14).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(tr("filter.remove", text))
            .accessibilityLabel(tr("filter.remove", text))
        }
        .foregroundStyle(Palette.review)
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(height: 24)
        .background(Palette.review.opacity(0.16), in: Capsule())
        .fixedSize()
    }
}

/// What sits above the list of pull requests to review: search, who wrote them, where they live, and the order. What those
/// choose shows below, as chips that can be taken away, with how many pull requests are left.
struct ReviewControls: View {
    let items: [ReviewItem]
    let shown: Int
    @Binding var filter: ReviewFilter
    @Binding var sort: PullRequestSort
    let showsOwner: Bool
    var select: SelectControl?
    @FocusState private var searching: Bool

    var body: some View {
        VStack(spacing: 6) {
            ControlBar(isFocused: searching) {
                BarSearch(text: $filter.query, isFocused: $searching)
                BarDivider()
                BarMenu(symbol: "person", isActive: filter.author != nil, help: tr("filter.author")) {
                    ChoiceOptions(allTitle: tr("filter.author.all"), choices: ReviewFilter.authors(in: items), selection: $filter.author)
                }
                BarDivider()
                BarMenu(symbol: "folder", isActive: filter.repository != nil, help: tr("filter.project")) {
                    ChoiceOptions(allTitle: tr("filter.project.all"), choices: ReviewFilter.repositories(in: items), selection: $filter.repository, display: project)
                }
                BarDivider()
                BarMenu(symbol: "arrow.up.arrow.down", isActive: sort != .priority, help: tr("sort.help")) {
                    SortOptions(options: PullRequestSort.reviewOptions, selection: $sort)
                }
                if let select {
                    BarDivider()
                    BarSelect(control: select)
                }
            }
            if Self.showsChips(filter: filter, sort: sort) { chips }
        }
        .padding(.horizontal, 14)
    }

    /// The room the chips take, so the list below can give up the same height and the popover keep its own.
    static let chipsHeight: CGFloat = 30

    static func showsChips(filter: ReviewFilter, sort: PullRequestSort) -> Bool {
        filter.author != nil || filter.repository != nil || sort != .priority
    }

    private var chips: some View {
        HStack(spacing: 6) {
            if let author = filter.author { ActiveChip(symbol: "person", text: author) { filter.author = nil } }
            if let repository = filter.repository { ActiveChip(symbol: "folder", text: project(repository)) { filter.repository = nil } }
            if sort != .priority { ActiveChip(symbol: "arrow.up.arrow.down", text: sort.title) { sort = .priority } }
            Spacer(minLength: 8)
            if filter.isActive {
                Text(tr("filter.count", shown, items.count)).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
        }
    }

    private func project(_ key: String) -> String {
        showsOwner ? key : String(key.split(separator: "/").last ?? Substring(key))
    }
}

/// What sits above the list of the viewer's own pull requests: the order.
struct MineControls: View {
    @Binding var sort: PullRequestSort

    var body: some View {
        ControlBar {
            BarMenu(symbol: "arrow.up.arrow.down", value: sort.title, help: tr("sort.help")) {
                SortOptions(options: PullRequestSort.mineOptions, selection: $sort)
            }
        }
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 14)
    }
}
