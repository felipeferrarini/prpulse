public enum OrganizationChoice {
    public enum Result: Equatable {
        case keep
        case pick([String])
        case choose
        case missing(String)
    }

    /// Decides what to do with the chosen organizations after the token's organizations were loaded.
    /// It never adds an organization on its own when the user has options to pick from.
    public static func resolve(current: [String], available: [String], isSetup: Bool) -> Result {
        if current.isEmpty { return available.count == 1 ? .pick([available[0]]) : .choose }
        let gone = current.filter { !available.contains($0) }
        guard let first = gone.first else { return .keep }
        guard isSetup else { return .missing(first) }
        let kept = current.filter { available.contains($0) }
        return kept.isEmpty ? .choose : .pick(kept)
    }
}
