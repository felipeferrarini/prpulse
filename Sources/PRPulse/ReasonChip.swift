import PRPulseCore
import SwiftUI

struct ReasonChip: Identifiable {
    let id: String
    let text: String
    let color: Color

    static func make(_ reason: MineReason) -> ReasonChip {
        ReasonChip(id: reason.kind, text: label(reason), color: color(reason))
    }

    static let needsReview = ReasonChip(id: "needsReview", text: tr("reason.needsReview"), color: .blue)
    static let draft = ReasonChip(id: "draft", text: tr("reason.draft"), color: .gray)

    private static func label(_ reason: MineReason) -> String {
        switch reason {
        case .changesRequested: tr("reason.changesRequested")
        case .openThreads(let count): count == 1 ? tr("reason.openThreads.one") : tr("reason.openThreads.other", count)
        case .unansweredComment: tr("reason.unansweredComment")
        case .ciFailed: tr("reason.ciFailed")
        case .conflict: tr("reason.conflict")
        case .readyToMerge: tr("reason.readyToMerge")
        }
    }

    private static func color(_ reason: MineReason) -> Color {
        switch reason {
        case .changesRequested, .ciFailed: .red
        case .openThreads, .unansweredComment: .orange
        case .conflict: .yellow
        case .readyToMerge: .green
        }
    }
}
