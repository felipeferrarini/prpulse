import Foundation

/// A tool the agent wants to use and is not allowed to without asking.
public struct ToolRequest: Equatable, Sendable {
    public let id: String
    public let tool: String
    /// What it wants to do, in a few words: the command, the file, the address.
    public let summary: String
    /// The input of the tool as the agent wrote it; it goes back unchanged when the viewer allows it.
    public let input: Data

    public init(id: String, tool: String, summary: String, input: Data) {
        self.id = id
        self.tool = tool
        self.summary = summary
        self.input = input
    }
}

/// What matters in one line of `claude -p --output-format stream-json`.
public enum ClaudeStreamEvent: Equatable, Sendable {
    case session(String)
    /// The agent is using a tool; `detail` is what it works on, when that is short and clear.
    case tool(name: String, detail: String?)
    case writing
    case permission(ToolRequest)
    /// The agent no longer waits for the answer to this request.
    case permissionCancelled(String)
    case result(text: String, isError: Bool, sessionID: String?)
}

public enum ClaudeStream {
    private static let summaryLimit = 600

    public static func events(in line: String) -> [ClaudeStreamEvent] {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { return [] }
        switch type {
        case "system": return session(object)
        case "assistant": return assistant(object)
        case "result": return [result(object)]
        case "control_request": return permission(object)
        case "control_cancel_request": return (object["request_id"] as? String).map { [.permissionCancelled($0)] } ?? []
        default: return []
        }
    }

    private static func permission(_ object: [String: Any]) -> [ClaudeStreamEvent] {
        guard let id = object["request_id"] as? String,
              let request = object["request"] as? [String: Any],
              request["subtype"] as? String == "can_use_tool",
              let tool = request["tool_name"] as? String else { return [] }
        let input = request["input"] as? [String: Any] ?? [:]
        let data = (try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])) ?? Data("{}".utf8)
        let summary = summary(of: tool, input: input, description: request["description"] as? String, json: data)
        return [.permission(ToolRequest(id: id, tool: request["display_name"] as? String ?? tool, summary: summary, input: data))]
    }

    private static func summary(of tool: String, input: [String: Any], description: String?, json: Data) -> String {
        let value: String? = switch tool {
        case "Bash": input["command"] as? String
        case "Write", "Edit", "MultiEdit": input["file_path"] as? String
        case "NotebookEdit": input["notebook_path"] as? String
        case "WebFetch": input["url"] as? String
        case "WebSearch": input["query"] as? String
        default: description
        }
        let text = value.flatMap { $0.isEmpty ? nil : $0 } ?? String(decoding: json, as: UTF8.self)
        return text.count > summaryLimit ? String(text.prefix(summaryLimit)) + "…" : text
    }

    private static func session(_ object: [String: Any]) -> [ClaudeStreamEvent] {
        guard object["subtype"] as? String == "init", let id = object["session_id"] as? String else { return [] }
        return [.session(id)]
    }

    private static func assistant(_ object: [String: Any]) -> [ClaudeStreamEvent] {
        guard let message = object["message"] as? [String: Any], let content = message["content"] as? [[String: Any]] else { return [] }
        return content.compactMap { block in
            switch block["type"] as? String {
            case "tool_use":
                guard let name = block["name"] as? String else { return nil }
                return .tool(name: name, detail: detail(of: name, input: block["input"] as? [String: Any] ?? [:]))
            case "text":
                return .writing
            default:
                return nil
            }
        }
    }

    private static func result(_ object: [String: Any]) -> ClaudeStreamEvent {
        let subtype = object["subtype"] as? String ?? ""
        let isError = object["is_error"] as? Bool ?? (subtype != "success")
        let text = (object["result"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? subtype
        return .result(text: text, isError: isError, sessionID: object["session_id"] as? String)
    }

    private static func detail(of tool: String, input: [String: Any]) -> String? {
        let value: String? = switch tool {
        case "Read": (input["file_path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
        case "Grep", "Glob": input["pattern"] as? String
        case "Bash": input["command"] as? String
        case "Skill": input["skill"] as? String ?? input["name"] as? String
        case "Task", "Agent": input["description"] as? String
        default: nil
        }
        guard let value else { return nil }
        let line = value.split(separator: "\n").first.map(String.init) ?? value
        return line.count > 70 ? String(line.prefix(70)) + "…" : line
    }
}
