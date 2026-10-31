import Foundation

/// Who decides when the agent wants to do something beyond reading.
public enum ReviewApproval: String, Codable, CaseIterable, Sendable {
    /// Claude Code's auto mode: its classifier decides what is safe, inside limits PRPulse sets. The viewer is only asked
    /// when Claude Code falls back to asking.
    case automatic
    /// Everything beyond reading waits for the viewer's Allow or Deny.
    case ask
}
