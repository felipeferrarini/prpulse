import Foundation
import PRPulseCore

func tr(_ key: String) -> String {
    NSLocalizedString(key, bundle: .module, comment: "")
}

func tr(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: tr(key), arguments: arguments)
}

extension LinkFormat {
    var title: String {
        switch self {
        case .links: tr("batch.format.links")
        case .titled: tr("batch.format.titled")
        case .markdown: tr("batch.format.markdown")
        }
    }
}
