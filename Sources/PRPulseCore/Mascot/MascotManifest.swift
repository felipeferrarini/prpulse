import Foundation

/// The `mascot.json` of a mascot pack: a sprite sheet with one row per mood and one column per frame.
public struct MascotManifest: Codable, Equatable, Sendable {
    public struct FrameSize: Codable, Equatable, Sendable {
        public let width: Int
        public let height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }
    }

    public struct Clip: Codable, Equatable, Sendable {
        public let row: Int
        public let frames: Int

        public init(row: Int, frames: Int) {
            self.row = row
            self.frames = frames
        }
    }

    public enum Problem: Error, Equatable {
        case badFrameSize
        case badFramesPerSecond
        case missingCalm
        case clipOutsideSheet(String)
    }

    public static let framesPerSecondRange = 1 ... 30

    public let name: String
    public let author: String?
    public let frame: FrameSize
    public let fps: Int
    public let states: [String: Clip]

    public init(name: String, author: String? = nil, frame: FrameSize, fps: Int, states: [String: Clip]) {
        self.name = name
        self.author = author
        self.frame = frame
        self.fps = fps
        self.states = states
    }

    /// Checks the manifest against the size of its image. Moods the app does not know are ignored.
    public func validate(sheetWidth: Int, sheetHeight: Int) throws {
        guard frame.width > 0, frame.height > 0 else { throw Problem.badFrameSize }
        guard Self.framesPerSecondRange.contains(fps) else { throw Problem.badFramesPerSecond }
        guard states[MascotMood.calm.rawValue] != nil else { throw Problem.missingCalm }
        for mood in MascotMood.allCases {
            guard let clip = states[mood.rawValue] else { continue }
            let fits = clip.row >= 0 && clip.frames >= 1
                && (clip.row + 1) * frame.height <= sheetHeight
                && clip.frames * frame.width <= sheetWidth
            if !fits { throw Problem.clipOutsideSheet(mood.rawValue) }
        }
    }

    /// The clip for a mood, falling back to calm when the pack does not draw it.
    public func clip(for mood: MascotMood) -> Clip {
        states[mood.rawValue] ?? states[MascotMood.calm.rawValue] ?? Clip(row: 0, frames: 1)
    }
}
