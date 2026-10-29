import Testing
@testable import PRPulseCore

private func rollup(_ state: String, _ contexts: [[String: Any]]) -> [String: Any] {
    ["state": state, "contexts": ["nodes": contexts]]
}

private func run(_ conclusion: String?, status: String = "COMPLETED", required: Bool) -> [String: Any] {
    ["__typename": "CheckRun", "name": "check", "conclusion": conclusion as Any, "status": status, "isRequired": required]
}

private func statusContext(_ state: String, required: Bool) -> [String: Any] {
    ["__typename": "StatusContext", "context": "ci", "state": state, "isRequired": required]
}

@Test func requiredFailureIsFailing() {
    let state = ChecksMapper.state(rollup: rollup("FAILURE", [run("FAILURE", required: true)]))
    #expect(state == .failing)
}

@Test func requiredStatusContextErrorIsFailing() {
    let state = ChecksMapper.state(rollup: rollup("ERROR", [statusContext("ERROR", required: true)]))
    #expect(state == .failing)
}

@Test func requiredRunningIsPendingAndRequiredGreenIsPassing() {
    let running = rollup("PENDING", [run(nil, status: "IN_PROGRESS", required: true)])
    #expect(ChecksMapper.state(rollup: running) == .pending)

    let green = rollup("SUCCESS", [run("SUCCESS", required: true)])
    #expect(ChecksMapper.state(rollup: green) == .passing)
}

@Test func optionalFailureAndCancelledNeverCountWhenRequiredChecksExist() {
    let contexts = [run("SUCCESS", required: true), run("FAILURE", required: false), run("CANCELLED", required: false)]
    #expect(ChecksMapper.state(rollup: rollup("FAILURE", contexts)) == .passing)
}

@Test func requiredCheckThatNeedsActionIsFailing() {
    for conclusion in ["CANCELLED", "ACTION_REQUIRED", "STALE", "TIMED_OUT"] {
        let state = ChecksMapper.state(rollup: rollup("FAILURE", [run(conclusion, required: true)]))
        #expect(state == .failing, "required \(conclusion)")
    }
}

@Test func withoutRequiredContextsAFailedCheckCountsEvenWhenMergeIsBlocked() {
    let contexts = [run("FAILURE", required: false)]
    #expect(ChecksMapper.state(rollup: rollup("FAILURE", contexts)) == .failing)
    #expect(ChecksMapper.state(rollup: rollup("FAILURE", contexts)) == .failing)
}

@Test func withoutRequiredContextsCancelledAndSkippedOptionalChecksAreNotFailures() {
    let contexts = [run("CANCELLED", required: false), run("SKIPPED", required: false), statusContext("SUCCESS", required: false)]
    #expect(ChecksMapper.state(rollup: rollup("FAILURE", contexts)) == .none)
}

@Test func withoutRequiredContextsRunningChecksArePending() {
    let contexts = [run("SUCCESS", required: false), run(nil, status: "IN_PROGRESS", required: false)]
    #expect(ChecksMapper.state(rollup: rollup("PENDING", contexts)) == .pending)
}

@Test func withoutRequiredContextsRollupStatesMapDirectly() {
    #expect(ChecksMapper.state(rollup: rollup("PENDING", [])) == .pending)
    #expect(ChecksMapper.state(rollup: rollup("SUCCESS", [])) == .passing)
    #expect(ChecksMapper.state(rollup: nil) == .none)
}
