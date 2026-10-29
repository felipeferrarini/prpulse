import Foundation

func tr(_ key: String) -> String {
    NSLocalizedString(key, bundle: .module, comment: "")
}

func tr(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: tr(key), arguments: arguments)
}
