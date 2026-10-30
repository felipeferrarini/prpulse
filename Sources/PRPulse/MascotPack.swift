import AppKit
import PRPulseCore

/// A mascot the app knows about, before its sprites are loaded.
struct MascotInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let directory: URL
    let isBuiltIn: Bool
}

/// A loaded mascot: the frames of every mood it draws, ready to play.
struct MascotPack {
    enum LoadError: Error {
        case unreadable
        case invalid(MascotManifest.Problem)
    }

    let info: MascotInfo
    let manifest: MascotManifest
    let frameSize: CGSize
    private let frames: [MascotMood: [CGImage]]

    var fps: Double { Double(manifest.fps) }

    /// The frames of a mood; a pack that does not draw it plays its calm frames.
    func frames(for mood: MascotMood) -> [CGImage] {
        frames[mood] ?? frames[.calm] ?? []
    }

    static func load(_ info: MascotInfo) throws -> MascotPack {
        guard
            let manifestData = try? Data(contentsOf: info.directory.appendingPathComponent("mascot.json")),
            let manifest = try? JSONDecoder().decode(MascotManifest.self, from: manifestData),
            let source = CGImageSourceCreateWithURL(info.directory.appendingPathComponent("sprites.png") as CFURL, nil),
            let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw LoadError.unreadable }
        do {
            try manifest.validate(sheetWidth: sheet.width, sheetHeight: sheet.height)
        } catch let problem as MascotManifest.Problem {
            throw LoadError.invalid(problem)
        }

        let width = manifest.frame.width, height = manifest.frame.height
        var frames: [MascotMood: [CGImage]] = [:]
        for mood in MascotMood.allCases where manifest.states[mood.rawValue] != nil {
            let clip = manifest.clip(for: mood)
            frames[mood] = (0 ..< clip.frames).compactMap { column in
                sheet.cropping(to: CGRect(x: column * width, y: clip.row * height, width: width, height: height))
            }
        }
        guard frames[.calm]?.isEmpty == false else { throw LoadError.unreadable }
        return MascotPack(info: info, manifest: manifest, frameSize: CGSize(width: width, height: height), frames: frames)
    }
}

/// Finds the built-in mascots and the ones the user dropped into the support folder.
enum MascotLibrary {
    static let defaultID = "brasa"
    private static let userPrefix = "user:"
    private static let builtInOrder = ["brasa", "byte", "gota", "broto", "nimbo", "seixo"]

    static var userFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PRPulse/Mascots", isDirectory: true)
    }

    static func available() -> [MascotInfo] {
        builtIn() + user()
    }

    static func info(id: String) -> MascotInfo? {
        available().first { $0.id == id }
    }

    /// The pack with this id, or the default one when it is gone or broken.
    static func load(id: String) -> MascotPack? {
        if let info = info(id: id), let pack = try? MascotPack.load(info) { return pack }
        guard let fallback = info(id: defaultID) else { return nil }
        return try? MascotPack.load(fallback)
    }

    /// Every pack that loads, kept while a screen with previews is open and dropped when it closes.
    @MainActor private static var previews: [MascotPack] = []

    @MainActor static func loadPreviews() -> [MascotPack] {
        if previews.isEmpty { previews = available().compactMap { try? MascotPack.load($0) } }
        return previews
    }

    @MainActor static func dropPreviews() {
        previews = []
    }

    private static func builtIn() -> [MascotInfo] {
        guard let root = Bundle.module.url(forResource: "Mascots", withExtension: nil) else { return [] }
        return builtInOrder.compactMap { folder in
            let directory = root.appendingPathComponent(folder, isDirectory: true)
            return describe(directory, id: folder, isBuiltIn: true)
        }
    }

    private static func user() -> [MascotInfo] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: userFolder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return folders
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { describe($0, id: userPrefix + $0.lastPathComponent, isBuiltIn: false) }
    }

    private static func describe(_ directory: URL, id: String, isBuiltIn: Bool) -> MascotInfo? {
        guard
            let data = try? Data(contentsOf: directory.appendingPathComponent("mascot.json")),
            let manifest = try? JSONDecoder().decode(MascotManifest.self, from: data)
        else { return nil }
        return MascotInfo(id: id, name: manifest.name, directory: directory, isBuiltIn: isBuiltIn)
    }
}
