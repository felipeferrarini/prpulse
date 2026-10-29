import Foundation

enum GraphQLResponse {
    static func data(from raw: Data) throws -> JSONObject {
        guard let root = try? JSONSerialization.jsonObject(with: raw) as? JSONObject else {
            throw GitHubError.malformed("response is not a JSON object")
        }
        let errors = root.array("errors")
        try throwBlockingError(in: errors)
        guard let data = root.object("data") else {
            throw GitHubError.malformed(errors.first?.string("message") ?? "empty response")
        }
        return data
    }

    private static func throwBlockingError(in errors: [JSONObject]) throws {
        if errors.contains(where: { $0.string("type") == "RATE_LIMITED" }) {
            throw GitHubError.rateLimited(retryAfter: nil)
        }
        if errors.contains(where: { $0.string("message")?.localizedCaseInsensitiveContains("SAML") == true }) {
            throw GitHubError.ssoRequired(org: nil)
        }
    }
}
