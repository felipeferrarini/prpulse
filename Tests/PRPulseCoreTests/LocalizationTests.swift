import Foundation
import Testing

private let appSources = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Sources/PRPulse")

private func strings(_ language: String) throws -> [String: String] {
    let url = appSources.appendingPathComponent("Resources/\(language).lproj/Localizable.strings")
    let table = try #require(NSDictionary(contentsOf: url) as? [String: String], "cannot parse \(url.path)")
    return table
}

private func keyLiteralsInSources() throws -> Set<String> {
    let pattern = try NSRegularExpression(pattern: #""((?:popover|error|reason|notification|setup|settings|lane|chip|wait|wizard|menu|diag|row|mascot|agents)\.[A-Za-z0-9.]+)""#)
    var found = Set<String>()
    let files = try #require(FileManager.default.enumerator(at: appSources, includingPropertiesForKeys: nil))
    for case let url as URL in files where url.pathExtension == "swift" {
        let text = try String(contentsOf: url, encoding: .utf8)
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range(at: 1), in: text) else { continue }
            let key = String(text[range])
            if !key.hasSuffix(".json") { found.insert(key) }
        }
    }
    return found
}

private func placeholders(_ text: String) -> [String] {
    let pattern = try! NSRegularExpression(pattern: "%[0-9$]*[dDf@]")
    return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
        Range($0.range, in: text).map { String(text[$0]) }
    }
}

@Test func bothLanguagesHaveTheSameKeys() throws {
    let english = Set(try strings("en").keys)
    let portuguese = Set(try strings("pt").keys)

    #expect(english.subtracting(portuguese).isEmpty, "missing in pt-BR: \(english.subtracting(portuguese).sorted())")
    #expect(portuguese.subtracting(english).isEmpty, "missing in en: \(portuguese.subtracting(english).sorted())")
}

@Test func bothLanguagesUseTheSamePlaceholders() throws {
    let english = try strings("en")
    let portuguese = try strings("pt")
    for (key, text) in english {
        #expect(placeholders(text) == placeholders(portuguese[key] ?? ""), "placeholder mismatch in \(key)")
    }
}

@Test func everyKeyUsedInTheAppIsDefined() throws {
    let defined = Set(try strings("en").keys)
    let missing = try keyLiteralsInSources().subtracting(defined)
    #expect(missing.isEmpty, "keys used but not defined: \(missing.sorted())")
}

@Test func noDefinedKeyIsUnused() throws {
    let used = try keyLiteralsInSources()
    let unused = Set(try strings("en").keys).subtracting(used).subtracting(["app.name"])
    #expect(unused.isEmpty, "keys defined but never used: \(unused.sorted())")
}

@Test func noTranslationIsEmpty() throws {
    for language in ["en", "pt"] {
        for (key, text) in try strings(language) {
            #expect(!text.trimmingCharacters(in: .whitespaces).isEmpty, "\(language) \(key) is empty")
        }
    }
}
