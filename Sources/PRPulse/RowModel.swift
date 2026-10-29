import Foundation
import PRPulseCore
import SwiftUI

/// What one row of the popover shows, already decided so the view only draws.
struct RowModel: Identifiable {
    enum Lead {
        case avatar(String)
        case lane(ActionLane)
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

    var id: PullRequestRef { pr.ref }

    static func review(_ item: ReviewItem) -> RowModel {
        let pr = item.pr
        return RowModel(
            pr: pr,
            lead: .avatar(pr.author.login),
            subtitle: "\(pr.ref.repo) #\(pr.ref.number), \(pr.author.login)",
            chips: reviewChips(item),
            lanes: [.review]
        )
    }

    static func mine(_ item: MineItem) -> RowModel {
        let pr = item.pr
        let primary = item.primary
        var chips = [Chip(id: "primary", text: primary.lane.chipTitle, tone: primary.lane.tone)]
        if item.reasons.count > 1 { chips.append(Chip(id: "more", text: "+\(item.reasons.count - 1)", tone: nil)) }
        return RowModel(
            pr: pr,
            lead: .lane(primary.lane),
            subtitle: "\(pr.ref.repo) #\(pr.ref.number), \(reasonText(primary))",
            chips: chips,
            lanes: Set(item.reasons.map(\.lane))
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
