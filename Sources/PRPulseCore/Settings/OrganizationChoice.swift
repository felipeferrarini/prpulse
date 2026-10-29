public enum OrganizationChoice {
    public enum Result: Equatable {
        case keep
        case pick(String)
        case choose
        case missing(String)
    }

    /// Decides what to do with the organization after the token's organizations were loaded.
    /// It never switches to another organization on its own when the user has options to pick from.
    public static func resolve(current: String, available: [String], isSetup: Bool) -> Result {
        if available.contains(current) { return .keep }
        if current.isEmpty { return available.count == 1 ? .pick(available[0]) : .choose }
        return isSetup ? .choose : .missing(current)
    }
}
