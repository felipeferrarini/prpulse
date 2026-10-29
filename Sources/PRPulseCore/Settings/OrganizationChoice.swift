public enum OrganizationChoice {
    public enum Result: Equatable {
        case keep
        case pick(String)
        case missing(String)
    }

    public static func resolve(current: String, available: [String], defaultChoice: String, autoPick: Bool) -> Result {
        if available.contains(current) { return .keep }
        if current.isEmpty || autoPick { return .pick(defaultChoice) }
        return .missing(current)
    }
}
