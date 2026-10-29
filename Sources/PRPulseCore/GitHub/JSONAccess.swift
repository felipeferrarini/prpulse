import Foundation

typealias JSONObject = [String: Any]

extension Dictionary where Key == String, Value == Any {
    func object(_ key: String) -> JSONObject? { self[key] as? JSONObject }

    func array(_ key: String) -> [JSONObject] { (self[key] as? [Any])?.compactMap { $0 as? JSONObject } ?? [] }

    func string(_ key: String) -> String? { self[key] as? String }

    func bool(_ key: String) -> Bool? { self[key] as? Bool }

    func int(_ key: String) -> Int? { self[key] as? Int }

    func nodes(_ key: String) -> [JSONObject] { object(key)?.array("nodes") ?? [] }
}

func parseDate(_ text: String?) -> Date? {
    guard let text else { return nil }
    return try? Date(text, strategy: .iso8601)
}
