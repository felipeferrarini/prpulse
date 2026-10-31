import Foundation
import PRPulseCore
import SwiftUI

/// What one row of the popover shows, already decided so the view only draws.
struct RowModel: Identifiable {
    enum Lead {
        case avatar(String)
        case lane(ActionLane)
        case waiting
        /// A whole stack of pull requests.
        case stack
    }

    enum Kind {
        case review, mine, waiting
    }

    struct Chip: Identifiable {
        let id: String
        let text: String
        let tone: Color?
    }

    let pr: PullRequestSnapshot
    let lead: Lead
    let subtitle: String
    let chips: [Chip]
    let lanes: Set<ActionLane>
    let kind: Kind
    /// A repository can be muted from a review row, unless the viewer was asked: those still show when muted.
    let canMute: Bool
    /// Set on the row that stands for a whole stack; `pr` is then the one of its pull requests that has waited longest.
    var group: StackKey?
    var memberCount = 1
    /// `2/7` on a pull request that is in a stack.
    var stackBadge: String?
    var titleOverride: String?

    var id: PullRequestRef { pr.ref }
    var title: String { titleOverride ?? pr.title }
    var isStack: Bool { group != nil }

    private static func badge(of pr: PullRequestSnapshot) -> String? {
        pr.stack.map { "\($0.position)/\($0.size)" }
    }

    private static func repository(_ pr: PullRequestSnapshot, showsOwner: Bool) -> String {
        showsOwner ? "\(pr.ref.owner)/\(pr.ref.repo)" : pr.ref.repo
    }

    static func review(_ item: ReviewItem, showsOwner: Bool = false) -> RowModel {
        let pr = item.pr
        return RowModel(
            pr: pr,
            lead: .avatar(pr.author.login),
            subtitle: "\(repository(pr, showsOwner: showsOwner)) #\(pr.ref.number), \(pr.author.login)",
            chips: reviewChips(item),
            lanes: [.review],
            kind: .review,
            canMute: !item.isRequested,
            stackBadge: badge(of: pr)
        )
    }

    static func waiting(_ item: WaitingItem, showsOwner: Bool = false) -> RowModel {
        let pr = item.pr
        let who = pr.requestedReviewers.isEmpty
            ? tr("reason.waiting.nobody")
            : tr("reason.waiting.on", pr.requestedReviewers.prefix(2).joined(separator: ", "))
        return RowModel(
            pr: pr,
            lead: .waiting,
            subtitle: "\(repository(pr, showsOwner: showsOwner)) #\(pr.ref.number), \(who)",
            chips: [Chip(id: "noreview", text: tr("chip.noReview"), tone: nil)],
            lanes: [],
            kind: .waiting,
            canMute: false
        )
    }

    static func mine(_ item: MineItem, showsOwner: Bool = false) -> RowModel {
        let pr = item.pr
        let primary = item.primary
        var chips = [Chip(id: "primary", text: primary.lane.chipTitle, tone: primary.lane.tone)]
        if item.reasons.count > 1 { chips.append(Chip(id: "more", text: "+\(item.reasons.count - 1)", tone: nil)) }
        return RowModel(
            pr: pr,
            lead: .lane(primary.lane),
            subtitle: "\(repository(pr, showsOwner: showsOwner)) #\(pr.ref.number), \(reasonText(primary))",
            chips: chips,
            lanes: Set(item.reasons.map(\.lane)),
            kind: .mine,
            canMute: false,
            stackBadge: badge(of: pr)
        )
    }

    /// The row of a stack: its first pull request gives the title, and it says how many there are and what asks for the viewer.
    static func stack(_ group: StackGroup<RowModel>, showsOwner: Bool = false) -> RowModel {
        let rows = group.items
        let bottom = group.bottom
        let name = repository(bottom, showsOwner: showsOwner)
        let count = group.members.count
        let subtitle = group.isComplete
            ? tr("stack.subtitle", name, count, bottom.author.login)
            : tr("stack.subtitle.partial", name, count, group.size, bottom.author.login)
        var chips = [Chip(id: "stack", text: tr("chip.stack", count), tone: nil)]
        if rows.contains(where: { $0.chips.contains { $0.id == "requested" } }) {
            chips.append(Chip(id: "requested", text: tr("chip.requested"), tone: Palette.review))
        } else if let lane = ActionLane.allCases.first(where: { lane in rows.contains { $0.kind == .mine && $0.lanes.contains(lane) } }) {
            chips.append(Chip(id: "lane", text: lane.chipTitle, tone: lane.tone))
        }
        return RowModel(
            pr: group.oldest,
            lead: .stack,
            subtitle: subtitle,
            chips: chips,
            lanes: rows.reduce(into: Set<ActionLane>()) { $0.formUnion($1.lanes) },
            kind: rows[0].kind,
            canMute: false,
            group: group.key,
            memberCount: count,
            titleOverride: bottom.title
        )
    }

    private static func reviewChips(_ item: ReviewItem) -> [Chip] {
        if item.pr.isDraft { return [Chip(id: "draft", text: tr("chip.draft"), tone: nil)] }
        if item.isRequested { return [Chip(id: "requested", text: tr("chip.requested"), tone: Palette.review)] }
        return [Chip(id: "team", text: tr("chip.team"), tone: nil)]
    }

    private static func reasonText(_ reason: MineReason) -> String {
        let text: String = switch reason {
        case .changesRequested: tr("reason.changesRequested")
        case .openThreads(let count): count == 1 ? tr("reason.openThreads.one") : tr("reason.openThreads.other", count)
        case .unansweredComment: tr("reason.unansweredComment")
        case .ciFailed: tr("reason.ciFailed")
        case .conflict: tr("reason.conflict")
        case .readyToMerge: tr("reason.readyToMerge")
        }
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

extension Waiting {
    var text: String {
        switch unit {
        case .now: tr("wait.now")
        case .hours: tr("wait.hours", value)
        case .days: tr("wait.days", value)
        }
    }
}
