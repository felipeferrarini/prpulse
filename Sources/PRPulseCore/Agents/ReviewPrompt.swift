import Foundation

/// The words sent to the agent. Only the pull request's address and number go in, never its title or body: those
/// come from other people and could carry instructions.
public enum ReviewPrompt {
    public static let placeholders = ["{url}", "{repo}", "{number}", "{skill}"]

    private static let token = try! NSRegularExpression(pattern: #"\{(url|repo|number|skill)\}"#)

    public static func render(_ template: String, for request: ReviewRequest, skill: String? = nil) -> String {
        let values = [
            "url": request.url.absoluteString,
            "repo": "\(request.ref.owner)/\(request.ref.repo)",
            "number": String(request.ref.number),
            "skill": skill ?? "",
        ]
        var result = ""
        var cursor = template.startIndex
        for match in token.matches(in: template, range: NSRange(template.startIndex..., in: template)) {
            guard let whole = Range(match.range, in: template), let name = Range(match.range(at: 1), in: template) else { continue }
            result += template[cursor ..< whole.lowerBound]
            result += values[String(template[name])] ?? ""
            cursor = whole.upperBound
        }
        return result + template[cursor...]
    }

    /// The viewer's own text wins; otherwise the one that names the skill, when there is one.
    public static func template(custom: String, generic: String, withSkill: String, skill: String?) -> String {
        if !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return custom }
        return skill == nil ? generic : withSkill
    }
}
