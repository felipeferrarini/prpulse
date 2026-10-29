enum ChecksMapper {
    private static let failedConclusions: Set<String> = ["FAILURE", "TIMED_OUT", "STARTUP_FAILURE"]
    private static let requiredActionConclusions = failedConclusions.union(["CANCELLED", "ACTION_REQUIRED", "STALE"])
    private static let greenConclusions: Set<String> = ["SUCCESS", "NEUTRAL", "SKIPPED"]

    static func state(rollup: JSONObject?) -> ChecksState {
        guard let rollup else { return .none }
        let contexts = rollup.nodes("contexts")
        let required = contexts.filter { $0.bool("isRequired") == true }
        return required.isEmpty ? fallbackState(rollup, contexts) : requiredState(required)
    }

    private static func requiredState(_ contexts: [JSONObject]) -> ChecksState {
        if contexts.contains(where: { isFailed($0, conclusions: requiredActionConclusions) }) { return .failing }
        if contexts.contains(where: isPending) { return .pending }
        return contexts.allSatisfy(isGreen) ? .passing : .none
    }

    private static func fallbackState(_ rollup: JSONObject, _ contexts: [JSONObject]) -> ChecksState {
        if contexts.contains(where: { isFailed($0, conclusions: failedConclusions) }) { return .failing }
        if contexts.contains(where: isPending) { return .pending }
        if !contexts.isEmpty { return contexts.allSatisfy(isGreen) ? .passing : .none }
        switch rollup.string("state") {
        case "FAILURE", "ERROR": return .failing
        case "PENDING", "EXPECTED": return .pending
        case "SUCCESS": return .passing
        default: return .none
        }
    }

    private static func isFailed(_ context: JSONObject, conclusions: Set<String>) -> Bool {
        if context.string("__typename") == "CheckRun" {
            return conclusions.contains(context.string("conclusion") ?? "")
        }
        return ["FAILURE", "ERROR"].contains(context.string("state") ?? "")
    }

    private static func isPending(_ context: JSONObject) -> Bool {
        if context.string("__typename") == "CheckRun" {
            return (context.string("status") ?? "COMPLETED") != "COMPLETED"
        }
        return ["PENDING", "EXPECTED"].contains(context.string("state") ?? "")
    }

    private static func isGreen(_ context: JSONObject) -> Bool {
        if context.string("__typename") == "CheckRun" {
            return greenConclusions.contains(context.string("conclusion") ?? "")
        }
        return context.string("state") == "SUCCESS"
    }
}
