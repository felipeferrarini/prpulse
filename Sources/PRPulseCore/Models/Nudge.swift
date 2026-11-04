import Foundation

/// A nudge found on a pull request: a comment its author left to ask a reviewer to look at it again.
public struct NudgeSnapshot: Equatable, Hashable, Sendable {
    public let id: String
    public let recipient: String
    /// 1 for the first nudge to this reviewer, up to `NudgeCodec.maxTone`: each is louder than the one before.
    public let tone: Int
    public let message: String?
    public let author: Actor
    public let createdAt: Date

    public init(id: String, recipient: String, tone: Int, message: String?, author: Actor, createdAt: Date) {
        self.id = id
        self.recipient = recipient
        self.tone = tone
        self.message = message
        self.author = author
        self.createdAt = createdAt
    }
}

/// The hidden marker a nudge carries in its comment, so another PRPulse can tell a nudge from any other comment.
///
/// `<!-- prpulse:nudge v1 to=octocat id=7F3A tone=2 msg=SGVsbG8 -->`
public enum NudgeCodec {
    public static let maxMessageLength = 140
    public static let maxTone = 3

    private static let opening = "<!-- prpulse:nudge v1 "
    private static let closing = " -->"

    /// One line of at most `maxMessageLength` characters that cannot close the marker. Nil when nothing is left.
    public static func clean(_ message: String?) -> String? {
        guard var text = message else { return nil }
        var previous: String
        repeat {
            previous = text
            text = text.replacingOccurrences(of: "<!--", with: "").replacingOccurrences(of: "-->", with: "")
        } while text != previous
        let singleLine = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !singleLine.isEmpty else { return nil }
        return String(singleLine.prefix(maxMessageLength))
    }

    public static func marker(recipient: String, id: String, tone: Int, message: String?) -> String {
        var fields = ["to=\(recipient)", "id=\(id)", "tone=\(min(max(tone, 1), maxTone))"]
        if let message = clean(message) { fields.append("msg=\(encode(message))") }
        return opening + fields.joined(separator: " ") + closing
    }

    /// The comment: the text people read, then the marker.
    public static func body(text: String, recipient: String, id: String, tone: Int, message: String?) -> String {
        text + "\n" + marker(recipient: recipient, id: id, tone: tone, message: message)
    }

    public static func parse(_ body: String, author: Actor, createdAt: Date) -> NudgeSnapshot? {
        guard let start = body.range(of: opening), let end = body.range(of: closing, range: start.upperBound ..< body.endIndex) else {
            return nil
        }
        var fields: [String: String] = [:]
        for pair in body[start.upperBound ..< end.lowerBound].split(separator: " ") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 { fields[String(parts[0])] = String(parts[1]) }
        }
        guard let recipient = fields["to"], let id = fields["id"], !recipient.isEmpty, !id.isEmpty, id.count <= 64,
              let tone = fields["tone"].flatMap(Int.init), (1 ... maxTone).contains(tone)
        else { return nil }
        let message = fields["msg"].flatMap(decode).flatMap(clean)
        return NudgeSnapshot(id: id, recipient: recipient, tone: tone, message: message, author: author, createdAt: createdAt)
    }

    private static func encode(_ message: String) -> String {
        Data(message.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func decode(_ text: String) -> String? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64).flatMap { String(data: $0, encoding: .utf8) }
    }
}
