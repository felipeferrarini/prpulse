import Foundation
import PRPulseCore

struct MascotConfig: Equatable {
    var enabled: Bool
    var packID: String
    var scale: Int

    init(_ settings: AppSettings) {
        enabled = settings.mascotEnabled
        packID = settings.mascotPack
        scale = settings.mascotScale
    }
}

struct MascotState: Equatable {
    var mood: MascotMood
    var count: Int
}

/// Something the mascot says. The id tells one bubble from the next.
struct MascotBubble: Equatable {
    let id = UUID()
    let title: String
    let detail: String?
}
