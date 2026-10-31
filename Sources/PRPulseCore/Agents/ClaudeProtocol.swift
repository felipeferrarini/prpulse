import Foundation

/// The lines PRPulse writes to `claude -p --input-format stream-json`, one JSON object per line.
public enum ClaudeProtocol {
    public static func userMessage(_ text: String) -> String {
        line(["type": "user", "message": ["role": "user", "content": text]])
    }

    /// The answer to a `can_use_tool` request. Allowing hands the tool its input back unchanged.
    public static func permissionResponse(requestID: String, allow: Bool, input: Data, denial: String) -> String {
        let body: [String: Any]
        if allow {
            let object = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] ?? [:]
            body = ["behavior": "allow", "updatedInput": object]
        } else {
            body = ["behavior": "deny", "message": denial]
        }
        return line(["type": "control_response", "response": ["subtype": "success", "request_id": requestID, "response": body]])
    }

    /// Stops what the agent is doing now and leaves the session open for the next message.
    public static func interruptRequest(id: String) -> String {
        line(["type": "control_request", "request_id": id, "request": ["subtype": "interrupt"]])
    }

    private static func line(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
